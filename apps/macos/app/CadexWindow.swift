import AppKit

/// The app's window, with its own full screen beside the system's (docs/spec/themes.md, Tela cheia).
///
/// Escape: in the system's full screen AppKit leaves it on an Escape that nobody took
/// (NSWindow.cancelOperation, like the green button), and in Cadex the Esc that reaches the
/// window is never the owner asking that: the preview's page passes back the keys it does not use,
/// so the owner's Esc there and the agent's (browser_press Escape, 8 times on 2026-11-23) took the
/// window out of full screen; the sidebar sends its own up the chain too (the owner, 2026-11-23:
/// "tirava o cadex da tela cheia, como se clicasse no ícone verde").
///
/// Cadex's full screen: the system's puts the window on a Space of its own over black, so a
/// translucent window (appearance.windowOpacity) showed black through the glass instead of the
/// wallpaper (the owner, 2026-11-24). Cadex's covers the screen on the desktop's Space, over the
/// menu bar and the Dock, which come back at the edges; the wallpaper shows through.
/// appearance.fullScreen picks it ("auto": with a translucent window).
final class CadexWindow: NSWindow {
    static let ownFullScreenDidChange = Notification.Name("CadexWindow.ownFullScreenDidChange")

    /// The settings' choice: the green button, ⌃⌘F and window.toggle-full-screen go to Cadex's full screen.
    var usesOwnFullScreen = false
    /// The frame before Cadex's full screen, nil outside it.
    private var frameBefore: NSRect?
    private var screenWatch: NSObjectProtocol?

    var isInOwnFullScreen: Bool { frameBefore != nil }

    override func toggleFullScreen(_ sender: Any?) {
        if isInOwnFullScreen { return leaveOwnFullScreen() }
        guard usesOwnFullScreen, !styleMask.contains(.fullScreen) else { return super.toggleFullScreen(sender) }
        enterOwnFullScreen()
    }

    private func enterOwnFullScreen() {
        guard let screen = screen ?? NSScreen.main else { return }
        frameBefore = frame
        styleMask.remove(.resizable)
        isMovable = false
        Self.hideMenuBar(true)
        setFrame(screen.frame, display: true)
        // A resolution or arrangement change: the window follows its screen's new size.
        screenWatch = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isInOwnFullScreen, let screen = self.screen ?? NSScreen.main else { return }
                self.setFrame(screen.frame, display: true)
            }
        }
        NotificationCenter.default.post(name: Self.ownFullScreenDidChange, object: self)
    }

    private func leaveOwnFullScreen() {
        guard let before = frameBefore else { return }
        frameBefore = nil
        if let screenWatch { NotificationCenter.default.removeObserver(screenWatch) }
        screenWatch = nil
        styleMask.insert(.resizable)
        isMovable = true
        Self.hideMenuBar(false)
        setFrame(before, display: true)
        NotificationCenter.default.post(name: Self.ownFullScreenDidChange, object: self)
    }

    /// The menu bar and the Dock hide while the app is in front and come back at the screen's edge.
    /// Per app: another window of Cadex in front decides (`becomeKey`).
    private static func hideMenuBar(_ hide: Bool) {
        NSApp.presentationOptions = hide ? [.autoHideMenuBar, .autoHideDock] : []
    }

    /// The menu bar's area is the window's too: AppKit keeps a titled window below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        isInOwnFullScreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }

    override func becomeKey() {
        super.becomeKey()
        Self.hideMenuBar(isInOwnFullScreen)
    }

    override func close() {
        if isInOwnFullScreen { Self.hideMenuBar(false) }
        super.close()
    }

    override func cancelOperation(_ sender: Any?) {
        if styleMask.contains(.fullScreen) { return }
        super.cancelOperation(sender)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, styleMask.contains(.fullScreen) { return }
        super.keyDown(with: event)
    }
}

extension NSWindow {
    /// In the system's full screen or in Cadex's: the window's buttons and the toolbar stay away.
    var isAnyFullScreen: Bool { styleMask.contains(.fullScreen) || (self as? CadexWindow)?.isInOwnFullScreen == true }
}
