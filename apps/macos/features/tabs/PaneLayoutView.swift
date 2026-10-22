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
    /// Space between panes: each pane is its own rounded card on the
    /// window's frame color, so the division reads clearly (the owner,
    /// 2026-10-22; a 1 pt line inside one panel looked crude).
    static let gap: CGFloat = 6
    /// The cards' corners, the same as the panels' (PanelView, 8 pt).
    static let cardRadius: CGFloat = 8
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
    /// Each shown pane's card: its header and its view, clipped round.
    private var cards: [Int: PaneCard] = [:]
    /// A pane being dragged by its header (PaneDragState).
    private var paneDrag: PaneDragState?
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

    /// Puts exactly the tree's panes in the view, each in its card, the
    /// outline on top.
    func syncSubviews() {
        if let zoomed, !tree.leaves.contains(zoomed) { self.zoomed = nil }
        let shown = zoomed.map { [$0] } ?? tree.leaves
        for (id, card) in cards where !shown.contains(id) {
            card.subviews.forEach { $0.removeFromSuperview() }
            card.removeFromSuperview()
            cards[id] = nil
        }
        for id in shown {
            let card = cards[id] ?? PaneCard()
            if cards[id] == nil {
                cards[id] = card
                addSubview(card, positioned: .below, relativeTo: outline)
            }
            // What left the tab (or the card) goes; the pane comes in.
            for view in card.subviews where !(view is PaneHeaderView) && view !== panes[id] { view.removeFromSuperview() }
            if let view = panes[id], view.superview !== card { card.addSubview(view, positioned: .below, relativeTo: nil) }
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let frames = zoomed.map { [$0: bounds] } ?? tree.frames(in: bounds, gap: Self.gap)
        needsDisplay = true
        let withHeaders = showsHeaders
        placeHeaders(withHeaders ? Array(frames.keys) : [])
        let asCards = frames.count > 1
        for (id, frame) in frames {
            guard let card = cards[id] else { continue }
            card.frame = frame
            card.layer?.cornerRadius = asCards ? Self.cardRadius : 0
            guard withHeaders, let header = headers[id] else { panes[id]?.frame = card.bounds; continue }
            let height = min(PaneHeaderView.height, frame.height)
            header.frame = CGRect(x: 0, y: 0, width: frame.width, height: height)
            panes[id]?.frame = CGRect(x: 0, y: height, width: frame.width, height: frame.height - height)
        }
        outline.frame = bounds
        outline.dimmed = asCards ? frames.filter { $0.key != focused }.map(\.value) : []
        outline.focusedCard = asCards ? focused.flatMap { frames[$0] } : nil
        outline.accent = headerStyle?.accent ?? .controlAccentColor
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
        for id in ids {
            guard let card = cards[id] else { continue }
            if let header = headers[id] {
                // Back from a hidden card (a pane was maximized): in its card again.
                if header.superview !== card { card.addSubview(header) }
                continue
            }
            let header = PaneHeaderView(frame: .zero)
            header.onAction = { [weak self] action in self?.onHeaderAction?(id, action) }
            card.addSubview(header)
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

    /// With 2+ panes, the window's frame color shows between the cards
    /// (PaneLooks.frameColor); a dragged divider shows a short handle.
    /// One pane draws nothing: a filled view would hide a background image.
    override func draw(_ dirtyRect: NSRect) {
        guard tree.leaves.count > 1, zoomed == nil else { return }
        PaneLooks.frameColor.setFill()
        bounds.fill()
        for divider in dividers(of: tree, in: bounds, path: []) where divider.path == hovered || divider.path == dragging?.path {
            NSColor.labelColor.withAlphaComponent(0.35).setFill()
            let line = divider.line
            let handle = divider.axis == .horizontal
                ? CGRect(x: line.midX - 1.5, y: line.midY - 20, width: 3, height: 40)
                : CGRect(x: line.midX - 20, y: line.midY - 1.5, width: 40, height: 3)
            NSBezierPath(roundedRect: handle, xRadius: 1.5, yRadius: 1.5).fill()
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

    /// A pane in flight: the tree and frames when it began (what the
    /// pointer is measured on), the gray windows, the label, the zone now
    /// and where the pointer was when it last changed.
    struct PaneDragState {
        let id: Int
        let original: PaneTree
        let frames: [Int: CGRect]
        let board: PaneDragBoard
        let chip: PaneDragChip
        var drop: PaneDrop?
        var droppedAt: CGPoint
        var escape: Any?
    }

    /// A header's drag: the panes turn into gray windows that glide live to
    /// where they would be; the zone under the pointer is read on the
    /// layout of the start (PaneDrop.swift). Esc or a release outside puts
    /// everything back; a release elsewhere moves the real panes once.
    func dragPane(_ id: Int, _ phase: PaneHeaderView.DragPhase, at windowPoint: NSPoint) {
        let point = convert(windowPoint, from: nil)
        switch phase {
        case .began: beginPaneDrag(id, at: point)
        case .moved: movePaneDrag(to: point)
        case .ended: endPaneDrag(at: point, cancelled: false)
        }
    }

    private func beginPaneDrag(_ id: Int, at point: CGPoint) {
        guard tree.leaves.count > 1, zoomed == nil, paneDrag == nil else { return }
        let style = headerStyle ?? TabBarView().style
        let frames = tree.frames(in: bounds, gap: Self.gap)
        var infos: [Int: PaneHeaderView.Info] = [:]
        for leaf in tree.leaves { infos[leaf] = describe?(leaf) }
        let board = PaneDragBoard(frame: bounds, frames: frames, infos: infos, dragged: id, style: style)
        board.autoresizingMask = [.width, .height]
        addSubview(board)
        let chip = PaneDragChip(info: infos[id] ?? PaneHeaderView.Info(title: "", icon: .terminalWindow), style: style)
        addSubview(chip)
        chip.follow(point, in: bounds)
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.paneDrag != nil else { return event }
            self.endPaneDrag(at: point, cancelled: true)
            return nil
        }
        paneDrag = PaneDragState(id: id, original: tree, frames: frames, board: board, chip: chip, drop: nil, droppedAt: point, escape: escape)
    }

    private func movePaneDrag(to point: CGPoint) {
        guard var drag = paneDrag else { return }
        drag.chip.follow(point, in: bounds)
        let next = PaneDrop.at(point, dragged: drag.id, frames: drag.frames, header: PaneHeaderView.height)
        // A new zone only after the pointer goes a few points on, so the
        // windows do not flick at a boundary.
        let moved = hypot(point.x - drag.droppedAt.x, point.y - drag.droppedAt.y)
        guard next != drag.drop, drag.drop == nil || moved >= PaneDrop.hysteresis else { return paneDrag = drag }
        drag.drop = next
        drag.droppedAt = point
        paneDrag = drag
        let result = next?.applied(to: drag.original, dragged: drag.id) ?? drag.original
        drag.board.show(result.frames(in: bounds, gap: Self.gap))
    }

    private func endPaneDrag(at point: CGPoint, cancelled: Bool) {
        guard let drag = paneDrag else { return }
        paneDrag = nil
        if let escape = drag.escape { NSEvent.removeMonitor(escape) }
        drag.chip.removeFromSuperview()
        drag.board.dismiss()
        guard !cancelled, bounds.contains(point), let drop = drag.drop else { return }
        let result = drop.applied(to: drag.original, dragged: drag.id)
        guard result != tree else { return }
        tree = result
        onTreeChange?(result)
        syncSubviews()
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
    /// The window's frame color, between the panes' cards; the app sets it
    /// from the theme.
    public static var frameColor: NSColor = .windowBackgroundColor {
        didSet { if frameColor != oldValue { NotificationCenter.default.post(name: didChange, object: nil) } }
    }
    /// A card's own color (the terminal's background): the headers' ground.
    public static var cardColor: NSColor = .textBackgroundColor {
        didSet { if cardColor != oldValue { NotificationCenter.default.post(name: didChange, object: nil) } }
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
    /// The focused card: a thin accent outline along its whole rounded
    /// edge, in place of a line across its top that the corners cut (the
    /// owner, 2026-10-22).
    var focusedCard: CGRect? { didSet { if focusedCard != oldValue { needsDisplay = true } } }
    var accent: NSColor = .controlAccentColor { didSet { if accent != oldValue { needsDisplay = true } } }

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
        let radius = PaneLayoutView.cardRadius
        NSColor.black.withAlphaComponent(PaneLooks.unfocusedDim).setFill()
        dimmed.forEach { NSBezierPath(roundedRect: $0, xRadius: radius, yRadius: radius).fill() }
        guard let focusedCard else { return }
        accent.withAlphaComponent(0.75).setStroke()
        let edge = NSBezierPath(roundedRect: focusedCard.insetBy(dx: 0.5, dy: 0.5), xRadius: radius - 0.5, yRadius: radius - 0.5)
        edge.lineWidth = 1
        edge.stroke()
    }
}

/// A pane's card: its header and its view, clipped to round corners on all
/// four sides when the tab is split (the owner, 2026-10-22). One container
/// clips both, where masking each one's corners came out upside down.
@MainActor
final class PaneCard: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneCard is created in code") }

    override var isFlipped: Bool { true }
}
