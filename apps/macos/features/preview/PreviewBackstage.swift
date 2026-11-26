import AppKit

/// A window that never goes on screen, lent to the agent's page while its
/// tab is not the one shown. The tabs keep only the shown tab in the view
/// hierarchy, so a hidden preview had no window and every browser_* call
/// came back "the preview tab is not on screen": the agent lost the browser
/// whenever the owner switched tabs, and its next goto pulled the owner back
/// (the owner, 2026-11-26). Clicks and keys reach a web view in a window that
/// was never shown (the agent's tests run that way since 2026-11-15).
@MainActor
enum PreviewBackstage {
    /// Used when the page was never laid out in a pane.
    static let fallbackSize = NSSize(width: 1280, height: 800)

    static let window: NSWindow = {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: fallbackSize), styleMask: [.titled], backing: .buffered, defer: false)
        // Kept for the app's life; never closed, never ordered in.
        window.isReleasedWhenClosed = false
        return window
    }()

    /// Puts `view` in the backstage window when it has none, at the size it
    /// last had in its pane. The returned closure gives it back (out of the
    /// window), unless the tab showed it again in the meantime.
    static func lend(_ view: NSView) -> @MainActor () -> Void {
        guard view.window == nil, let stage = window.contentView else { return {} }
        let size = view.frame.size.width > 0 && view.frame.size.height > 0 ? view.frame.size : fallbackSize
        window.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        stage.addSubview(view)
        view.layoutSubtreeIfNeeded()
        return { [weak view] in
            guard let view, view.superview === stage else { return }
            view.removeFromSuperview()
        }
    }
}
