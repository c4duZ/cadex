import Foundation

/// Whether Claude Code already trusts a folder, read from the account's
/// `.claude.json` without writing (docs/adr/0033-cadex-launches-agents.md:
/// a session opened with a prompt in an untrusted folder stops at the trust
/// dialog, and `claude --bg` exits "Workspace not trusted"). The field is
/// `projects[<folder>].hasTrustDialogAccepted` (seen in a test account,
/// Claude Code 2.1.325, 2026-11-16). Trust passes to child folders (seen
/// 2026-11-14), and for a worktree the main repository's counts
/// (docs/spec/worktrees.md, tested 2026-11-15).
public enum ClaudeTrust {
    /// The `.claude.json` of an account: ~/.claude.json for the default one
    /// (`configDir` nil), else inside its folder.
    public static func file(configDir: String?) -> String {
        configDir.map { $0 + "/.claude.json" } ?? FileManager.default.homeDirectoryForCurrentUser.path + "/.claude.json"
    }

    /// The trusted folders of a `.claude.json`'s contents; empty when it does not read.
    public static func trustedFolders(_ data: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let projects = root["projects"] as? [String: Any] else { return [] }
        return projects.compactMap { folder, value in
            ((value as? [String: Any])?["hasTrustDialogAccepted"] as? Bool) == true ? folder : nil
        }
    }

    /// `folder` (or `repository`, the main one of a worktree) is a trusted
    /// folder or inside one.
    public static func isTrusted(_ folder: String, repository: String? = nil, trusted: [String]) -> Bool {
        let roots = trusted.map(normalized)
        // Claude Code keeps real paths (/private/tmp, not /tmp): links resolved here too.
        let asked = [folder] + (repository.map { [$0] } ?? [])
        return (asked + asked.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }).map(normalized).contains { path in
            roots.contains { root in path == root || path.hasPrefix(root == "/" ? "/" : root + "/") }
        }
    }

    /// Reads the account's file; false when there is none.
    public static func isTrusted(_ folder: String, repository: String?, configDir: String?) -> Bool {
        guard let data = FileManager.default.contents(atPath: file(configDir: configDir)) else { return false }
        return isTrusted(folder, repository: repository, trusted: trustedFolders(data))
    }

    static func normalized(_ path: String) -> String {
        let standard = (path as NSString).standardizingPath
        return standard.count > 1 && standard.hasSuffix("/") ? String(standard.dropLast()) : standard
    }
}
