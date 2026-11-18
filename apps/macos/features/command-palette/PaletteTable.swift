import AppKit

/// The palette's list: the row under the pointer is chosen as the mouse moves, as Spotlight and
/// Raycast do (the owner, 2026-11-18: the list did not answer the mouse, the palette felt stiff).
/// Only a real move counts: a list scrolled by the keys under a still pointer keeps its row. The
/// panel hands every move over (`pointerMoved`): a tracking area on the list never received them.
final class PaletteTable: NSTableView {
    var onHover: ((Int) -> Void)?
    private var lastPointer: NSPoint?

    func pointerMoved(_ event: NSEvent) {
        let pointer = NSEvent.mouseLocation
        guard pointer != lastPointer else { return }
        lastPointer = pointer
        let point = convert(event.locationInWindow, from: nil)
        guard visibleRect.contains(point) else { return }
        let row = self.row(at: point)
        if row >= 0 { onHover?(row) }
    }
}
