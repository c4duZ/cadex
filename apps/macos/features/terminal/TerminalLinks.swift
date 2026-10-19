import AppKit

/// ⌘ over a URL or path underlines it; ⌘+click opens it. The core finds the
/// link (cadex_terminal_link_at); this file tracks the pointer and opens.
extension TerminalView {
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = mouse.trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        mouse.trackingArea = area
    }

    public override func mouseMoved(with event: NSEvent) {
        refreshHoveredLink(at: convert(event.locationInWindow, from: nil), command: event.modifierFlags.contains(.command))
    }

    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        refreshHoveredLink(at: location, command: event.modifierFlags.contains(.command))
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

    private func refreshHoveredLink(at location: CGPoint, command: Bool) {
        let link = command && bounds.contains(location) ? linkUnder(location) : nil
        if link != mouse.hoveredLink {
            mouse.hoveredLink = link
            needsDisplay = true
        }
        (link == nil ? NSCursor.iBeam : NSCursor.pointingHand).set()
    }

    private func linkUnder(_ location: CGPoint) -> TerminalSession.Link? {
        let p = geometry.pointer(at: location)
        return session?.link(atCol: Int(p.col), row: Int(p.row))
    }
}
