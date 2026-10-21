import AppKit

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

    override var isFlipped: Bool { true }

    static func width(lanes: Int) -> CGFloat {
        margin * 2 + CGFloat(min(max(lanes, 1), maxLanes)) * laneWidth
    }

    static func color(_ index: Int) -> NSColor {
        palette[index % palette.count]
    }

    private func x(_ lane: Int) -> CGFloat {
        Self.margin + (CGFloat(lane) + 0.5) * Self.laneWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        for s in passing { line(from: NSPoint(x: x(s.to), y: 0), to: NSPoint(x: x(s.to), y: bounds.height), color: s.color) }
        guard let graph else { return }
        let mid = bounds.midY
        let height = bounds.height
        for s in graph.top { line(from: NSPoint(x: x(s.from), y: 0), to: NSPoint(x: x(s.to), y: mid), color: s.color) }
        for s in graph.bottom { line(from: NSPoint(x: x(s.from), y: mid), to: NSPoint(x: x(s.to), y: height), color: s.color) }
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
        path.lineWidth = 2
        Self.color(color).setStroke()
        path.stroke()
    }
}
