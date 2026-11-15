import AppKit
import CoreGraphics
import ScreenCaptureKit
import TempImages

/// The picture of one app's front window, never the whole screen
/// (docs/adr/0026-computer-use.md), by ScreenCaptureKit; kept in the
/// temporary folder as the preview's pictures.
@MainActor
enum ComputerUseShot {
    static let pictures = TempImageStore(folder: "cadex-computer", prefix: "window")

    /// The PNG's path, or the reason it could not be taken.
    static func window(of pid: pid_t, then done: @escaping @MainActor (Result<String, ComputerUseError>) -> Void) {
        guard CGPreflightScreenCaptureAccess() else { return done(.failure(.permission("Screen Recording"))) }
        guard #available(macOS 14.0, *) else { return done(.failure(.failed("window pictures need macOS 14"))) }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: true) { content, _ in
            let window = content?.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            guard let window else {
                return DispatchQueue.main.async { done(.failure(.failed("the app has no window on screen"))) }
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, _ in
                DispatchQueue.main.async {
                    guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                          let url = try? pictures.save(TempImageStore.fitted(png)) else { return done(.failure(.failed("the picture could not be taken"))) }
                    done(.success(url.path))
                }
            }
        }
    }
}

public enum ComputerUseError: Error, Equatable, Sendable {
    case permission(String)
    case failed(String)
}
