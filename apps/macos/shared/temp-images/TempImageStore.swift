import Foundation

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
