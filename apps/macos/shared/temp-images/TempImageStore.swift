import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG files an agent can be pointed to, kept in a folder of the temporary
/// directory and removed after a week so they do not pile up: images pasted
/// into the terminal (docs/plans/1-terminal.md) and pictures of elements
/// picked in the preview (docs/spec/preview.md).
public struct TempImageStore: Sendable {
    public static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    public let directory: URL
    /// The start of each file's name ("paste", "pick").
    public let prefix: String

    /// `folder` inside the temporary directory.
    public init(folder: String, prefix: String) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
        self.prefix = prefix
    }

    public init(directory: URL, prefix: String) {
        self.directory = directory
        self.prefix = prefix
    }

    /// The longest side, in pixels, an image keeps: past it Claude's API
    /// scales the image down anyway, and Claude Code took almost 8 s to
    /// show the tag of a 2940 × 1912 screenshot (2026-10-21).
    public static let maxSide = 1568

    /// The image no larger than maxSide on its longest side, as PNG; as it
    /// came when already that small or unreadable.
    public static func fitted(_ png: Data, maxSide: Int = maxSide) -> Data {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              max(width, height) > maxSide else { return png }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return png }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return png }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : png
    }

    public func save(_ png: Data, now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        // The suffix keeps two images of the same second apart.
        let name = "\(prefix)-\(formatter.string(from: now))-\(UUID().uuidString.prefix(4)).png"
        let url = directory.appendingPathComponent(name)
        try png.write(to: url)
        return url
    }

    /// Deletes images older than maxAge. Errors are ignored: a file that
    /// stays is harmless, and this runs while the app opens.
    public func removeOld(now: Date = Date()) {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.pathExtension == "png" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > Self.maxAge {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
