import Foundation
import Tabs

/// The spaces as saved (docs/spec/spaces.md): Application Support/Cadex/
/// spaces.json, written whole and atomically, so a crash leaves the old
/// file or the new one, never half of one.
public struct SavedSpaces: Codable, Equatable, Sendable {
    public struct Space: Codable, Equatable, Sendable {
        public var name: String
        public var tabs: TabsSnapshot

        public init(name: String, tabs: TabsSnapshot) {
            self.name = name
            self.tabs = tabs
        }
    }

    /// Bumped when the format changes in a way old files cannot be read.
    public var version = 1
    public var spaces: [Space]
    public var active: Int
    /// The workspace folder (the explorer's root), for a launch without one:
    /// from the Dock there is never a folder argument.
    public var folder: String?

    public init(spaces: [Space], active: Int, folder: String? = nil) {
        self.spaces = spaces
        self.active = active
        self.folder = folder
    }
}

public enum SpacesFile {
    /// CADEX_SPACES_FILE points somewhere else: checking the app must not
    /// overwrite the owner's spaces.
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["CADEX_SPACES_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cadex/spaces.json")
    }

    /// The saved spaces; nil without a file. A file that does not read is
    /// moved aside (spaces.bad-<date>.json) and the app starts fresh.
    public static func load(from url: URL) -> SavedSpaces? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let saved = try? JSONDecoder().decode(SavedSpaces.self, from: data), !saved.spaces.isEmpty {
            return saved
        }
        moveAside(url)
        return nil
    }

    public static func save(_ spaces: SavedSpaces, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(spaces).write(to: url, options: .atomic)
    }

    static func moveAside(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = url.deletingPathExtension().lastPathComponent + ".bad-\(stamp)." + url.pathExtension
        try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name))
    }
}
