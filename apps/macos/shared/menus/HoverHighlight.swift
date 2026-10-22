import AppKit
import ObjectiveC

/// A soft rounded fill under the pointer, for the status bar's clickable
/// items, as the title bar's buttons have (the owner, 2026-10-22: the
/// bottom ones gave no sign of being clickable). The view keeps its own
/// layout; give it a little inset so the fill surrounds the content.
@MainActor
public final class HoverHighlight: NSObject {
    private weak var view: NSView?
    private nonisolated(unsafe) static var key = 0

    /// Lights `view` while the pointer is over it; once per view.
    public static func attach(_ view: NSView) {
        guard objc_getAssociatedObject(view, &key) == nil else { return }
        let highlight = HoverHighlight()
        highlight.view = view
        objc_setAssociatedObject(view, &key, highlight, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        view.wantsLayer = true
        view.layer?.cornerRadius = 5
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                            owner: highlight))
    }

    // The tracking area's owner gets these by their Objective-C names (a
    // HoverCard that never opened, 2026-10-21).
    @objc(mouseEntered:) public func mouseEntered(_ event: NSEvent) {
        view?.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
    }

    @objc(mouseExited:) public func mouseExited(_ event: NSEvent) {
        view?.layer?.backgroundColor = nil
    }
}
