import AppKit

/// The window server's blur of what is behind a window (the strong glass, the owner's fork
/// screenshot, 2026-11-24): the desktop shows through with its shapes, softened, where the
/// system's frost (NSVisualEffectView) turned it into one flat gray. The call is the window
/// server's own, private but stable for years (Ghostty's and iTerm2's background blur use it);
/// looked up at run time, so a macOS without it only skips the blur.
@MainActor
public enum WindowBlur {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SetRadius = @convention(c) (Int32, Int, Int32) -> Int32

    private static let functions: (MainConnection, SetRadius)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let connection = dlsym(handle, "CGSMainConnectionID"),
              let radius = dlsym(handle, "CGSSetWindowBackgroundBlurRadius") else { return nil }
        return (unsafeBitCast(connection, to: MainConnection.self), unsafeBitCast(radius, to: SetRadius.self))
    }()

    /// The strong glass's radius in points (the fork's screenshot: the wallpaper's shapes still read).
    public static let strong = 24

    /// Blurs what is behind `window` by `radius` (0 takes it off). The window must be non-opaque
    /// with a clear background for it to show.
    public static func set(_ window: NSWindow?, radius: Int) {
        guard let window, window.windowNumber > 0, let (connection, set) = functions else { return }
        _ = set(connection(), window.windowNumber, Int32(radius))
    }
}
