import Foundation

/// Reads a subagent's log from where it stopped, only while its tab is open
/// (ADR 0019): in 256 KB pieces, so memory peaks at one piece and not at
/// the file (12 MB against 72 MB for the largest log, 2026-10-21), and only
/// the new bytes when the subagent writes more. A long result is never
/// held: its first 4 KB give the preview, its lines are counted as its
/// bytes go by. Used from one queue at a time.
final class AgentTranscriptReader: @unchecked Sendable {
    static let chunk = 256 * 1024
    static let head = 4096

    let path: String
    private(set) var offset: UInt64 = 0
    private var partial = Data()
    /// Inside a long line left out: its first bytes (a result's, for the
    /// preview; nil for an attachment) and the line breaks counted so far.
    private var skipping: (head: Data?, newlines: Int)?

    init(path: String) { self.path = path }

    /// The entries added since the last call; none if the file is gone.
    func readNew() -> [AgentTranscriptEntry] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        var entries: [AgentTranscriptEntry] = []
        while true {
            var piece = autoreleasepool { handle.readData(ofLength: Self.chunk) }
            if piece.isEmpty { break }
            offset += UInt64(piece.count)
            if let skip = skipping {
                guard let end = Self.newlines(in: piece).first else {
                    skipping = (skip.head, skip.newlines + Self.escapedNewlines(in: piece[...]))
                    continue
                }
                let count = skip.newlines + Self.escapedNewlines(in: piece[..<end])
                if let head = skip.head { entries.append(AgentTranscriptParse.longResult(head: head, newlines: count)) }
                piece = piece.subdata(in: end + 1..<piece.count)
                skipping = nil
            }
            partial.append(piece)
            var start = 0
            for end in Self.newlines(in: partial) {
                entries += autoreleasepool { Self.entries(partial[start..<end]) }
                start = end + 1
            }
            if start > 0 { partial = partial.subdata(in: start..<partial.count) }
            // A long unfinished line known to be left out: let go of it now.
            // Holding it, a 5 MB result was copied at each piece and memory
            // rose 3 MB per opening (2026-10-21).
            if partial.count > AgentTranscriptParse.long {
                let head = Data(partial.prefix(Self.head))
                if AgentTranscriptParse.isLeftOut(head: head) {
                    skipping = (AgentTranscriptParse.isResult(head: head) ? head : nil, Self.escapedNewlines(in: partial[...]))
                    partial = Data()
                }
            }
        }
        return entries
    }

    /// One whole line: a long one left out gives at most its preview, told
    /// in place and copied only when kept (a result's line can be megabytes).
    static func entries(_ line: Data) -> [AgentTranscriptEntry] {
        guard line.count > AgentTranscriptParse.long else { return AgentTranscriptParse.entries(Data(line)) }
        let head = Data(line.prefix(Self.head))
        guard AgentTranscriptParse.isLeftOut(head: head) else { return AgentTranscriptParse.entries(Data(line)) }
        return AgentTranscriptParse.isResult(head: head) ? [AgentTranscriptParse.longResult(head: head, newlines: escapedNewlines(in: line[...]))] : []
    }

    /// Where the line breaks are, by memchr: Data.firstIndex walked the
    /// 34 MB log byte by byte in 600 ms (2026-10-21).
    static func newlines(in data: Data) -> [Int] {
        data.withUnsafeBytes { raw -> [Int] in
            guard let base = raw.baseAddress else { return [] }
            var found: [Int] = []
            var at = 0
            while at < raw.count, let hit = memchr(base + at, 10, raw.count - at) {
                let index = base.distance(to: UnsafeRawPointer(hit))
                found.append(index)
                at = index + 1
            }
            return found
        }
    }

    /// The "\n" inside a JSON string: a result's lines, counted as bytes.
    static func escapedNewlines(in data: Data.SubSequence) -> Int {
        data.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress, raw.count > 1 else { return 0 }
            var count = 0
            var at = 0
            while at < raw.count - 1, let hit = memchr(base + at, 92, raw.count - at - 1) {
                let index = base.distance(to: UnsafeRawPointer(hit))
                if raw[index + 1] == 110 { count += 1 }
                at = index + 2
            }
            return count
        }
    }
}
