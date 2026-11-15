import Foundation

/// A comment the owner pinned to lines of a review (docs/spec/review.md):
/// the file, the side (old: lines the base had, else the work tree's), the
/// lines and their text, 3 lines around, and the Markdown the owner wrote.
public struct ReviewComment: Codable, Equatable, Sendable {
    public var id: String
    public var path: String
    public var old: Bool
    public var start: Int
    public var end: Int
    public var lines: [String]
    public var before: [String]
    public var after: [String]
    public var body: String
    public var created: Date
    /// Its lines are no longer in the file: it waits at the top, with the
    /// old excerpt, until the owner deletes or moves it.
    public var stale = false

    public init(path: String, old: Bool, start: Int, end: Int, lines: [String], before: [String], after: [String], body: String,
                id: String = UUID().uuidString, created: Date = Date()) {
        self.id = id
        self.path = path
        self.old = old
        self.start = start
        self.end = end
        self.lines = lines
        self.before = before
        self.after = after
        self.body = body
        self.created = created
    }

    /// "Lines 10–12" or "Line 10", and "(removed)" for the old side.
    public var title: String {
        let lines = start == end ? "line \(start)" : "lines \(start)–\(end)"
        return "\(path), \(lines)" + (old ? " (removed)" : "")
    }

    /// The comment in the file as it is now: where its excerpt is (the
    /// match whose context agrees most, then the nearest to where it was),
    /// or stale when the excerpt is gone.
    public func placed(in text: [String]) -> ReviewComment {
        var copy = self
        guard !lines.isEmpty, lines.count <= text.count else {
            copy.stale = true
            return copy
        }
        var best: (score: Int, distance: Int, at: Int)?
        for at in 0...(text.count - lines.count) where Array(text[at..<(at + lines.count)]) == lines {
            let score = Self.agreement(before.reversed(), text[..<at].reversed()) + Self.agreement(after, text[(at + lines.count)...])
            let distance = abs(at + 1 - start)
            if best == nil || score > best!.score || (score == best!.score && distance < best!.distance) { best = (score, distance, at) }
        }
        guard let found = best else {
            copy.stale = true
            return copy
        }
        copy.start = found.at + 1
        copy.end = found.at + lines.count
        copy.stale = false
        return copy
    }

    /// How many lines in a row agree, from the start of both.
    private static func agreement<A: Sequence, B: Sequence>(_ expected: A, _ actual: B) -> Int where A.Element == String, B.Element == String {
        var count = 0
        for (a, b) in zip(expected, actual) {
            guard a == b else { break }
            count += 1
        }
        return count
    }
}
