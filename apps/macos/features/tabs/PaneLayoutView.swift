import AppKit

/// Lays a tab's panes out by its PaneTree, draws the 1-point dividers and
/// lets them be dragged, and dims the panes without focus when there are
/// several (docs/spec/tabs.md, "Divisões").
///
/// The owner found the blue focus outline beside the divider crude and the
/// divider hard to grab (2026-10-19): the outline gave way to dimming, as
/// in iTerm2, and the divider grabs 6 pt each side and thickens under the
/// pointer.
final class PaneLayoutView: NSView {
    /// Space between panes, where the divider line is drawn and grabbed.
    static let gap: CGFloat = 1
    /// No pane gets smaller than this by dragging or splitting.
    static let minPaneSize = CGSize(width: 120, height: 60)
    /// How far from the line a drag still grabs the divider.
    private static let grabSlack: CGFloat = 6

    var tree: PaneTree = .leaf(0) { didSet { needsLayout = true } }
    var panes: [Int: NSView] = [:]
    var focused: Int? { didSet { outline.needsDisplay = true; needsLayout = true } }
    /// The tree after a divider drag.
    var onTreeChange: ((PaneTree) -> Void)?
    /// The one pane taking the whole tab (pane.zoom), the others out of view.
    var zoomed: Int? { didSet { if zoomed != oldValue { syncSubviews() } } }
    /// What each pane's header says, from the tab.
    var describe: ((Int) -> PaneHeaderView.Info?)?
    /// A header's click or button, by pane.
    var onHeaderAction: ((Int, PaneHeaderView.Action) -> Void)?
    var headerStyle: TabBarView.Style? { didSet { refreshHeaders() } }
    private var headers: [Int: PaneHeaderView] = [:]
    /// A pane being dragged by its header: its id, the tree it would make
    /// if dropped now, and the cards on top.
    private var paneDrag: (id: Int, tentative: PaneTree, overlay: PaneDragOverlay)?
    var headerViews: [Int: PaneHeaderView] { headers }

    private let outline = FocusOutlineView()
    private var dragging: (path: [Bool], axis: PaneTree.Axis, area: CGRect)?
    /// The divider under the pointer (or being dragged), drawn thicker.
    private var hovered: [Bool]? { didSet { if hovered != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        outline.autoresizingMask = [.width, .height]
        addSubview(outline)
        NotificationCenter.default.addObserver(forName: PaneLooks.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsLayout = true }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneLayoutView is created in code") }

    /// Puts exactly the tree's panes in the view, outline on top.
    func syncSubviews() {
        if let zoomed, !tree.leaves.contains(zoomed) { self.zoomed = nil }
        let shown = zoomed.map { [$0] } ?? tree.leaves
        let wanted = Set(shown.compactMap { panes[$0] }.map(ObjectIdentifier.init))
        for view in subviews where view !== outline && !(view is PaneHeaderView) && !wanted.contains(ObjectIdentifier(view)) {
            view.removeFromSuperview()
        }
        for id in shown {
            guard let view = panes[id], view.superview !== self else { continue }
            addSubview(view, positioned: .below, relativeTo: outline)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let frames = zoomed.map { [$0: bounds] } ?? tree.frames(in: bounds, gap: Self.gap)
        needsDisplay = true
        let withHeaders = showsHeaders
        placeHeaders(withHeaders ? Array(frames.keys) : [])
        for (id, frame) in frames {
            guard withHeaders, let header = headers[id] else { panes[id]?.frame = frame; continue }
            let height = min(PaneHeaderView.height, frame.height)
            header.frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
            panes[id]?.frame = CGRect(x: frame.minX, y: frame.minY + height, width: frame.width, height: frame.height - height)
        }
        outline.frame = bounds
        outline.dimmed = zoomed == nil && tree.leaves.count > 1 ? frames.filter { $0.key != focused }.map(\.value) : []
        updateTrackingAreas()
    }

    /// tabs.paneHeaders: "split" (with 2+ panes, or one maximized), "always", "never".
    var showsHeaders: Bool {
        switch PaneLooks.paneHeaders {
        case "always": true
        case "never": false
        default: tree.leaves.count > 1 || zoomed != nil
        }
    }

    /// One header per shown pane, under the dimming like its pane.
    private func placeHeaders(_ ids: [Int]) {
        for (id, header) in headers where !ids.contains(id) {
            header.removeFromSuperview()
            headers[id] = nil
        }
        for id in ids where headers[id] == nil {
            let header = PaneHeaderView(frame: .zero)
            header.onAction = { [weak self] action in self?.onHeaderAction?(id, action) }
            addSubview(header, positioned: .below, relativeTo: outline)
            headers[id] = header
        }
        refreshHeaders()
    }

    /// The headers say again what their panes show (a title, a cwd changed).
    func refreshHeaders() {
        for (id, header) in headers {
            if let info = describe?(id) { header.info = info }
            if let headerStyle { header.style = headerStyle }
            header.focused = id == focused
            header.zoomed = id == zoomed
        }
    }

    /// Only the divider lines: filling the whole view would hide a
    /// background image behind the terminals.
    override func draw(_ dirtyRect: NSRect) {
        for divider in dividers(of: tree, in: bounds, path: []) {
            if divider.path == hovered || divider.path == dragging?.path {
                NSColor.labelColor.withAlphaComponent(0.35).setFill()
                let thick = divider.axis == .horizontal ? divider.line.insetBy(dx: -1.5, dy: 0) : divider.line.insetBy(dx: 0, dy: -1.5)
                NSBezierPath(roundedRect: thick, xRadius: 2, yRadius: 2).fill()
            } else {
                NSColor.separatorColor.setFill()
                divider.line.fill()
            }
        }
    }

    /// Whether pane `id` has room to be split along `axis`.
    /// Half the tab is wide enough for a pane.
    var canDock: Bool { (bounds.width - Self.gap) / 2 >= Self.minPaneSize.width }

    func canSplit(_ id: Int, axis: PaneTree.Axis) -> Bool {
        guard let frame = tree.frames(in: bounds, gap: Self.gap)[id] else { return false }
        switch axis {
        case .horizontal: return (frame.width - Self.gap) / 2 >= Self.minPaneSize.width
        case .vertical: return (frame.height - Self.gap) / 2 >= Self.minPaneSize.height
        }
    }

    // MARK: Dragging a pane by its header

    /// A header's drag: cards of the panes glide to where they would be,
    /// and on release the pane moves beside the one under the pointer, on
    /// its nearest side. Released over itself or outside, nothing changes.
    func dragPane(_ id: Int, _ phase: PaneHeaderView.DragPhase, at windowPoint: NSPoint) {
        let point = convert(windowPoint, from: nil)
        switch phase {
        case .began:
            guard tree.leaves.count > 1, zoomed == nil, paneDrag == nil else { return }
            let frames = tree.frames(in: bounds, gap: Self.gap)
            let cards = tree.leaves.map { PaneDragOverlay.Card(id: $0, title: describe?($0)?.title ?? "") }
            let overlay = PaneDragOverlay(frame: bounds, cards: cards, frames: frames, dragged: id, style: headerStyle ?? TabBarView().style)
            overlay.autoresizingMask = [.width, .height]
            addSubview(overlay)
            paneDrag = (id, tree, overlay)
            overlay.show(frames, pointer: point)
        case .moved:
            guard let drag = paneDrag else { return }
            let tentative = Self.dropping(drag.id, at: point, in: tree, bounds: bounds)
            paneDrag?.tentative = tentative
            drag.overlay.show(tentative.frames(in: bounds, gap: Self.gap), pointer: point)
        case .ended:
            guard let drag = paneDrag else { return }
            paneDrag = nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                drag.overlay.animator().alphaValue = 0
            }, completionHandler: { drag.overlay.removeFromSuperview() })
            let dropped = Self.dropping(drag.id, at: point, in: tree, bounds: bounds)
            guard dropped != tree else { return }
            tree = dropped
            onTreeChange?(dropped)
            syncSubviews()
        }
    }

    /// The tree if `id` were dropped at `point`: beside the pane under it,
    /// on its nearest side; over itself or outside, the tree as it is.
    static func dropping(_ id: Int, at point: CGPoint, in tree: PaneTree, bounds: CGRect) -> PaneTree {
        let frames = tree.frames(in: bounds, gap: gap)
        guard let (target, frame) = frames.first(where: { $0.key != id && $0.value.contains(point) }) else { return tree }
        return tree.moving(id, beside: target, edge: PaneTree.dropEdge(at: point, in: frame))
    }

    // MARK: Dragging dividers

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        for divider in dividers(of: tree, in: bounds, path: []) {
            addTrackingArea(NSTrackingArea(rect: grabArea(divider), options: [.mouseEnteredAndExited, .activeInKeyWindow],
                                           owner: self, userInfo: ["path": divider.path]))
        }
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = event.trackingArea?.userInfo?["path"] as? [Bool]
    }

    override func mouseExited(with event: NSEvent) {
        if dragging == nil { hovered = nil }
    }

    private func grabArea(_ divider: Divider) -> CGRect {
        divider.line.insetBy(dx: -Self.grabSlack, dy: -Self.grabSlack)
    }

    override func resetCursorRects() {
        for divider in dividers(of: tree, in: bounds, path: []) {
            addCursorRect(grabArea(divider),
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
        hovered = divider(at: convert(event.locationInWindow, from: nil))?.path
    }

    private struct Divider {
        let path: [Bool]
        let axis: PaneTree.Axis
        /// The split node's whole area.
        let area: CGRect
        let line: CGRect
    }

    private func divider(at point: CGPoint) -> Divider? {
        dividers(of: tree, in: bounds, path: []).first { grabArea($0).contains(point) }
    }

    private func dividers(of node: PaneTree, in rect: CGRect, path: [Bool]) -> [Divider] {
        guard zoomed == nil, case .split(let axis, let a, let b, let ratio) = node else { return [] }
        let (first, second) = PaneTree.divide(rect, axis: axis, ratio: ratio, gap: Self.gap)
        let line = axis == .horizontal
            ? CGRect(x: first.maxX, y: rect.minY, width: Self.gap, height: rect.height)
            : CGRect(x: rect.minX, y: first.maxY, width: rect.width, height: Self.gap)
        return [Divider(path: path, axis: axis, area: rect, line: line)]
            + dividers(of: a, in: first, path: path + [false])
            + dividers(of: b, in: second, path: path + [true])
    }
}

/// How dark the panes without focus are (tabs.unfocusedDim, plan 15): the
/// app sets it from the settings, and every window redraws.
@MainActor
public enum PaneLooks {
    public static let didChange = Notification.Name("PaneLooks.didChange")
    /// 0.16 barely showed over dark themes (2026-10-19); 0.26 is the default.
    public static var unfocusedDim: CGFloat = 0.26 {
        didSet { if unfocusedDim != oldValue { NotificationCenter.default.post(name: didChange, object: nil) } }
    }
    /// tabs.paneHeaders: "split" (default), "always" or "never".
    public static var paneHeaders = "split" {
        didSet { if paneHeaders != oldValue { NotificationCenter.default.post(name: didChange, object: nil) } }
    }
}

/// A light shade over the panes without focus, so the focused one stands
/// out without a line. Draws over the panes and lets every click through.
private final class FocusOutlineView: NSView {
    var dimmed: [CGRect] = [] { didSet { if dimmed != oldValue { needsDisplay = true } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        NotificationCenter.default.addObserver(forName: PaneLooks.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FocusOutlineView is created in code") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(PaneLooks.unfocusedDim).setFill()
        dimmed.forEach { $0.fill() }
    }
}
