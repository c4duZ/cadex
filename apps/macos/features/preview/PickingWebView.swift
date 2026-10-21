import AppKit
import WebKit

/// The preview's web view. While picking (docs/adr/0018-element-picker.md)
/// the mouse stays with the app: WebKit gets no move, click or drag, so the
/// page sees no hover (not even CSS :hover) and no click. Scrolling still
/// goes through.
///
/// WebKit hears mouse moves through tracking areas owned by its own
/// WKMouseTrackingObserver, not through mouseMoved(with:) of the view: the
/// first version saw no hover and the page kept its :hover (owner,
/// 2026-10-21). So while picking its areas are put aside and one of ours
/// takes their place; they come back when picking ends.
@MainActor
final class PickingWebView: WKWebView {
    var isPicking = false {
        didSet {
            guard isPicking != oldValue else { return }
            isPicking ? takeMouse() : giveMouseBack()
        }
    }
    private var pickArea: NSTrackingArea?
    /// WebKit's tracking areas while picking.
    private(set) var parkedAreas: [NSTrackingArea] = []
    /// A point in the view, top-left origin (the view is flipped).
    var onPickMove: ((CGPoint) -> Void)?
    var onPickClick: ((CGPoint, NSEvent.ModifierFlags) -> Void)?
    var onPickExit: (() -> Void)?
    /// ⇧ was let go: the marked elements go out.
    var onShiftUp: (() -> Void)?
    /// The view lost the keyboard: picking ends with the focus.
    var onResign: (() -> Void)?

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    private func takeMouse() {
        parkedAreas = trackingAreas
        leavePage()
        parkedAreas.forEach(removeTrackingArea)
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                                         .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        pickArea = area
        NSCursor.crosshair.set()
    }

    /// The page drops its :hover, as if the mouse had left it: WebKit's
    /// areas hear a mouse exit before they are put aside.
    private func leavePage() {
        guard let window, let event = NSEvent.enterExitEvent(
            with: .mouseExited, location: window.mouseLocationOutsideOfEventStream, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil) else { return }
        let exit = #selector(NSResponder.mouseExited(with:))
        for area in parkedAreas where area.options.contains(.mouseEnteredAndExited) {
            guard let owner = area.owner as? NSObject, owner !== self, owner.responds(to: exit) else { continue }
            owner.perform(exit, with: event)
        }
    }

    private func giveMouseBack() {
        if let pickArea { removeTrackingArea(pickArea) }
        pickArea = nil
        parkedAreas.forEach(addTrackingArea)
        parkedAreas = []
        NSCursor.arrow.set()
    }

    /// WebKit makes its areas again when the view changes size: while
    /// picking, the new ones are put aside in place of the old.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard isPicking else { return }
        let added = trackingAreas.filter { $0 !== pickArea }
        guard !added.isEmpty else { return }
        added.forEach(removeTrackingArea)
        parkedAreas = added
    }

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

    override func flagsChanged(with event: NSEvent) {
        guard isPicking else { return super.flagsChanged(with: event) }
        if !event.modifierFlags.contains(.shift) { onShiftUp?() }
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
