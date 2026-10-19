import Foundation

/// The pieces of a path for the status bar: "Home › Cadu › cadex"
/// (docs/spec/status-bar.md). Pure, so the rules are testable.
public enum Breadcrumb {
    public struct Segment: Equatable {
        public let title: String
        /// The folder this piece stands for; nil for the "…" of elided pieces.
        public let path: String?
    }

    /// The pieces of `path`. Under home, the first piece is "Home" for the
    /// home folder; elsewhere it is "/". With more than `maxSegments`
    /// pieces, the middle ones become "…" and the current folder stays.
    public static func segments(of path: String, home: String, maxSegments: Int = 6) -> [Segment] {
        var segments: [Segment] = []
        var current: String
        var rest: Substring
        if path == home || path.hasPrefix(home + "/") {
            segments.append(Segment(title: "Home", path: home))
            current = home
            rest = path.dropFirst(home.count)
        } else {
            segments.append(Segment(title: "/", path: "/"))
            current = ""
            rest = Substring(path)
        }
        for name in rest.split(separator: "/") {
            current += "/" + name
            segments.append(Segment(title: String(name), path: current))
        }
        guard segments.count > maxSegments, maxSegments >= 3 else { return segments }
        // Keep the root, then "…", then the last pieces.
        let tail = segments.suffix(maxSegments - 2)
        return [segments[0], Segment(title: "…", path: nil)] + tail
    }

    /// The folders inside `path`, by name, without hidden ones. Nil when the
    /// folder cannot be read.
    public static func subfolders(of path: String) -> [String]? {
        let url = URL(fileURLWithPath: path)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return nil }
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
