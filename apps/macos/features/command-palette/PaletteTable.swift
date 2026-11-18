import AppKit

/// The palette's list: the row under the pointer is chosen as the mouse moves, as Spotlight and
/// Raycast do (the owner, 2026-11-18: the list did not answer the mouse, the palette felt stiff).
/// Only a real move counts: a list scrolled by the keys under a still pointer keeps its row.
final class PaletteTable: NSTableView {
    var onHover: ((Int) -> Void)?
    private var lastPointer: NSPoint?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        guard pointer != lastPointer else { return }
        lastPointer = pointer
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 { onHover?(row) }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
}
