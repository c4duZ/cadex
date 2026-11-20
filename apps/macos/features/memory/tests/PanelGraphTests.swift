import AppKit
import Checks
import Foundation
import Strings
@testable import Memory

// Grafo de conhecimento (plan 40 E) over the recorded seed (the project's /graph with /pages, and
// /api/v1/graph): the reading, the force layout (the same every run, linked nodes closer than
// loose ones, no two dots overlapping), the canvas's keys, pointer and names, and with
// CADEX_SNAPSHOT_DIR memory-graph.png, memory-graph-global.png and memory-graph-empty.png.

func panelGraphSeed() -> PanelGraph? {
    PanelGraph.parse(project: cadexRef, graph: panelFixture("graph"), pages: panelFixture("pages"))
}

/// The owner's memory as it is (2026-11-19): 49 pages and no link between them.
func panelLooseGraph(_ count: Int = 49) -> PanelGraph {
    var g = PanelGraph(project: cadexRef)
    g.nodes = (0..<count).map { PanelGraphNode(title: "Session \($0)", path: "sessions/\($0).md", project: cadexRef, kind: "session", tier: "episodic") }
    return g
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

private func minGap(_ points: [CGPoint]) -> Double {
    var best = Double.infinity
    for i in points.indices { for j in points.indices where j > i { best = min(best, distance(points[i], points[j])) } }
    return best
}

@MainActor func panelGraphTests() -> [(name: String, body: Checks.Body)] { [
    ("the project's graph: five pages with their kinds, three links; the general one: two projects, one link", {
        guard let g = panelGraphSeed(), let all = PanelGraph.parse(global: panelFixture("graph-global")) else { return expect(false) }
        expect(g.nodes.map(\.path) == ["index.md", "gotchas/socket.md", "decisions/engine.md", "_slots/current-focus.md", "_rules/commit-style.md"])
        expect(g.nodes.map(\.kind) == ["fact", "gotcha", "decision", "fact", "rule"] && g.edges.count == 3 && g.loose == [3, 4], "\(g.loose)")
        expect(g.connections.map(\.from.label) == ["gotchas/socket.md", "index.md", "index.md"] && g.kinds.first == "fact")
        inPortuguese { expect(g.summary == "5 páginas mais recentes · 3 links entre elas" && g.emptyLine == nil, g.summary) }
        expect(all.nodes.map(\.title) == ["cadex", "site"] && all.edges == [.init(from: 1, to: 0)] && all.nodes[0].kind == "project")
        expect(all.connections.map { $0.from.label + " → " + $0.to.label } == ["site:deploy.md → cadex:decisions/engine.md"])
        inPortuguese {
            expect(panelLooseGraph().emptyLine?.hasPrefix("Nenhum link entre estas páginas") == true)
            expect(PanelGraph.parse(global: Data(#"{"edges":[]}"#.utf8))?.emptyLine?.hasPrefix("Ainda não há links entre projetos") == true)
        }
        expect(PanelPlace(arguments: PanelPlace.graph(cadexRef).arguments) == .graph(cadexRef))
        expect(PanelPlace(arguments: ["section": "graph"]) == .graph(nil) && PanelPlace.graph(cadexRef).section == .projects)
        inPortuguese { expect(PanelPlace.graph(cadexRef).crumbs.map(\.title) == ["Projetos", "cadex", "grafo"]) }
        expect(PanelLoads.paths(.graph(cadexRef)) == [cadexRef.api + "/graph", cadexRef.api + "/pages"] && PanelLoads.paths(.graph(nil)) == ["api/v1/graph"])
    }),
    ("the force layout: the same every run, linked pages closer than loose ones, no overlaps, inside the square", {
        guard let g = panelGraphSeed() else { return expect(false) }
        let layout = PanelForceLayout()
        let edges = g.edges.map { ($0.from, $0.to) }
        let a = layout.place(count: g.nodes.count, edges: edges), b = layout.place(count: g.nodes.count, edges: edges)
        expect(a == b, "deterministic")
        let linked = g.edges.map { distance(a[$0.from], a[$0.to]) }.reduce(0, +) / Double(g.edges.count)
        let center = CGPoint(x: 300, y: 300)
        let looseOut = g.loose.map { distance(a[$0], center) }.reduce(0, +) / Double(g.loose.count)
        let linkedOut = [0, 1, 2].map { distance(a[$0], center) }.reduce(0, +) / 3
        let toLoose = [0, 1, 2].flatMap { i in g.loose.map { distance(a[i], a[$0]) } }.reduce(0, +) / Double(3 * g.loose.count)
        expect(linked < toLoose, "linked \(linked) < to loose \(toLoose)")
        expect(looseOut > linkedOut, "loose at the edge: \(looseOut) > \(linkedOut)")
        for points in [a, layout.place(count: 49, edges: []), layout.place(count: 120, edges: (0..<60).map { ($0, ($0 * 7 + 3) % 120) })] {
            expect(minGap(points) >= 10, "no overlaps: \(minGap(points))")
            expect(points.allSatisfy { (0...600).contains($0.x) && (0...600).contains($0.y) })
        }
        expect(layout.place(count: 0, edges: []).isEmpty && layout.place(count: 1, edges: [(0, 0)]) == [CGPoint(x: 300, y: 300)])
    }),
    ("the canvas: Tab and the arrows walk the nodes, Enter and a click open, each node named by title and path, the tip on hover", {
        guard let g = panelGraphSeed() else { return expect(false) }
        var gone: [PanelPlace] = []
        let view = PanelGraphView(g, synchronous: true) { gone.append($0) }
        view.frame = NSRect(x: 0, y: 0, width: 1192, height: 826)
        view.layoutSubtreeIfNeeded()
        let canvas = view.canvas
        expect(canvas.elementLabels.first == "Cadex memory, index.md", "\(canvas.elementLabels)")
        canvas.step(1)
        canvas.step(1)
        expect(canvas.focused == 1 && canvas.tipSaid == "Socket mode gotchas/socket.md", canvas.tipSaid ?? "")
        canvas.move(dx: 1, dy: 0)
        canvas.move(dx: -1, dy: 0)
        expect(canvas.focused != nil)
        canvas.focused = 2
        canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                              characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        expect(gone == [.page(cadexRef, "decisions/engine.md")], "\(gone)")
        canvas.focused = nil
        canvas.hovered = canvas.node(at: canvas.viewPoint(4))
        expect(canvas.tipSaid == "Commit style _rules/commit-style.md")
        canvas.setZoom(2)
        expect(canvas.node(at: canvas.viewPoint(3)) == 3)
        canvas.fit()
        expect(canvas.zoom == 1 && canvas.pan == .zero)
        view.pressConnection(1)
        expect(gone.last == .page(cadexRef, "decisions/engine.md"))
        guard let all = PanelGraph.parse(global: panelFixture("graph-global")) else { return expect(false) }
        let global = PanelGraphView(all, synchronous: true) { gone.append($0) }
        global.canvas.focused = 1
        global.canvas.onOpen?(1)
        expect(gone.last == .graph(PanelProjectRef(name: "site")))
        global.pressConnection(0)
        expect(gone.last == .page(PanelProjectRef(name: "site"), "deploy.md"))
    }),
    ("the page opens the graphs from the section and from a project, reading each graph's routes", {
        let reads = Box<[String]>([])
        let page = panelPage(reads)
        page.show(.graph)
        expect(page.place == .graph(nil) && page.section == .graph && page.screen is PanelGraphView && page.showsGraph, "\(reads.value)")
        page.go(.graph(cadexRef))
        expect((page.screen as? PanelGraphView)?.graph.nodes.count == 5 && page.section == .projects)
        expect(reads.value.suffix(2) == [cadexRef.api + "/graph", cadexRef.api + "/pages"])
        page.fitGraph()
    }),
    ("the graphs drawn (CADEX_SNAPSHOT_DIR: memory-graph.png, memory-graph-global.png, memory-graph-empty.png)", {
        guard ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] != nil, let g = panelGraphSeed(),
              let all = PanelGraph.parse(global: panelFixture("graph-global")) else { return }
        inPortuguese {
            let view = PanelGraphView(g, synchronous: true) { _ in }
            view.canvas.hovered = 2
            panelSnapshot(view, "memory-graph.png")
            panelSnapshot(PanelGraphView(all, synchronous: true) { _ in }, "memory-graph-global.png")
            panelSnapshot(PanelGraphView(panelLooseGraph(), synchronous: true) { _ in }, "memory-graph-empty.png")
        }
    }),
] }
