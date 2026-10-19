import Foundation
import CCadex

/// One commit of the history, with its row of the graph when there is one.
struct HistoryCommit: Equatable, Sendable {
    struct Segment: Equatable, Sendable {
        let from: Int
        let to: Int
        let color: Int
    }

    struct Graph: Equatable, Sendable {
        let column: Int
        let color: Int
        let top: [Segment]
        let bottom: [Segment]

        /// The widest lane the row touches.
        var width: Int { ([column] + (top + bottom).flatMap { [$0.from, $0.to] }).max().map { $0 + 1 } ?? 1 }
    }

    let sha: String
    let parents: [String]
    let author: String
    let email: String
    let date: Date
    /// "HEAD -> main", "origin/main", "tag: v1"...
    let refs: [String]
    let subject: String
    let graph: Graph?

    var shortSha: String { String(sha.prefix(7)) }

    /// A line of cadex_history_next.
    static func parse(_ line: Substring) -> HistoryCommit? {
        let f = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard f.count >= 11, !f[0].isEmpty else { return nil }
        let column = Int(f[7]) ?? -1
        let graph = column < 0 ? nil : Graph(column: column, color: Int(f[8]) ?? 0, top: segments(f[9]), bottom: segments(f[10]))
        return HistoryCommit(
            sha: String(f[0]), parents: f[1].split(separator: " ").map(String.init),
            author: String(f[2]), email: String(f[3]),
            date: Date(timeIntervalSince1970: TimeInterval(Int(f[4]) ?? 0)),
            refs: f[5].isEmpty ? [] : f[5].components(separatedBy: ", "),
            subject: String(f[6]), graph: graph)
    }

    private static func segments(_ text: Substring) -> [Segment] {
        text.split(separator: " ").compactMap { part in
            let n = part.split(separator: ",").compactMap { Int($0) }
            return n.count == 3 ? Segment(from: n[0], to: n[1], color: n[2]) : nil
        }
    }
}

/// A commit's message and files (cadex_history_details).
struct CommitDetails: Equatable, Sendable {
    struct File: Equatable, Sendable {
        let letter: Character
        /// nil for a binary file.
        let added: Int?
        let removed: Int?
        let path: String
        let orig: String
    }

    let parents: [String]
    let message: String
    let files: [File]

    static func parse(_ text: String) -> CommitDetails {
        let parts = text.split(separator: "\u{1e}", maxSplits: 2, omittingEmptySubsequences: false)
        let parents = parts.first.map { $0.split(separator: " ").map(String.init) } ?? []
        let message = parts.count > 1 ? parts[1].trimmingCharacters(in: .newlines) : ""
        let files = (parts.count > 2 ? parts[2] : "").split(separator: "\n").compactMap { line -> File? in
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard f.count >= 5, let letter = f[0].first else { return nil }
            return File(letter: letter, added: Int(f[1]), removed: Int(f[2]), path: String(f[3]), orig: String(f[4]))
        }
        return CommitDetails(parents: parents, message: message, files: files)
    }
}

/// The log of a repository through the core (cadex_history_*). Each call
/// blocks on git: run them on `queue`, never on the main thread.
final class HistoryLog: @unchecked Sendable {
    static let pageSize = 500
    let root: String
    let query: String
    let currentOnly: Bool
    let queue = DispatchQueue(label: "cadex.history")
    private var handle: OpaquePointer?
    private(set) var ended = false
    /// git failed (as opposed to a repository without commits).
    private(set) var failed = false

    init(root: String, query: String = "", currentOnly: Bool = false) {
        self.root = root
        self.query = query
        self.currentOnly = currentOnly
    }

    deinit {
        cadex_history_close(handle)
    }

    /// The next page; an empty one when the log ended or git failed.
    func next() -> [HistoryCommit] {
        if handle == nil, cadex_history_open(root, query, currentOnly, &handle) != CADEX_OK {
            ended = true
            failed = true
        }
        guard let handle, !ended else { return [] }
        guard let text = Self.text({ cadex_history_next(handle, Self.pageSize, &$0, &$1) }) else {
            ended = true
            failed = true
            return []
        }
        let commits = text.split(separator: "\n").compactMap(HistoryCommit.parse)
        if commits.count < Self.pageSize { ended = true }
        return commits
    }

    func details(_ sha: String) -> CommitDetails? {
        Self.text { cadex_history_details(root, sha, &$0, &$1) }.map(CommitDetails.parse)
    }

    /// The commit's page on origin, or nil without a known remote.
    func remoteURL(_ sha: String) -> URL? {
        Self.text { cadex_history_remote_url(root, sha, &$0, &$1) }.flatMap(URL.init(string:))
    }

    private static func text(_ call: (inout UnsafeMutablePointer<UInt8>?, inout Int) -> cadex_status) -> String? {
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        guard call(&out, &len) == CADEX_OK else { return nil }
        guard let out else { return "" }
        defer { cadex_free(out) }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }
}
