import AppKit
import Terminal
import UILooks

/// Lays a tab's panes out by its PaneTree, each in its box with its header (plan 28 phase B; the
/// Terminals and Pane mockups, components.pane): 8 pt around and between the boxes, the focused
/// one lit with its halo, the others a shade dimmer; the gap between two boxes is where a drag
/// resizes them (docs/spec/tabs.md, "Divisões").
final class PaneLayoutView: NSView {
    /// Space between panes, where a drag resizes them.
    static var gap: CGFloat { UILooks.pt(DesignTokens.Pane.gap) }
    /// The panes' area: the center less its padding.
    var paneArea: CGRect {
        let pad = UILooks.pt(DesignTokens.Pane.outerPadding)
        return bounds.insetBy(dx: pad, dy: pad)
    }
    /// No pane gets smaller than this by dragging or splitting.
    static let minPaneSize = CGSize(width: 120, height: 60)
    /// How far from the line a drag still grabs the divider.
    private static let grabSlack: CGFloat = 8

    var tree: PaneTree = .leaf(0) { didSet { needsLayout = true } }
    var panes: [Int: NSView] = [:]
    var focused: Int? { didSet { needsLayout = true } }
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
    private var handles: [DividerHandle] = []
    /// A pane being dragged by its header (PaneDragState).
    private var paneDrag: PaneDragState?
    var headerViews: [Int: PaneHeaderView] { headers }

    private lazy var chrome = PaneChrome(host: layer)
    private var dragging: (path: [Bool], axis: PaneTree.Axis, area: CGRect)?
    /// The divider under the pointer (or being dragged), drawn thicker.
    private var hovered: [Bool]? { didSet { if hovered != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneLayoutView is created in code") }

    /// Puts exactly the tree's panes in the view, under the divider handles.
    func syncSubviews() {
        if let zoomed, !tree.leaves.contains(zoomed) { self.zoomed = nil }
        let shown = zoomed.map { [$0] } ?? tree.leaves
        let wanted = Set(shown.compactMap { panes[$0] }.map(ObjectIdentifier.init))
        for view in subviews where !(view is DividerHandle) && !(view is PaneHeaderView) && !wanted.contains(ObjectIdentifier(view))
            && !((view as? TerminalScrollbar).map { bar in shown.contains { (panes[$0] as? TerminalView)?.scrollbar === bar } } ?? false)
            && !shown.contains(where: { (panes[$0] as? TerminalView)?.footCard === view })
            && !shown.contains(where: { (panes[$0] as? TerminalView)?.footBar === view }) {
            view.removeFromSuperview()
        }
        for id in shown {
            guard let view = panes[id], view.superview !== self else { continue }
            addSubview(view, positioned: .below, relativeTo: handles.first)
        }
        needsLayout = true
    }

    /// A lone pane fills the view flat, with no box or header (the drawer's terminals).
    var plain = false { didSet { needsLayout = true } }

    override func layout() {
        super.layout()
        let frames = zoomed.map { [$0: paneArea] } ?? tree.frames(in: paneArea, gap: Self.gap)
        needsDisplay = true
        // A page alone in its tab: the whole center, flat (the Project mockup), no box drawn. The
        // headers say first what each pane is (the first layout had none yet and drew the box).
        placeHeaders(Array(frames.keys))
        if frames.count == 1, let only = frames.keys.first, headers[only]?.info.page == true || plain, let view = panes[only] {
            chrome.place([:], focused: nil)
            headers[only]?.isHidden = true
            // A plain terminal (the drawer's) keeps the mockup's room around its text.
            let pad = DesignTokens.Pane.bodyPadding, own = TerminalView.innerPadding
            view.frame = view is TerminalView && plain
                ? bounds.insetBy(dx: max(UILooks.pt(pad.left) - own, 0), dy: max(UILooks.pt(pad.top) - own, 0)) : bounds
            view.layer?.cornerRadius = 0
            view.alphaValue = 1
            placeHandles()
            return
        }
        chrome.place(frames, focused: focused)
        placeHeaders(Array(frames.keys))
        typealias P = DesignTokens.Pane
        for (id, frame) in frames {
            // Inside the box's line: the header on top, the pane under it; a terminal with the
            // mockup's room around its text (bodyPadding).
            let inner = frame.insetBy(dx: DesignTokens.Stroke.hairline, dy: DesignTokens.Stroke.hairline)
            let hidden = headers[id]?.info.hidden == true
            headers[id]?.isHidden = hidden
            let height = hidden ? 0 : min(headers[id]?.preferredHeight ?? PaneHeaderView.height, inner.height)
            headers[id]?.frame = CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: height)
            var body = CGRect(x: inner.minX, y: inner.minY + height, width: inner.width, height: inner.height - height)
            if let terminal = panes[id] as? TerminalView {
                // The mockup's scrollbar along the box's right edge, under the header.
                let bar = UILooks.pt(P.Scrollbar.width)
                // It stops where the box's corner rounds, as drawn.
                terminal.scrollbar.frame = CGRect(x: body.maxX - bar, y: body.minY, width: bar, height: max(body.height - UILooks.pt(P.radius), 0))
                if terminal.scrollbar.superview !== self { addSubview(terminal.scrollbar, positioned: .below, relativeTo: handles.first) }
                terminal.scrollbar.alphaValue = frames.count > 1 && id != focused ? P.Idle.opacity : 1
                placeFootCard(terminal, box: frame)
                // A lane's foot bar across the box's bottom; the terminal ends above it.
                if let bar = terminal.footBar {
                    if bar.superview !== self { addSubview(bar, positioned: .below, relativeTo: handles.first) }
                    let barHeight = bar.fittingSize.height
                    bar.frame = CGRect(x: inner.minX, y: inner.maxY - barHeight, width: inner.width, height: barHeight)
                    body.size.height = max(body.height - barHeight, 0)
                    bar.alphaValue = frames.count > 1 && id != focused ? P.Idle.opacity : 1
                }
            }
            if headers[id]?.info.padded == true {
                // The mockup's room around the text, less what the terminal keeps itself.
                let pad = P.bodyPadding, own = TerminalView.innerPadding
                let left = max(UILooks.pt(pad.left) - own, 0), right = max(UILooks.pt(pad.right) - own, 0)
                let top = max(UILooks.pt(pad.top) - own, 0), bottom = max(UILooks.pt(pad.bottom) - own, 0)
                body = CGRect(x: body.minX + left, y: body.minY + top,
                              width: max(body.width - left - right, 0), height: max(body.height - top - bottom, 0))
            }
            panes[id]?.frame = body
            // A document with no padding (a page, an image) takes the box's rounded corners: its
            // square ones showed past the curve. The top ones too when it has no header.
            if headers[id]?.info.padded != true, let view = panes[id] {
                view.wantsLayer = true
                view.layer?.cornerRadius = max(UILooks.pt(P.radius) - DesignTokens.Stroke.hairline, 0)
                view.layer?.maskedCorners = hidden ? [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                    : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                view.layer?.masksToBounds = true
            }
            // The panes without focus a shade dimmer (components.pane.idle.opacity).
            let alpha = frames.count > 1 && id != focused ? P.Idle.opacity : 1
            headers[id]?.alphaValue = alpha
            panes[id]?.alphaValue = alpha
        }
        placeHandles()
    }

    /// The terminal's foot card (an agent's permission) where the Pane mockup puts it: 16 pt from
    /// the box's left, 24 from its right, its bottom 92 above the box's (over the agent's prompt).
    private func placeFootCard(_ terminal: TerminalView, box: CGRect) {
        guard let card = terminal.footCard else { return }
        typealias I = DesignTokens.Pane.Permission.Inset
        // Over its terminal: below the first divider handle put it under every view when a tab has
        // one pane (no handles), behind the terminal, so the card was never seen (plan 33, 2026-11-18).
        if card.superview !== self { addSubview(card, positioned: .above, relativeTo: terminal) }
        let height = card.fittingSize.height
        let left = box.minX + UILooks.pt(I.left), right = box.maxX - UILooks.pt(I.right)
        // Over the agent's input box, whose top rule is the row above the cursor (Claude's, plan 33);
        // never lower than the mockup's place.
        let input = terminal.frame.minY + terminal.rowTop(terminal.cursorRow - 1) - UILooks.pt(DesignTokens.Pane.Permission.gap)
        let bottom = min(box.maxY - UILooks.pt(I.bottom), terminal.cursorRow > 1 ? input : .infinity)
        card.frame = CGRect(x: left, y: bottom - height, width: max(right - left, 0), height: height)
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
            addSubview(header, positioned: .below, relativeTo: handles.first)
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

    /// The gap between boxes shows nothing at rest (the mockups); under the pointer or in a drag,
    /// a short bar in its middle says it resizes.
    override func draw(_ dirtyRect: NSRect) {
        for divider in dividers(of: tree, in: paneArea, path: []) where divider.path == hovered || divider.path == dragging?.path {
            DesignTokens.Color.lineFocus.setFill()
            let bar = DesignTokens.Stroke.glyph
            let line = divider.axis == .horizontal
                ? CGRect(x: divider.line.midX - bar / 2, y: divider.line.minY, width: bar, height: divider.line.height)
                : CGRect(x: divider.line.minX, y: divider.line.midY - bar / 2, width: divider.line.width, height: bar)
            NSBezierPath(roundedRect: line, xRadius: bar / 2, yRadius: bar / 2).fill()
        }
    }

    /// Whether pane `id` has room to be split along `axis`.
    /// Half the tab is wide enough for a pane.
    var canDock: Bool { (paneArea.width - Self.gap) / 2 >= Self.minPaneSize.width }

    func canSplit(_ id: Int, axis: PaneTree.Axis) -> Bool {
        guard let frame = tree.frames(in: paneArea, gap: Self.gap)[id] else { return false }
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
        let frames = tree.frames(in: paneArea, gap: Self.gap)
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

    /// One handle per divider, on top of the panes and their headers: the
    /// resize cursor holds along the whole divider. With cursor rects on
    /// this view, the terminal and the headers under the band set their
    /// own cursor and the resize one came and went (the owner, 2026-10-22).
    private func placeHandles() {
        let all = zoomed == nil ? dividers(of: tree, in: paneArea, path: []) : []
        while handles.count > all.count { handles.removeLast().removeFromSuperview() }
        while handles.count < all.count {
            let handle = DividerHandle()
            handle.layout = self
            addSubview(handle, positioned: .above, relativeTo: nil)
            handles.append(handle)
        }
        for (handle, divider) in zip(handles, all) {
            handle.path = divider.path
            handle.axis = divider.axis
            if handle.frame != grabArea(divider) {
                handle.frame = grabArea(divider)
                window?.invalidateCursorRects(for: handle)
            }
        }
    }

    func handleHovered(_ path: [Bool]?) {
        if dragging == nil { hovered = path }
    }

    private func grabArea(_ divider: Divider) -> CGRect {
        divider.line.insetBy(dx: -Self.grabSlack, dy: -Self.grabSlack)
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
        placeHandles()
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
        dividers(of: tree, in: paneArea, path: []).first { grabArea($0).contains(point) }
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

/// The grab band of a divider: the resize cursor over all of it, and its
/// clicks and drags handed to the layout (PaneLayoutView).
@MainActor
final class DividerHandle: NSView {
    weak var layout: PaneLayoutView?
    var path: [Bool] = []
    var axis: PaneTree.Axis = .horizontal { didSet { if axis != oldValue { window?.invalidateCursorRects(for: self) } } }

    private var cursor: NSCursor { axis == .horizontal ? .resizeLeftRight : .resizeUpDown }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseEntered(with event: NSEvent) { cursor.set(); layout?.handleHovered(path) }
    override func mouseExited(with event: NSEvent) { layout?.handleHovered(nil) }
    override func mouseDown(with event: NSEvent) { layout?.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { cursor.set(); layout?.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { layout?.mouseUp(with: event) }
}
