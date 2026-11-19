import AppKit

/// A press on a tile or a page icon (plan 36 phase E): a click, or once the pointer goes past
/// `slop` a drag. AppKit sends the drag and the release to the view the press began on, so the
/// tile keeps them and hands each to the rail; no event loop of its own (the perf hooks send the
/// down and the up one after the other, and a loop waiting for the up never saw it).
@MainActor
final class RailPress {
    static let slop: CGFloat = 4
    private var start: NSPoint?
    private(set) var dragging = false

    func down(_ event: NSEvent) {
        start = event.locationInWindow
        dragging = false
    }

    /// True once this press is a drag.
    func moved(_ event: NSEvent) -> Bool {
        guard let start else { return false }
        let point = event.locationInWindow
        if !dragging, hypot(point.x - start.x, point.y - start.y) > Self.slop { dragging = true }
        return dragging
    }

    /// Let go: whether it was a drag (then it is no click).
    func up() -> Bool {
        defer { start = nil; dragging = false }
        return dragging
    }
}

/// Dragging in the rail (docs/adr/0038-rail-and-side-column.md; plan 36 phase E): the dragged tile
/// or icon goes among the others live, they slide out of its way, and the order is kept on release.
/// A project dragged above the line is pinned, below it is not; one with no terminal cannot go
/// below (unpinned and empty, nothing would keep it). The pages move only among the pages.
extension RailView {
    enum DragKind { case project, page }

    /// What moves together: the tiles and the line between pinned and not, or the page icons.
    func movable(_ kind: DragKind) -> [NSView] {
        switch kind {
        case .project:
            return top.arrangedSubviews.filter { $0 is RailTile || $0 === groupLine }
        case .page:
            return pagesStack.arrangedSubviews.filter { view in pageButtons.contains { $0.1 === view } }
        }
    }

    func dragMoved(_ view: NSView, _ kind: DragKind, _ event: NSEvent) {
        if dragged !== view {
            dragged = view
            view.alphaValue = Self.liftedAlpha
        }
        let items = movable(kind)
        let stack = kind == .project ? top : pagesStack
        guard let base = items.first.flatMap({ stack.arrangedSubviews.firstIndex(of: $0) }) else { return }
        var others = items.filter { $0 !== view }
        // Its slot: past every other whose middle is above the pointer (window coordinates go up).
        let pointer = event.locationInWindow.y
        var slot = others.filter { $0.convert(NSPoint(x: 0, y: $0.bounds.midY), to: nil).y > pointer }.count
        if let tile = view as? RailTile, !tile.project.open, let line = others.firstIndex(where: { $0 === groupLine }) {
            slot = min(slot, line)
        }
        others.insert(view, at: slot)
        guard others != items else { return }
        for (offset, item) in others.enumerated() {
            stack.removeArrangedSubview(item)
            stack.insertArrangedSubview(item, at: base + offset)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.allowsImplicitAnimation = true
            layoutSubtreeIfNeeded()
        }
    }

    func dragEnded(_ view: NSView, _ kind: DragKind) {
        dragged = nil
        view.alphaValue = 1
        switch kind {
        case .project:
            guard let tile = view as? RailTile else { return }
            let items = movable(.project)
            let order = items.compactMap { ($0 as? RailTile)?.project.id }
            var pinned = tile.project.pinned
            if let line = items.firstIndex(where: { $0 === groupLine }), let at = items.firstIndex(of: tile) {
                pinned = at < line
            }
            tiles.sort { (order.firstIndex(of: $0.project.id) ?? 0) < (order.firstIndex(of: $1.project.id) ?? 0) }
            onMove?(tile.project.id, order, pinned)
        case .page:
            let items = movable(.page)
            pageButtons.sort { a, b in (items.firstIndex(of: a.1) ?? 0) < (items.firstIndex(of: b.1) ?? 0) }
            onMovePages?(pageButtons.map(\.0.id))
        }
    }

    static let liftedAlpha: CGFloat = 0.7
    static let slideDuration: TimeInterval = 0.15
}
