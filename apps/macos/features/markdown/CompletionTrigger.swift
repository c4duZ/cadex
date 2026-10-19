import Foundation

/// What the text before the cursor asks to complete (docs/spec/markdown.md):
/// a path after `](`, a heading after `](file#`, a note after `[[`.
enum CompletionTrigger: Equatable {
    /// `range` is the part typed so far, replaced by the choice.
    case path(query: String, range: NSRange)
    case heading(file: String, query: String, range: NSRange)
    case note(query: String, range: NSRange)

    var range: NSRange {
        switch self {
        case let .path(_, range), let .heading(_, _, range), let .note(_, range): range
        }
    }

    /// Looks back on the cursor's line only, at most this far.
    private static let lookBack = 300

    static func detect(in text: NSString, cursor: Int) -> CompletionTrigger? {
        guard cursor <= text.length else { return nil }
        let lineStart = text.lineRange(for: NSRange(location: cursor, length: 0)).location
        let from = max(lineStart, cursor - lookBack)
        let before = text.substring(with: NSRange(location: from, length: cursor - from)) as NSString
        let link = before.range(of: "](", options: .backwards)
        let wiki = before.range(of: "[[", options: .backwards)
        if wiki.location != NSNotFound, link.location == NSNotFound || wiki.location > link.location {
            let typed = before.substring(from: NSMaxRange(wiki))
            guard !typed.contains("]") else { return nil }
            return .note(query: typed, range: NSRange(location: from + NSMaxRange(wiki), length: (typed as NSString).length))
        }
        guard link.location != NSNotFound else { return nil }
        let typed = before.substring(from: NSMaxRange(link))
        guard !typed.contains(")"), !typed.contains(" ") else { return nil }
        let start = from + NSMaxRange(link)
        if let hash = typed.firstIndex(of: "#") {
            let file = String(typed[..<hash])
            let query = String(typed[typed.index(after: hash)...])
            let offset = (file as NSString).length + 1
            return .heading(file: file, query: query, range: NSRange(location: start + offset, length: (query as NSString).length))
        }
        return .path(query: typed, range: NSRange(location: start, length: (typed as NSString).length))
    }

    /// `target` (relative to the root) as written from the note `from`
    /// (relative too): ../spec/search.md.
    static func relativePath(to target: String, from: String) -> String {
        let fromDirs = (from as NSString).deletingLastPathComponent.split(separator: "/").map(String.init)
        let parts = target.split(separator: "/").map(String.init)
        var shared = 0
        while shared < fromDirs.count, shared < parts.count - 1, fromDirs[shared] == parts[shared] { shared += 1 }
        let up = Array(repeating: "..", count: fromDirs.count - shared)
        return (up + parts[shared...]).joined(separator: "/")
    }
}
