import Foundation

/// Background images the user picked, kept as copies next to settings.json
/// (Application Support/Cadex/backgrounds), so moving or deleting the
/// original keeps the look (docs/spec/themes.md).
@MainActor
enum BackgroundImages {
    static var folder: URL {
        SettingsStore.defaultFile.deletingLastPathComponent().appendingPathComponent("backgrounds", isDirectory: true)
    }

    /// Copies `url` into the folder and returns the copy's path.
    static func keepCopy(of url: URL, into folder: URL = folder) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(UUID().uuidString).appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: copy)
        return copy.path
    }
}
