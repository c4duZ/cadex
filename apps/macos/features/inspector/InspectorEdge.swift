import AppKit

/// The column's right edge (it sits left of the center since ADR 0038), which drags its width (docs/spec/inspector.md: "arrastar a borda muda e
/// fica salva"). A strip a little wider than the line, so it can be caught; the resize cursor on it.
@MainActor
final class InspectorEdge: NSView {
    /// How wide the strip that catches the drag is, in points (a 1 pt line is too thin to aim at).
    static let grab: CGFloat = 5
    /// The width asked while dragging: the column's width at the start plus how far the pointer went
    /// right. `ended` on mouse up, to save it.
    var onDrag: ((_ width: CGFloat, _ ended: Bool) -> Void)?
    /// The panel's width when the drag starts.
    var currentWidth: (() -> CGFloat)?
    private var start: (x: CGFloat, width: CGFloat)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        start = (NSEvent.mouseLocation.x, currentWidth?() ?? 0)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        onDrag?(start.width + NSEvent.mouseLocation.x - start.x, false)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        onDrag?(start.width + NSEvent.mouseLocation.x - start.x, true)
        self.start = nil
    }
}
