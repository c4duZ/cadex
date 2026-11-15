import Foundation
import CCadex

/// Plan 21 phase C's calls into the core: a version's bytes (an image, a
/// conflict's stage) and the conflict blocks, resolved one by one and
/// marked resolved. Like the rest of GitRepository, `blob` and
/// `markResolved` block on git: run them on `queue`.
extension GitRepository {
    /// One conflict block, in 0-based lines of the file (ends exclusive).
    struct ConflictBlock: Equatable, Sendable {
        let start: Int
        let ours: Range<Int>
        let base: Range<Int>?
        let theirs: Range<Int>
        let end: Int
    }

    enum Side: UInt8, Sendable { case ours = 0, theirs = 1, both = 2 }

    /// `rev`: a commit, "" the index, ":1" ":2" ":3" a conflict's base, ours, theirs.
    func blob(rev: String, path: String) -> Data? {
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        guard cadex_git_show_blob(root, rev, path, &out, &len) == CADEX_OK else { return nil }
        guard let out else { return Data() }
        defer { cadex_free(out) }
        return Data(bytes: out, count: len)
    }

    func markResolved(path: String, text: String) -> String? {
        let bytes = Array(text.utf8)
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        let status = bytes.withUnsafeBufferPointer { cadex_git_mark_resolved(root, path, $0.baseAddress, $0.count, &out, &len) }
        defer { cadex_free(out) }
        if status == CADEX_OK { return nil }
        guard let out else { return "git failed" }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }

    static func conflictBlocks(_ text: String) -> [ConflictBlock] {
        let bytes = Array(text.utf8)
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        guard bytes.withUnsafeBufferPointer({ cadex_git_conflict_blocks($0.baseAddress, $0.count, &out, &len) }) == CADEX_OK, let out else { return [] }
        defer { cadex_free(out) }
        let listing = String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
        return listing.split(separator: "\n").compactMap { line in
            let n = line.split(separator: "\t").compactMap { Int($0) }
            guard n.count == 8 else { return nil }
            return ConflictBlock(start: n[0], ours: n[1]..<n[2], base: n[3] < 0 ? nil : n[3]..<n[4], theirs: n[5]..<n[6], end: n[7])
        }
    }

    static func resolve(_ text: String, block: Int, side: Side) -> String? {
        let bytes = Array(text.utf8)
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        guard bytes.withUnsafeBufferPointer({ cadex_git_conflict_resolve($0.baseAddress, $0.count, block, side.rawValue, &out, &len) }) == CADEX_OK else { return nil }
        guard let out else { return "" }
        defer { cadex_free(out) }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }

    /// The first line (1-based) with a marker left, or nil.
    static func markerLine(_ text: String) -> Int? {
        let bytes = Array(text.utf8)
        let line = bytes.withUnsafeBufferPointer { cadex_git_conflict_marker($0.baseAddress, $0.count) }
        return line == 0 ? nil : line
    }
}
