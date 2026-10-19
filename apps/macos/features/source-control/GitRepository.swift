import Foundation
import CCadex

/// One repository, through the core's source-control feature (cadex_git_*).
/// Every call blocks on `git`: callers run them on `queue`, never on the
/// main thread.
final class GitRepository: @unchecked Sendable {
    let root: String
    /// One git at a time per repository: index.lock forbids more anyway.
    let queue = DispatchQueue(label: "cadex.git")

    init(root: String) {
        self.root = root
    }

    struct Entry: Equatable, Sendable {
        enum Kind: Int, Sendable { case changed = 0, renamed = 1, conflict = 2, untracked = 3 }
        let kind: Kind
        let index: Character
        let worktree: Character
        let path: String
        let orig: String

        var isStaged: Bool { kind != .untracked && kind != .conflict && index != "." }
        var isUnstaged: Bool { kind == .untracked || (kind != .conflict && worktree != ".") }
        /// The letter shown for a side: ? for new files.
        func letter(staged: Bool) -> Character {
            if kind == .untracked { return "?" }
            if kind == .conflict { return "U" }
            return staged ? index : worktree
        }
    }

    struct Status: Equatable, Sendable {
        var branch = ""
        var oid = ""
        var upstream = ""
        var ahead = 0
        var behind = 0
        var entries: [Entry] = []
        var detached: Bool { branch.isEmpty }
    }

    static var isGitAvailable: Bool { cadex_git_available() }

    /// The repository holding `folder`, or nil.
    static func find(from folder: String) -> GitRepository? {
        let top = text { cadex_git_root(folder, &$0, &$1) }
        return top.map(GitRepository.init(root:))
    }

    func status() -> Status? {
        guard let text = Self.text({ cadex_git_status(root, &$0, &$1) }) else { return nil }
        return Self.parseStatus(text)
    }

    static func parseStatus(_ text: String) -> Status {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
        var status = Status()
        if let head = lines.first, head.count >= 5 {
            status = Status(branch: head[0], oid: head[1], upstream: head[2], ahead: Int(head[3]) ?? 0, behind: Int(head[4]) ?? 0)
            lines.removeFirst()
        }
        status.entries = lines.compactMap { f in
            guard f.count >= 5, let k = Int(f[0]), let kind = Entry.Kind(rawValue: k), let x = f[1].first, let y = f[2].first else { return nil }
            return Entry(kind: kind, index: x, worktree: y, path: f[3], orig: f[4])
        }
        return status
    }

    // MARK: Actions (nil: done; otherwise git's message)

    func stage(_ paths: [String]) -> String? { withPaths(paths) { cadex_git_stage(root, $0, $1, &$2, &$3) } }
    func unstage(_ paths: [String]) -> String? { withPaths(paths) { cadex_git_unstage(root, $0, $1, &$2, &$3) } }
    func discard(_ paths: [String]) -> String? { withPaths(paths) { cadex_git_discard(root, $0, $1, &$2, &$3) } }
    func commit(_ message: String, all: Bool) -> String? { action { cadex_git_commit(root, message, all, &$0, &$1) } }
    func fetch() -> String? { action { cadex_git_fetch(root, &$0, &$1) } }
    func pull() -> String? { action { cadex_git_pull(root, &$0, &$1) } }
    func push(publish branch: String?) -> String? { action { cadex_git_push(root, branch, &$0, &$1) } }
    func switchTo(_ name: String, remote: Bool) -> String? { action { cadex_git_switch(root, name, remote, &$0, &$1) } }
    static func initialize(_ folder: String) -> String? { action { cadex_git_init(folder, &$0, &$1) } }

    /// (name, remote) of every branch, the current one first.
    func branches() -> [(name: String, remote: Bool)] {
        (Self.text { cadex_git_branches(root, &$0, &$1) } ?? "").split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\t")
            guard f.count == 2 else { return nil }
            return (String(f[1]), f[0] == "remote")
        }
    }

    struct Diff: Sendable {
        var before: String
        var after: String
        var patch: String
        var binary: Bool
        var tooLarge: Bool
    }

    func diff(path: String, orig: String, staged: Bool) -> Diff? {
        sides { cadex_git_diff(root, path, orig.isEmpty ? nil : orig, staged, &$0) }
    }

    /// The file as commit `sha` changed it.
    func diff(commit sha: String, path: String, orig: String) -> Diff? {
        sides { cadex_git_diff_commit(root, sha, path, orig.isEmpty ? nil : orig, &$0) }
    }

    private func sides(_ call: (inout cadex_git_diff_sides) -> cadex_status) -> Diff? {
        var d = cadex_git_diff_sides()
        guard call(&d) == CADEX_OK else { return nil }
        defer { cadex_git_diff_free(&d) }
        func string(_ p: UnsafeMutablePointer<UInt8>?, _ n: Int) -> String {
            guard let p else { return "" }
            return String(decoding: UnsafeBufferPointer(start: p, count: n), as: UTF8.self)
        }
        return Diff(before: string(d.before, d.before_len), after: string(d.after, d.after_len),
                    patch: string(d.patch, d.patch_len), binary: d.binary, tooLarge: d.too_large)
    }

    // MARK: C plumbing

    private static func text(_ call: (inout UnsafeMutablePointer<UInt8>?, inout Int) -> cadex_status) -> String? {
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        guard call(&out, &len) == CADEX_OK else { return nil }
        guard let out else { return "" }
        defer { cadex_free(out) }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }

    private static func action(_ call: (inout UnsafeMutablePointer<UInt8>?, inout Int) -> cadex_status) -> String? {
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        let status = call(&out, &len)
        defer { cadex_free(out) }
        if status == CADEX_OK { return nil }
        if status == CADEX_GIT_MISSING { return "O git não foi encontrado" }
        guard let out else { return "O git falhou" }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }

    private func action(_ call: (inout UnsafeMutablePointer<UInt8>?, inout Int) -> cadex_status) -> String? {
        Self.action(call)
    }

    private func withPaths(_ paths: [String],
                           _ call: (UnsafePointer<UnsafePointer<CChar>?>, Int, inout UnsafeMutablePointer<UInt8>?, inout Int) -> cadex_status) -> String? {
        let copies = paths.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        let list = copies.map { UnsafePointer($0) }
        return list.withUnsafeBufferPointer { buffer in
            Self.action { out, len in call(buffer.baseAddress!, buffer.count, &out, &len) }
        }
    }
}
