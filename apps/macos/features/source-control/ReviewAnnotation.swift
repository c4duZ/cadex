import Foundation

/// A note the app pins under lines of the review (plan 21 phase D: the
/// review feature's comments come through here, so this feature knows
/// nothing of them). `line` is the last line it covers, on the new side
/// (`old` false) or the old one; a stale note sits at the top of its file.
public struct ReviewAnnotation: Equatable, Sendable {
    public let id: String
    public let path: String
    public let old: Bool
    public let line: Int
    public let title: String
    public let text: String
    public let stale: Bool

    public init(id: String, path: String, old: Bool, line: Int, title: String, text: String, stale: Bool) {
        self.id = id
        self.path = path
        self.old = old
        self.line = line
        self.title = title
        self.text = text
        self.stale = stale
    }
}

/// Lines the owner marked to comment on: one file, one side, a run of
/// lines with their text and 3 lines around (so a comment can find its
/// place again after the agent edits the file).
public struct ReviewLineSelection: Equatable, Sendable {
    public let path: String
    public let old: Bool
    public let start: Int
    public let end: Int
    public let lines: [String]
    public let before: [String]
    public let after: [String]

    public init(path: String, old: Bool, start: Int, end: Int, lines: [String], before: [String], after: [String]) {
        self.path = path
        self.old = old
        self.start = start
        self.end = end
        self.lines = lines
        self.before = before
        self.after = after
    }
}

extension ReviewLayout {
    /// The annotations of a file, to put in its rows.
    static func annotationRows(for file: Int, path: String, rows: [Row], annotations: [ReviewAnnotation]) -> [Row] {
        var result = rows
        let mine = annotations.enumerated().filter { $0.element.path == path }
        // Stale ones under the header, in order.
        var top = 1
        for (index, note) in mine where note.stale {
            result.insert(.annotation(file: file, index: index), at: min(top, result.count))
            top += 1
        }
        for (index, note) in mine.reversed() where !note.stale {
            let at = result.lastIndex { row in
                guard case .line(_, let kind, let old, let new, _) = row else { return false }
                return note.old ? (kind != .added && old == note.line) : (kind != .removed && new == note.line)
            }
            // A line not shown (a binary, a note) puts it under the header.
            result.insert(.annotation(file: file, index: index), at: at.map { $0 + 1 } ?? min(top, result.count))
        }
        return result
    }
}
