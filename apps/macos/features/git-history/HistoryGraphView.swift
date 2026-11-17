import AppKit
import UILooks

/// One row of the graph (docs/spec/git-history.md): the lines from the row
/// above to the dot or straight down, the dot, and the lines to the
/// parents' lanes. Rows are drawn one at a time as the table shows them,
/// never the whole graph.
@MainActor
final class HistoryGraphView: NSView {
    static let laneWidth: CGFloat = 12
    static let margin: CGFloat = 8
    /// Lanes past this are cut: the graph column would eat the subjects.
    static let maxLanes = 24

    static let palette: [NSColor] = [
        .systemBlue, .systemPink, .systemGreen, .systemOrange,
        .systemPurple, .systemTeal, .systemYellow, .systemRed,
    ]

    var graph: HistoryCommit.Graph? {
        didSet { needsDisplay = true }
    }
    /// Lanes that only pass through, top to bottom, without a dot: under
    /// an open commit in the sidebar, behind its files.
    var passing: [HistoryCommit.Segment] = [] {
        didSet { needsDisplay = true }
    }
    /// A merge's dot is hollow.
    var isMerge = false
    var isHead = false
    /// The right panel's History tab (plan 26 C2b; components.inspector.commit): one line color,
    /// a 10 pt dot, blue and full on the commit you are on, a ring on the others.
    var compact = false {
        didSet { needsDisplay = true }
    }
    /// What the compact ring is filled with: the row's ground.
    var ground: NSColor = DesignTokens.Inspector.bg
    private typealias C = DesignTokens.Inspector.Commit

    override var isFlipped: Bool { true }

    static func width(lanes: Int, compact: Bool = false) -> CGFloat {
        let lanes = CGFloat(min(max(lanes, 1), maxLanes))
        return compact ? UILooks.pt(C.padding.left) + lanes * UILooks.pt(C.Lane.width) : margin * 2 + lanes * laneWidth
    }

    static func color(_ index: Int) -> NSColor {
        palette[index % palette.count]
    }

    private func x(_ lane: Int) -> CGFloat {
        compact ? UILooks.pt(C.padding.left) + (CGFloat(lane) + 0.5) * UILooks.pt(C.Lane.width)
            : Self.margin + (CGFloat(lane) + 0.5) * Self.laneWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        for s in passing { line(from: NSPoint(x: x(s.to), y: 0), to: NSPoint(x: x(s.to), y: bounds.height), color: s.color) }
        guard let graph else { return }
        let mid = bounds.midY
        let height = bounds.height
        for s in graph.top { line(from: NSPoint(x: x(s.from), y: 0), to: NSPoint(x: x(s.to), y: mid), color: s.color) }
        for s in graph.bottom { line(from: NSPoint(x: x(s.from), y: mid), to: NSPoint(x: x(s.to), y: height), color: s.color) }
        if compact { return drawCompactDot(at: NSPoint(x: x(graph.column), y: mid)) }
        let radius: CGFloat = isHead ? 4.5 : 3.5
        let dot = NSBezierPath(ovalIn: NSRect(x: x(graph.column) - radius, y: mid - radius, width: radius * 2, height: radius * 2))
        let color = Self.color(graph.color)
        if isMerge {
            NSColor.textBackgroundColor.setFill()
            dot.fill()
            color.setStroke()
            dot.lineWidth = 2
            dot.stroke()
        } else {
            color.setFill()
            dot.fill()
        }
    }

    /// Straight when the lane does not move; otherwise an S curve, so
    /// forks and merges read as branches.
    private func line(from a: NSPoint, to b: NSPoint, color: Int) {
        let path = NSBezierPath()
        path.move(to: a)
        if a.x == b.x {
            path.line(to: b)
        } else {
            let bend = (b.y - a.y) / 2
            path.curve(to: b, controlPoint1: NSPoint(x: a.x, y: a.y + bend), controlPoint2: NSPoint(x: b.x, y: b.y - bend))
        }
        path.lineWidth = compact ? C.Lane.stroke : 2
        (compact ? C.Lane.line : Self.color(color)).setStroke()
        path.stroke()
    }

    /// The drawing's dot: full blue on HEAD, a ring over the panel's ground on the others.
    private func drawCompactDot(at center: NSPoint) {
        let size = UILooks.pt(C.Dot.size)
        let ring = C.Lane.stroke
        let box = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        if isHead {
            C.Dot.head.setFill()
            NSBezierPath(ovalIn: box).fill()
            return
        }
        let dot = NSBezierPath(ovalIn: box.insetBy(dx: ring / 2, dy: ring / 2))
        ground.setFill()
        dot.fill()
        C.Dot.ring.setStroke()
        dot.lineWidth = ring
        dot.stroke()
    }
}
