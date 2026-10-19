import AppKit

/// Lays a tab's panes out by its PaneTree, draws the 1-point dividers and
/// lets them be dragged, and outlines the focused pane when there are
/// several (docs/spec/tabs.md, "Divisões").
final class PaneLayoutView: NSView {
    /// Space between panes, where the divider line is drawn and grabbed.
    static let gap: CGFloat = 1
    /// No pane gets smaller than this by dragging or splitting.
    static let minPaneSize = CGSize(width: 120, height: 60)
    /// How far from the line a drag still grabs the divider.
    private static let grabSlack: CGFloat = 3

    var tree: PaneTree = .leaf(0) { didSet { needsLayout = true } }
    var panes: [Int: NSView] = [:]
    var focused: Int? { didSet { outline.needsDisplay = true; needsLayout = true } }
    /// The tree after a divider drag.
    var onTreeChange: ((PaneTree) -> Void)?

    private let outline = FocusOutlineView()
    private var dragging: (path: [Bool], axis: PaneTree.Axis, area: CGRect)?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        outline.autoresizingMask = [.width, .height]
        addSubview(outline)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneLayoutView is created in code") }

    /// Puts exactly the tree's panes in the view, outline on top.
    func syncSubviews() {
        let wanted = Set(tree.leaves.compactMap { panes[$0] }.map(ObjectIdentifier.init))
        for view in subviews where view !== outline && !wanted.contains(ObjectIdentifier(view)) {
            view.removeFromSuperview()
        }
        for id in tree.leaves {
            guard let view = panes[id], view.superview !== self else { continue }
            addSubview(view, positioned: .below, relativeTo: outline)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let frames = tree.frames(in: bounds, gap: Self.gap)
        needsDisplay = true
        for (id, frame) in frames {
            panes[id]?.frame = frame
        }
        outline.frame = bounds
        outline.focusFrame = tree.leaves.count > 1 ? focused.flatMap { frames[$0] } : nil
    }

    /// Only the divider lines: filling the whole view would hide a
    /// background image behind the terminals.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        for divider in dividers(of: tree, in: bounds, path: []) { divider.line.fill() }
    }

    /// Whether pane `id` has room to be split along `axis`.
    func canSplit(_ id: Int, axis: PaneTree.Axis) -> Bool {
        guard let frame = tree.frames(in: bounds, gap: Self.gap)[id] else { return false }
        switch axis {
        case .horizontal: return (frame.width - Self.gap) / 2 >= Self.minPaneSize.width
        case .vertical: return (frame.height - Self.gap) / 2 >= Self.minPaneSize.height
        }
    }

    // MARK: Dragging dividers

    override func resetCursorRects() {
        for divider in dividers(of: tree, in: bounds, path: []) {
            addCursorRect(divider.line.insetBy(dx: -Self.grabSlack, dy: -Self.grabSlack),
                          cursor: divider.axis == .horizontal ? .resizeLeftRight : .resizeUpDown)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if divider(at: local) != nil { return self }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = divider(at: point) else { return }
        dragging = (hit.path, hit.axis, hit.area)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag = dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        let horizontal = drag.axis == .horizontal
        let length = horizontal ? drag.area.width : drag.area.height
        let minimum = horizontal ? Self.minPaneSize.width : Self.minPaneSize.height
        let offset = horizontal ? point.x - drag.area.minX : point.y - drag.area.minY
        guard length > minimum * 2 else { return }
        let ratio = min(max(offset, minimum), length - minimum) / length
        tree = tree.settingRatio(ratio, at: drag.path)
        onTreeChange?(tree)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        dragging = nil
    }

    private struct Divider {
        let path: [Bool]
        let axis: PaneTree.Axis
        /// The split node's whole area.
        let area: CGRect
        let line: CGRect
    }

    private func divider(at point: CGPoint) -> Divider? {
        dividers(of: tree, in: bounds, path: []).first {
            $0.line.insetBy(dx: -Self.grabSlack, dy: -Self.grabSlack).contains(point)
        }
    }

    private func dividers(of node: PaneTree, in rect: CGRect, path: [Bool]) -> [Divider] {
        guard case .split(let axis, let a, let b, let ratio) = node else { return [] }
        let (first, second) = PaneTree.divide(rect, axis: axis, ratio: ratio, gap: Self.gap)
        let line = axis == .horizontal
            ? CGRect(x: first.maxX, y: rect.minY, width: Self.gap, height: rect.height)
            : CGRect(x: rect.minX, y: first.maxY, width: rect.width, height: Self.gap)
        return [Divider(path: path, axis: axis, area: rect, line: line)]
            + dividers(of: a, in: first, path: path + [false])
            + dividers(of: b, in: second, path: path + [true])
    }
}

/// The discreet outline around the focused pane. Draws over the panes and
/// lets every click through.
private final class FocusOutlineView: NSView {
    var focusFrame: CGRect? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let focusFrame else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.5).setStroke()
        let path = NSBezierPath(rect: focusFrame.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }
}
