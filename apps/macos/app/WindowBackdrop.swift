import AppKit
import CoreImage

/// The optional looks of the window (docs/spec/themes.md): a background
/// image behind the terminal area, with opacity and blur, and vibrancy that
/// frosts the frame over what is behind the window. Both off by default:
/// they cost compositing on every frame.
@MainActor
final class WindowBackdrop {
    struct Image: Equatable {
        var path: String
        var opacity: Double
        var blur: Double
    }

    /// The blurred image, made once per path and blur, not per frame.
    private var cache: (key: Image, image: CGImage)?

    /// The image ready to show, or nil when the file is gone (the area then
    /// shows the theme's color, as the spec says).
    func image(for setting: Image) -> CGImage? {
        if let cache, cache.key.path == setting.path, cache.key.blur == setting.blur { return cache.image }
        guard let source = NSImage(contentsOfFile: setting.path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let image = setting.blur > 0 ? Self.blurred(source, radius: setting.blur) ?? source : source
        cache = (setting, image)
        return image
    }

    private static func blurred(_ image: CGImage, radius: Double) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        // Clamped first so the edges do not fade to transparent.
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent) else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
    }
}
