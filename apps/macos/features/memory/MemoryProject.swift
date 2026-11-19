import CryptoKit
import Foundation

/// The folder of Claude's automatic memory for a session (plan 22, phase C):
/// `<memory>/auto/[<account key>/]<project key>`, given to the session as
/// `autoMemoryDirectory`, so every session of a project (its worktrees and
/// subfolders too) saves in the one folder the engine keeps the index of
/// (core/features/memory/server/src/auto_index.rs).
///
/// The project key is the rule of core/features/memory/server/src/project_key.rs,
/// written again here; a test on each side pins the same value:
/// 1. the session's folder, canonical (realpath; as given if it does not
///    resolve);
/// 2. up to the first folder holding `.git`: a `.git` folder is the common
///    dir; a `.git` file names its gitdir (`gitdir: <path>`, relative to the
///    folder holding it), whose `commondir` file names the common dir
///    (relative to the gitdir), else the gitdir is the common dir;
/// 3. a common dir named `.git`: the root is its parent; any other case (no
///    `.git`, a bare repository, a submodule) keeps the folder of step 1;
/// 4. the first 16 hex digits of the SHA-256 of the root's path.
/// Read from the files, not by asking git: this runs at every launch.
public enum MemoryProject {
    /// The folder's `project.json`, which the engine maps back to the
    /// project by (auto_wiki.rs).
    static let projectFile = "project.json"

    nonisolated static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    nonisolated static func join(_ base: String, _ path: String) -> String {
        path.hasPrefix("/") ? path : base + "/" + path
    }

    nonisolated static func read(_ path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }

    /// The common dir a worktree's `.git` file leads to.
    nonisolated static func commonDir(dotGit: String, holder: String) -> String? {
        guard let text = read(dotGit),
              let line = text.components(separatedBy: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let gitdir = join(holder, String(line.dropFirst("gitdir:".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        guard let common = read(gitdir + "/commondir") else { return gitdir }
        return join(gitdir, common.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Step 2: the common dir of the repository `cwd` is in (canonical), nil outside git. Its
    /// `info/exclude` is the one every worktree reads (MemoryMarkerPlace).
    public nonisolated static func gitCommonDir(cwd: String) -> String? {
        var dir = canonical(cwd)
        while true {
            let dotGit = (dir == "/" ? "" : dir) + "/.git"
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) {
                return (isDirectory.boolValue ? dotGit : commonDir(dotGit: dotGit, holder: dir)).map(canonical)
            }
            if dir == "/" || dir.isEmpty { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    /// Steps 1 to 3: the main checkout of the repository `cwd` is in, or
    /// `cwd` itself.
    public nonisolated static func mainRoot(cwd: String) -> String {
        let start = canonical(cwd)
        guard let common = gitCommonDir(cwd: start), (common as NSString).lastPathComponent == ".git" else { return start }
        return (common as NSString).deletingLastPathComponent
    }

    /// Step 4, for a root already found.
    public nonisolated static func key(root: String) -> String {
        let trimmed = root.count > 1 && root.hasSuffix("/") ? String(root.dropLast()) : root
        return SHA256.hash(data: Data(trimmed.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The session's folder for its automatic memory, made, with its
    /// project.json (`root`, and `account` when each account keeps its own
    /// memory). nil when it cannot be made: the session then keeps Claude's
    /// default folder.
    public nonisolated static func autoFolder(memory: String, cwd: String, account: String?) -> String? {
        let root = mainRoot(cwd: cwd)
        let dir = memory + "/auto/" + (account.map { $0 + "/" } ?? "") + key(root: root)
        let fm = FileManager.default
        guard (try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])) != nil else { return nil }
        let info: [String: Any] = ["root": root, "account": account ?? NSNull()]
        guard let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]) else { return nil }
        let path = dir + "/" + projectFile
        if fm.contents(atPath: path) != data, (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) == nil { return nil }
        return dir
    }
}
