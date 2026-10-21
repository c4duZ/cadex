import AppKit
import WebKit

/// The preview's web view. While picking (docs/adr/0018-element-picker.md)
/// the mouse stays with the app: WebKit gets no move, click or drag, so the
/// page sees no hover (not even CSS :hover) and no click. Scrolling still
/// goes through.
@MainActor
final class PickingWebView: WKWebView {
    var isPicking = false {
        didSet { (isPicking ? NSCursor.crosshair : NSCursor.arrow).set() }
    }
    /// A point in the view, top-left origin (the view is flipped).
    var onPickMove: ((CGPoint) -> Void)?
    var onPickClick: ((CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onPickExit: (() -> Void)?
    /// The view lost the keyboard: picking ends with the focus.
    var onResign: (() -> Void)?

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) {
        guard isPicking else { return super.mouseMoved(with: event) }
        NSCursor.crosshair.set()
        onPickMove?(point(event))
    }

    override func mouseDown(with event: NSEvent) {
        guard isPicking else { return super.mouseDown(with: event) }
        onPickClick?(point(event), event.modifierFlags)
    }

    override func mouseExited(with event: NSEvent) {
        guard isPicking else { return super.mouseExited(with: event) }
        onPickExit?()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard isPicking else { return super.cursorUpdate(with: event) }
        NSCursor.crosshair.set()
    }

    override func mouseUp(with event: NSEvent) { if !isPicking { super.mouseUp(with: event) } }
    override func mouseDragged(with event: NSEvent) { if !isPicking { super.mouseDragged(with: event) } }
    override func mouseEntered(with event: NSEvent) { if !isPicking { super.mouseEntered(with: event) } }
    override func rightMouseDown(with event: NSEvent) { if !isPicking { super.rightMouseDown(with: event) } }
    override func rightMouseUp(with event: NSEvent) { if !isPicking { super.rightMouseUp(with: event) } }
    override func otherMouseDown(with event: NSEvent) { if !isPicking { super.otherMouseDown(with: event) } }
    override func otherMouseUp(with event: NSEvent) { if !isPicking { super.otherMouseUp(with: event) } }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onResign?() }
        return resigned
    }
}
