import AppKit
import Strings
import UILooks

/// The link graph drawn natively (plan 40 E; no WebView, ADR 0001): Core Graphics on the view's
/// layer, the nodes where PanelForceLayout put them. The titles are not written beside the dots
/// (upstream's overlap and do not read, screens-memory.md): the one under the pointer or with the
/// focus shows a tip with its title and path. Click or Enter opens; Tab and the arrows move from
/// node to node, each an accessibility element named by its title and path; a pinch zooms and a
/// two-finger scroll pans (memory.graph-fit puts it back).
@MainActor
final class PanelGraphCanvas: NSView {
    typealias G = MP.Graph
    let graph: PanelGraph
    /// Centers in the layout's square (G.size a side), once laid out.
    private(set) var points: [CGPoint] = []
    private let loose: Set<Int>
    var hovered: Int? { didSet { if hovered != oldValue { refresh() } } }
    var focused: Int? { didSet { if focused != oldValue { refresh() } } }
    private(set) var zoom: CGFloat = 1
    private(set) var pan = CGPoint.zero
    var onOpen: ((Int) -> Void)?
    private let tip = FrameBox()
    private let tipTitle = PanelText.line("", size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.medium)
    private let tipPath = PanelText.line("", size: DesignTokens.FontSize.caption, color: DesignTokens.Color.textMuted)
    private var nodeElements: [NSAccessibilityElement] = []

    init(_ graph: PanelGraph, layout: PanelForceLayout = PanelForceLayout(side: Double(MP.Graph.size)), synchronous: Bool = false) {
        self.graph = graph
        loose = graph.loose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = G.bg.cgColor
        layer?.borderColor = G.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(G.radius)
        layer?.masksToBounds = true
        tip.box(bg: G.Tip.bg, border: G.Tip.border, radius: UILooks.pt(G.Tip.radius))
        tip.hold(PanelText.row([tipTitle, tipPath], gap: MP.Chip.gap), padding: G.Tip.padding)
        tip.isHidden = true
        addSubview(tip)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(graph.project.map { T("Link graph of ", "Grafo de links de ") + PanelGraph.name($0) } ?? T("Link graph", "Grafo de links"))
        let edges = graph.edges.map { ($0.from, $0.to) }
        let count = graph.nodes.count
        if synchronous || count < PanelForceLayout.offMainFrom {
            laidOut(layout.place(count: count, edges: edges))
        } else {
            // A big graph is laid out off the main thread; the frame shows empty until it lands.
            Task.detached(priority: .userInitiated) {
                let placed = layout.place(count: count, edges: edges)
                await MainActor.run { [weak self] in self?.laidOut(placed) }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelGraphCanvas is created in code") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { !graph.nodes.isEmpty }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func laidOut(_ placed: [CGPoint]) {
        points = placed
        nodeElements = graph.nodes.indices.map { index in
            let node = graph.nodes[index]
            let element = NSAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(node.title + ", " + node.place)
            element.setAccessibilityParent(self)
            return element
        }
        setAccessibilityChildren(nodeElements)
        refresh()
    }

    private func refresh() {
        needsDisplay = true
        placeTip()
        updateElementFrames()
    }

    // MARK: Geometry

    /// How the layout's square maps into the view: fitted, then zoomed about the middle and panned.
    private var scale: CGFloat {
        let side = CGFloat(MP.Graph.size)
        return max(0.05, min(bounds.width, bounds.height) / side * zoom)
    }

    func viewPoint(_ index: Int) -> CGPoint {
        let side = CGFloat(MP.Graph.size)
        let p = points[index]
        return CGPoint(x: bounds.midX + (p.x - side / 2) * scale + pan.x, y: bounds.midY + (p.y - side / 2) * scale + pan.y)
    }

    private var radius: CGFloat { UILooks.pt(G.Node.size) / 2 }

    /// The node under `point` (view coordinates), the nearest within a finger's reach.
    func node(at point: CGPoint) -> Int? {
        let reach = max(radius + 4, 8)
        var best: (Int, CGFloat)?
        for index in points.indices {
            let d = hypot(viewPoint(index).x - point.x, viewPoint(index).y - point.y)
            if d <= reach, d < (best?.1 ?? .infinity) { best = (index, d) }
        }
        return best?.0
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext, !points.isEmpty else { return }
        let chosen = focused ?? hovered
        cg.setLineWidth(G.Edge.width)
        for edge in graph.edges {
            let lit = chosen == edge.from || chosen == edge.to
            cg.setStrokeColor((lit ? G.Edge.chosen : G.Edge.color).cgColor)
            cg.move(to: viewPoint(edge.from))
            cg.addLine(to: viewPoint(edge.to))
            cg.strokePath()
        }
        for index in points.indices {
            let center = viewPoint(index)
            let dot = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let color = Self.color(graph.nodes[index].kind)
            // A loose page is a ring in its kind's color: a dimmed dot read as the grey of "fact" in
            // the legend (plan 40 E's prints).
            if loose.contains(index) {
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(DesignTokens.Stroke.glyph)
                cg.strokeEllipse(in: dot.insetBy(dx: DesignTokens.Stroke.glyph / 2, dy: DesignTokens.Stroke.glyph / 2))
                cg.setLineWidth(G.Edge.width)
            } else {
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: dot)
            }
            if index == chosen {
                cg.setStrokeColor(G.focus.cgColor)
                cg.setLineWidth(DesignTokens.Stroke.glyph)
                cg.strokeEllipse(in: dot.insetBy(dx: -3, dy: -3))
                cg.setLineWidth(G.Edge.width)
            }
        }
    }

    /// The dot's color by the page's kind (components.memoryPanel.graph.node.kind).
    static func color(_ kind: String) -> NSColor {
        switch kind {
        case "rule": G.Node.Kind.rule
        case "decision": G.Node.Kind.decision
        case "gotcha": G.Node.Kind.gotcha
        case "session": G.Node.Kind.session
        case "project": G.Node.Kind.project
        default: G.Node.Kind.other
        }
    }

    private func placeTip() {
        guard let index = focused ?? hovered, points.indices.contains(index) else { tip.isHidden = true; return }
        let node = graph.nodes[index]
        tipTitle.stringValue = node.title
        tipPath.stringValue = node.place
        tip.isHidden = false
        tip.layoutSubtreeIfNeeded()
        let size = tip.fittingSize
        let center = viewPoint(index)
        var origin = CGPoint(x: center.x + radius + 6, y: center.y - size.height - radius)
        if origin.x + size.width > bounds.maxX - 4 { origin.x = center.x - radius - 6 - size.width }
        origin.x = max(4, origin.x)
        origin.y = max(4, min(origin.y, bounds.maxY - size.height - 4))
        tip.frame = CGRect(origin: origin, size: size)
    }

    private func updateElementFrames() {
        guard nodeElements.count == points.count else { return }
        for index in points.indices {
            let c = viewPoint(index)
            let rect = CGRect(x: c.x - radius - 2, y: c.y - radius - 2, width: radius * 2 + 4, height: radius * 2 + 4)
            nodeElements[index].setAccessibilityFrameInParentSpace(rect)
            nodeElements[index].setAccessibilityFocused(index == focused)
        }
    }

    override func layout() {
        super.layout()
        refresh()
    }

    // MARK: Pointer and keys

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        hovered = node(at: convert(event.locationInWindow, from: nil))
        if hovered != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseUp(with event: NSEvent) {
        guard let index = node(at: convert(event.locationInWindow, from: nil)) else { return }
        focused = index
        onOpen?(index)
    }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 48: step(shift ? -1 : 1)  // Tab
        case 36, 76: if let focused { onOpen?(focused) } else { super.keyDown(with: event) }
        case 123: move(dx: -1, dy: 0)
        case 124: move(dx: 1, dy: 0)
        case 125: move(dx: 0, dy: 1)
        case 126: move(dx: 0, dy: -1)
        default: super.keyDown(with: event)
        }
    }

    /// Tab: the next node in the graph's order (the engine's: most linked, then newest); past the
    /// last, the focus leaves the graph as Tab does.
    func step(_ by: Int) {
        guard !points.isEmpty else { return }
        guard let current = focused else { focused = by > 0 ? 0 : points.count - 1; return }
        let next = current + by
        guard points.indices.contains(next) else {
            focused = nil
            if by > 0 { window?.selectNextKeyView(self) } else { window?.selectPreviousKeyView(self) }
            return
        }
        focused = next
    }

    /// An arrow: the nearest node that way (within a 45° cone), else the next in order.
    func move(dx: CGFloat, dy: CGFloat) {
        guard let current = focused else { return step(1) }
        let from = viewPoint(current)
        var best: (Int, CGFloat)?
        for index in points.indices where index != current {
            let p = viewPoint(index)
            let (vx, vy) = (p.x - from.x, p.y - from.y)
            let along = vx * dx + vy * dy
            let across = abs(vx * dy - vy * dx)
            guard along > 0, across <= along else { continue }
            let d = along + across * 2
            if d < (best?.1 ?? .infinity) { best = (index, d) }
        }
        focused = best?.0 ?? current
    }

    override func becomeFirstResponder() -> Bool {
        if focused == nil, !points.isEmpty { focused = 0 }
        return true
    }

    override func resignFirstResponder() -> Bool {
        focused = nil
        return true
    }

    override func magnify(with event: NSEvent) {
        zoom = max(0.4, min(6, zoom * (1 + event.magnification)))
        refresh()
    }

    override func scrollWheel(with event: NSEvent) {
        // Only a trackpad's two fingers pan; a mouse wheel scrolls the page around the graph.
        guard event.hasPreciseScrollingDeltas, zoom > 1 else { return super.scrollWheel(with: event) }
        pan.x += event.scrollingDeltaX
        pan.y += event.scrollingDeltaY
        refresh()
    }

    /// memory.graph-fit: the whole graph in the frame again.
    func fit() {
        zoom = 1
        pan = .zero
        refresh()
    }

    /// For tests.
    func setZoom(_ value: CGFloat) { zoom = value; refresh() }
    var elementLabels: [String] { nodeElements.map { $0.accessibilityLabel() ?? "" } }
    var tipSaid: String? { tip.isHidden ? nil : tipTitle.stringValue + " " + tipPath.stringValue }
}
