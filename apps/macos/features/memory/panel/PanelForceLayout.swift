import Foundation

/// Where the graph's nodes sit (plan 40 E): a force layout, not upstream's circle (the owner,
/// 2026-11-19, "pode fazer o 2": with many pages the circle is a tangle). Linked pages pull
/// together into groups, every node pushes the others away, and a node with no link feels only a
/// weak pull to the center, so the loose ones settle around the edge.
///
/// Fruchterman–Reingold with a cooling step over the linked nodes, rings for the loose ones, then
/// a pass that parts nodes closer than `minGap`. Deterministic: the start is a sunflower spiral
/// turned by `seed`, nothing random, so the same
/// graph lands the same way every time (stable snapshots). O(n²) a step; the engine caps a
/// project's graph at 120 nodes (upstream's PROJECT_LINK_GRAPH_MAX_NODES), and `iterations`
/// shrinks as n grows, so a full graph stays near 2 M pair visits; the view computes it off the
/// main thread past `PanelForceLayout.offMainFrom` nodes.
public struct PanelForceLayout: Sendable {
    /// The square the nodes land in, its side in points (components.memoryPanel.graph.size).
    public var side: Double = 600
    /// The least distance between two node centers once laid out.
    public var minGap: Double = 22
    public var seed: UInt64 = 40
    /// The steps cap; the real count is `steps(for:)`.
    public var iterations = 300
    /// From this many nodes the view lays out off the main thread.
    public static let offMainFrom = 40

    public init(side: Double = 600, minGap: Double = 22, seed: UInt64 = 40) {
        self.side = side
        self.minGap = minGap
        self.seed = seed
    }

    func steps(for n: Int) -> Int { n <= 1 ? 0 : min(iterations, max(60, 2_000_000 / max(1, n * n))) }

    /// Each node's center in `0...side`, in node order. `edges` are index pairs; self links and
    /// repeats count once. The linked nodes are laid out by forces in the middle disc; the loose
    /// ones go round it on rings at the edge; with no link at all, a sunflower fills the square.
    public func place(count n: Int, edges: [(Int, Int)]) -> [CGPoint] {
        guard n > 0 else { return [] }
        if n == 1 { return [CGPoint(x: side / 2, y: side / 2)] }
        var links = Set<Pair>()
        for (a, b) in edges where a != b && a >= 0 && b >= 0 && a < n && b < n { links.insert(Pair(a, b)) }
        var degree = [Int](repeating: 0, count: n)
        for link in links { degree[link.a] += 1; degree[link.b] += 1 }
        let linked = (0..<n).filter { degree[$0] > 0 }, loose = (0..<n).filter { degree[$0] == 0 }
        var pos = [Vec](repeating: Vec(x: side / 2, y: side / 2), count: n)
        if linked.isEmpty {
            pos = start(n, radius: side / 2 - minGap)
        } else {
            let local = Dictionary(uniqueKeysWithValues: linked.enumerated().map { ($1, $0) })
            let inner = loose.isEmpty ? side / 2 - minGap : side * 0.30
            let placed = forces(linked.count, links.map { Pair(local[$0.a]!, local[$0.b]!) }, inner: inner)
            for (i, node) in linked.enumerated() { pos[node] = placed[i] }
            for (i, node) in loose.enumerated() { pos[node] = ring(i, of: loose.count) }
        }
        return part(pos).map { CGPoint(x: $0.x, y: $0.y) }
    }

    /// Fruchterman–Reingold over the linked nodes, centered and scaled to fill a disc of `inner`
    /// (no more than twice its natural size, so a lone pair does not stretch across the frame).
    private func forces(_ n: Int, _ links: [Pair], inner: Double) -> [Vec] {
        guard n > 1 else { return [Vec(x: side / 2, y: side / 2)] }
        let k = (side * side / Double(n)).squareRoot() * 0.5
        var pos = start(n, radius: inner)
        var temperature = side / 8
        for _ in 0..<steps(for: n) {
            var push = [Vec](repeating: Vec(), count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    var d = pos[i] - pos[j]
                    var dist = d.length
                    if dist < 0.01 { d = Vec(x: 0.01 * Double(i - j), y: 0.01); dist = d.length }
                    let f = d * (k * k / dist / dist)
                    push[i] = push[i] + f
                    push[j] = push[j] - f
                }
            }
            for link in links {
                let d = pos[link.a] - pos[link.b]
                let f = d * (max(d.length, 0.01) / k)
                push[link.a] = push[link.a] - f
                push[link.b] = push[link.b] + f
            }
            let center = Vec(x: side / 2, y: side / 2)
            for i in 0..<n {
                push[i] = push[i] + (center - pos[i]) * (0.08 * k / 10)
                let length = push[i].length
                if length > 0 { pos[i] = pos[i] + push[i] * (min(length, temperature) / length) }
            }
            temperature = max(0.5, temperature * 0.97)
        }
        let mid = pos.reduce(Vec()) { $0 + $1 } * (1 / Double(n))
        let reach = pos.map { ($0 - mid).length }.max() ?? 1
        let scale = min(inner / max(reach, 1), 2)
        return pos.map { Vec(x: side / 2, y: side / 2) + ($0 - mid) * scale }
    }

    /// The `i`th of `count` loose nodes: rings from the edge inward, each as full as `minGap` lets it.
    private func ring(_ i: Int, of count: Int) -> Vec {
        var radius = side / 2 - minGap, index = i, left = count
        while true {
            let fits = max(1, Int(2 * .pi * radius / (minGap * 1.4)))
            let here = min(fits, left)
            if index < here {
                let a = 2 * .pi * Double(index) / Double(here) - .pi / 2 + Double(seed % 360) * .pi / 180
                return Vec(x: side / 2 + radius * cos(a), y: side / 2 + radius * sin(a))
            }
            index -= here
            left -= here
            radius -= minGap * 1.4
        }
    }

    /// The start: a sunflower spiral (golden angle), turned by the seed; even spread, no ties.
    private func start(_ n: Int, radius: Double) -> [Vec] {
        let turn = Double(seed % 360) * .pi / 180
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<n).map { i in
            let r = radius * (Double(i) + 0.5).squareRoot() / Double(n).squareRoot()
            let a = Double(i) * golden + turn
            return Vec(x: side / 2 + r * cos(a), y: side / 2 + r * sin(a))
        }
    }

    /// Nodes closer than `minGap` (after scaling to the square) moved apart, a few rounds.
    private func part(_ input: [Vec]) -> [Vec] {
        var pos = input
        for _ in 0..<50 {
            var moved = false
            for i in 0..<pos.count {
                for j in (i + 1)..<pos.count {
                    var d = pos[i] - pos[j]
                    var dist = d.length
                    guard dist < minGap else { continue }
                    if dist < 0.001 { d = Vec(x: 1, y: Double(i - j)); dist = d.length }
                    let shift = d * ((minGap - dist) / 2 / dist + 0.0001)
                    pos[i] = pos[i] + shift
                    pos[j] = pos[j] - shift
                    moved = true
                }
            }
            for i in pos.indices {
                pos[i].x = min(max(pos[i].x, minGap / 2), side - minGap / 2)
                pos[i].y = min(max(pos[i].y, minGap / 2), side - minGap / 2)
            }
            if !moved { break }
        }
        return pos
    }

    struct Pair: Hashable {
        let a: Int, b: Int
        init(_ x: Int, _ y: Int) { a = min(x, y); b = max(x, y) }
    }

    struct Vec {
        var x = 0.0, y = 0.0
        var length: Double { (x * x + y * y).squareRoot() }
        static func + (l: Vec, r: Vec) -> Vec { Vec(x: l.x + r.x, y: l.y + r.y) }
        static func - (l: Vec, r: Vec) -> Vec { Vec(x: l.x - r.x, y: l.y - r.y) }
        static func * (l: Vec, s: Double) -> Vec { Vec(x: l.x * s, y: l.y * s) }
    }
}
