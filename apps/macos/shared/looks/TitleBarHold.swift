import AppKit

/// Nothing clickable in the title bar moves the window (the owner,
/// 2026-10-22): there macOS decides to move the window when the button goes
/// down, before the app sees the click, so mouseDownCanMoveWindow and
/// locking at the click came too late (dragging a tab took the whole
/// window). The window is locked while the pointer is over a tab or a
/// button of the bar, and free again when it leaves; the bar's empty parts
/// still move it.
@MainActor
public enum TitleBarHold {
    /// The pointer came onto something clickable in the bar.
    public static func entered(_ view: NSView) {
        view.window?.isMovable = false
    }

    /// It left: free again, unless it is still held (a drag that went
    /// outside), which `released` settles.
    public static func exited(_ view: NSView, holding: Bool) {
        if !holding { view.window?.isMovable = true }
    }

    /// The button came up: free again if the pointer is no longer on it.
    public static func released(_ view: NSView, _ event: NSEvent) {
        if !view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { view.window?.isMovable = true }
    }
}
