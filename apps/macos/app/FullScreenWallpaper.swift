import AppKit

/// The desktop behind a translucent window in the system's full screen.
///
/// The system's full screen puts the window on a Space of its own over black, so the glass
/// (appearance.windowOpacity) showed black instead of the desktop (the owner, 2026-11-24). Cadex's
/// own full screen stayed on the desktop's Space for that, but it was not a real full screen: the
/// app stayed on the desktop and the window's buttons were gone (the owner, 2026-11-27: in a Space
/// of its own, "mostrar o desktop atrás, sem alterar a visão que teríamos se fosse uma tela cheia
/// em um desktop vazio"). So, in the system's, a window with the wallpaper as the desktop draws it
/// lies right behind Cadex's, as its child: the glass's own blur (the frost, or the strong glass's
/// window server blur) acts on it as it does on the desktop, and the look is the same.
@MainActor
final class FullScreenWallpaper {
    /// The window is translucent (WorkspaceView sets it with the looks).
    var translucent = false { didSet { if translucent != oldValue { refresh() } } }
    private weak var parent: NSWindow?
    private var backdrop: NSWindow?
    private var watches: [NSObjectProtocol] = []

    func attach(to window: NSWindow?) {
        guard window !== parent else { return }
        watches.forEach(NotificationCenter.default.removeObserver)
        watches = []
        hide()
        parent = window
        guard let window else { return }
        let names = [NSWindow.didEnterFullScreenNotification, NSWindow.willExitFullScreenNotification, NSWindow.didChangeScreenNotification]
        watches = names.map { name in
            let leaving = name == NSWindow.willExitFullScreenNotification
            return NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(leaving: leaving) }
            }
        }
        refresh()
    }

    private func refresh(leaving: Bool = false) {
        guard let parent, !leaving, translucent, parent.styleMask.contains(.fullScreen),
              let screen = parent.screen, let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let picture = NSImage(contentsOf: url) else { return hide() }
        let window = backdrop ?? Self.makeBackdrop()
        backdrop = window
        window.contentView?.layer?.contents = picture
        // The desktop's "Fill Screen": the picture covers the screen, cut at the edges.
        window.contentView?.layer?.contentsGravity = .resizeAspectFill
        window.setFrame(screen.frame, display: true)
        if window.parent !== parent { parent.addChildWindow(window, ordered: .below) }
    }

    private func hide() {
        guard let backdrop else { return }
        backdrop.parent?.removeChildWindow(backdrop)
        backdrop.orderOut(nil)
    }

    private static func makeBackdrop() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.animationBehavior = .none
        window.contentView?.wantsLayer = true
        return window
    }
}
