import CCadex
import Foundation
import Strings

/// One worktree of a repository.
public struct TaskWorktree: Equatable, Sendable {
    public let path: String
    /// Empty when detached.
    public let branch: String
    public let head: String
}

/// The core's worktrees feature (cadex_worktrees_*): a task's worktree
/// through the user's git, only in authorized folders.
public enum WorktreesCore {
    /// "Corrigir login" -> "corrigir-login".
    public static func branchName(_ name: String) -> String {
        text { cadex_worktrees_branch_name(name, &$0, &$1) } ?? "task"
    }

    /// The repository's worktrees, the main one first.
    public static func list(repo: String) -> [TaskWorktree] {
        (text { cadex_worktrees_list(repo, &$0, &$1) } ?? "").split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { return nil }
            return TaskWorktree(path: fields[0], branch: fields[1], head: fields[2])
        }
    }

    /// A new branch from `base` in a worktree at `path`; git's message when it refused.
    static func create(repo: String, path: String, branch: String, base: String) -> String? {
        action { cadex_worktrees_create(repo, path, branch, base, &$0, &$1) }
    }

    /// What `.worktreeinclude` names, copied; the count and the lines that matched nothing.
    static func copyIncludes(repo: String, worktree: String) -> (copied: Int, unmatched: [String]) {
        var copied = 0
        let unmatched = text { cadex_worktrees_copy_includes(repo, worktree, &copied, &$0, &$1) } ?? ""
        return (copied, unmatched.split(separator: "\n").map(String.init))
    }

    /// What taking it away would lose, one per line; nil when git failed.
    static func whatWouldBeLost(path: String, branch: String) -> [String]? {
        text { cadex_worktrees_what_would_be_lost(path, branch, &$0, &$1) }.map { $0.split(separator: "\n").map(String.init) }
    }

    /// Takes it away and, with `branch`, its branch when merged; git's message when it refused.
    static func remove(repo: String, path: String, branch: String?) -> String? {
        action { cadex_worktrees_remove(repo, path, branch, &$0, &$1) }
    }

    /// The repository holding `folder`, or nil.
    /// `git worktree prune`; git's message when it refused.
    static func prune(repo: String) -> String? { action { cadex_worktrees_prune(repo, &$0, &$1) } }

    /// `git branch -D`; git's message when it refused.
    static func deleteBranch(repo: String, branch: String) -> String? { action { cadex_worktrees_delete_branch(repo, branch, &$0, &$1) } }

    public static func repository(of folder: String) -> String? {
        text { cadex_git_root(folder, &$0, &$1) }
    }

    /// The branch checked out in `repo` (empty when detached).
    static func currentBranch(_ repo: String) -> String {
        let status = text { cadex_git_status(repo, &$0, &$1) } ?? ""
        return status.split(separator: "\n").first?.split(separator: "\t", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    }

    /// Lets the core work in `path` (the workspace's authorized folders).
    static func authorize(_ path: String) -> Bool {
        var out: UnsafeMutablePointer<UInt8>?
        var len = 0
        defer { cadex_free(out) }
        return cadex_workspace_authorize(path, &out, &len) == CADEX_OK
    }

    static func isAuthorized(_ path: String) -> Bool { cadex_workspace_is_authorized(path) }

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
        if status == CADEX_GIT_MISSING { return T("Git was not found", "O git não foi encontrado") }
        guard let out else { return T("Git failed", "O git falhou") }
        return String(decoding: UnsafeBufferPointer(start: out, count: len), as: UTF8.self)
    }
}
