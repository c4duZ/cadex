import AppKit

/// ⌘ over a URL or path underlines it; ⌘+click opens it. The core finds the
/// link (cadex_terminal_link_at); this file tracks the pointer and opens.
extension TerminalView {
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = mouse.trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        mouse.trackingArea = area
    }

    public override func mouseMoved(with event: NSEvent) {
        // Something on top owns the pointer (a split's divider handle): its
        // cursor stays. Setting the I-beam here at every move fought the
        // resize cursor along the divider (the owner, 2026-10-22).
        guard isUnderPointer(event) else { return }
        let location = convert(event.locationInWindow, from: nil)
        let onImage = !event.modifierFlags.contains(.command) && refreshImageHover(at: location)
        if !onImage { hideImageHover() }
        refreshHoveredLink(at: location, command: event.modifierFlags.contains(.command), onImage: onImage)
        reportHover(event)
    }

    public override func mouseExited(with event: NSEvent) {
        hideImageHover()
    }

    /// Whether this terminal is the view the pointer is on, not one above it.
    private func isUnderPointer(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView, let superview = content.superview ?? Optional(content) else { return true }
        guard let hit = superview.hitTest(superview.convert(event.locationInWindow, from: nil)) else { return true }
        return hit === self || hit.isDescendant(of: self)
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        refreshHoveredLink(at: location, command: event.modifierFlags.contains(.command), onImage: imageHover != nil)
    }

    /// Cell indices (row-major) of the hovered link, for the renderer.
    var hoveredLinkCells: ClosedRange<Int>? {
        guard let link = mouse.hoveredLink else { return nil }
        let cols = geometry.cols
        let first = link.start.row * cols + link.start.col
        let last = link.end.row * cols + link.end.col
        return first <= last ? first...last : nil
    }

    /// ⌘+click: opens the link under the pointer. Returns false when there
    /// is none, so the click selects as usual.
    func openLink(at location: CGPoint) -> Bool {
        guard bounds.contains(location), let link = linkUnder(location) else { return false }
        switch link.kind {
        case .url:
            guard let url = URL(string: link.target) else { return false }
            NSWorkspace.shared.open(url)
        case .path:
            // Until the viewers exist (plan 5), files show in Finder.
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: link.target)])
        }
        return true
    }

    /// `onImage`: the pointer is on a pasted image's tag, whose hand cursor stays.
    private func refreshHoveredLink(at location: CGPoint, command: Bool, onImage: Bool) {
        let link = command && bounds.contains(location) ? linkUnder(location) : nil
        if link != mouse.hoveredLink {
            mouse.hoveredLink = link
            needsDisplay = true
        }
        (link == nil && !onImage ? NSCursor.iBeam : NSCursor.pointingHand).set()
    }

    private func linkUnder(_ location: CGPoint) -> TerminalSession.Link? {
        let p = geometry.pointer(at: location)
        return session?.link(atCol: Int(p.col), row: Int(p.row))
    }
}
