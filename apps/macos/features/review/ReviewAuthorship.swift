import Foundation

/// Who wrote each line, kept as ranges of the agent's lines with the
/// session that wrote them (docs/adr/0027-local-authorship.md); a line in
/// no range is the owner's, or unknown. Pure: the tracker reads the files.
public struct AuthorRange: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var session: String
}

public struct FileAuthorship: Codable, Equatable, Sendable {
    public var agent: [AuthorRange] = []
    /// The file passed the limits (2 MB, or the worktree's 50 MB of kept
    /// versions): its authorship stopped there.
    public var stopped = false
}

public enum Authorship {
    /// The marks of `old` moved onto `new`: an unchanged line keeps its
    /// author, a changed or new one loses the mark (it is the owner's
    /// unless an agent event says otherwise).
    public static func carry(_ ranges: [AuthorRange], from old: [String], to new: [String]) -> [AuthorRange] {
        guard !ranges.isEmpty else { return [] }
        let difference = new.difference(from: old)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var moved: [Int: String] = [:]
        let owners = lines(of: ranges)
        var j = 0
        for i in 0..<old.count where !removed.contains(i) {
            while inserted.contains(j) { j += 1 }
            if let session = owners[i + 1] { moved[j + 1] = session }
            j += 1
        }
        return join(moved)
    }

    /// The agent's lines of an edit added (a later edit of the same line wins).
    public static func add(_ ranges: [AuthorRange], lines added: [ClosedRange<Int>], session: String) -> [AuthorRange] {
        var all = lines(of: ranges)
        for range in added { for line in range { all[line] = session } }
        return join(all)
    }

    /// Line (1-based) → session.
    public static func lines(of ranges: [AuthorRange]) -> [Int: String] {
        var all: [Int: String] = [:]
        for range in ranges where range.start <= range.end { for line in range.start...range.end { all[line] = range.session } }
        return all
    }

    /// Consecutive lines of one session back into ranges.
    static func join(_ lines: [Int: String]) -> [AuthorRange] {
        var out: [AuthorRange] = []
        for line in lines.keys.sorted() {
            let session = lines[line]!
            if let last = out.last, last.end + 1 == line, last.session == session {
                out[out.count - 1].end = line
            } else {
                out.append(AuthorRange(start: line, end: line, session: session))
            }
        }
        return out
    }
}
