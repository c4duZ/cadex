import AppKit
import CoreImage
import UILooks

/// The desktop behind a translucent window in the system's full screen.
///
/// The system's full screen puts the window on a Space of its own over black, so the glass
/// (appearance.windowOpacity) showed black instead of the desktop (the owner, 2026-11-24). Cadex's
/// own full screen stayed on the desktop's Space for that, but it was not a real full screen (the
/// owner, 2026-11-27: in a Space of its own, "mostrar o desktop atrás, sem alterar a visão que
/// teríamos se fosse uma tela cheia em um desktop vazio").
///
/// A window behind Cadex's does not work there: the full screen's Space puts every other window of
/// the app, a child one too, over the full-screen window (3.1.9 showed the bare wallpaper over
/// Cadex, the owner's screenshot, 2026-11-27). So the wallpaper is drawn inside the window, at the
/// bottom, as the desktop draws it ("Fill Screen"), and the glass blurs it as it blurs the desktop:
/// the frost blends within the window while this shows (WorkspaceView), and under the strong glass,
/// whose blur is the window server's of what is behind the window, the picture comes blurred by the
/// same radius (WindowBlur.strong).
@MainActor
final class FullScreenWallpaper: NSView {
    /// The window is translucent, and its glass is the strong one (WorkspaceView sets them with the looks).
    var looks: (translucent: Bool, strong: Bool) = (false, false) {
        didSet { if looks != oldValue { refresh() } }
    }
    /// Shown or hidden: the workspace sets its frost to blend within the window, or behind it again.
    var onChange: (() -> Void)?
    private(set) var isShowing = false
    private var watches: [NSObjectProtocol] = []
    /// The picture as read and as blurred, made once per wallpaper file and blur.
    private var cache: (url: URL, strong: Bool, image: CGImage)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FullScreenWallpaper is created in code") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        watches.forEach(NotificationCenter.default.removeObserver)
        watches = []
        guard let window else { return }
        // On entering, before the animation, so the window grows into its Space with the picture.
        let names = [NSWindow.willEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification]
        watches = names.map { name in
            let entering = name == NSWindow.willEnterFullScreenNotification
            return NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(entering: entering) }
            }
        }
        refresh()
    }

    private func refresh(entering: Bool = false) {
        let full = entering || window?.styleMask.contains(.fullScreen) == true
        let picture = full && looks.translucent ? wallpaper() : nil
        layer?.contents = picture
        isHidden = picture == nil
        guard isShowing != (picture != nil) else { return }
        isShowing = picture != nil
        onChange?()
    }

    /// The window's screen's wallpaper; nil when the system gives no picture file (the Space's
    /// black then shows, as before).
    private func wallpaper() -> CGImage? {
        guard let screen = window?.screen ?? NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if let cache, cache.url == url, cache.strong == looks.strong { return cache.image }
        guard let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // The window server's blur radius counts the screen's pixels, and it reads as about twice
        // a Gaussian's: taken as points of the picture (≈65 px on a 4K wallpaper), the full
        // screen's wallpaper went to a shapeless fog the desktop never shows (the owner's
        // screenshot, 2026-11-27: "está opaco").
        let screenPixels = max(screen.frame.width * screen.backingScaleFactor, 1)
        let radius = CGFloat(WindowBlur.strong) * CGFloat(source.width) / screenPixels / 2
        let image = looks.strong ? Self.blurred(source, radius: radius) ?? source : source
        cache = (url, looks.strong, image)
        return image
    }

    private static func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        // Clamped first so the edges do not fade to black.
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }
}
