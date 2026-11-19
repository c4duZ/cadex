import Foundation

/// The repository's .ai-memory.toml made by Cadex and where it lives (plan 35 B; the owner,
/// 2026-11-19: the file in every project, in the repository's git by default, "only on this Mac"
/// as a choice). Upstream makes it only with `ai-memory project init` at a terminal
/// (docs/research/ai-memory-upstream.md, "1. O marcador"); Cadex makes the same file by itself.
extension MemoryMarker {
    /// What upstream's `project init` writes (`workspace`, `project`), the brief turned on, and the
    /// other keys commented with upstream's defaults, so the owner sees what can be set.
    public static func template(project: String) -> String {
        """
        # ai-memory's settings for this repository, read by the memory's hooks at every session.
        # What each key does: https://github.com/akitaonrails/ai-memory/blob/main/docs/marker-file.md
        # Cadex made this file; the project's Memory settings in Cadex edit it. A commented key
        # keeps upstream's default.

        workspace = "default"
        project = \(quoted(project))
        # drop_subagent_captures = false

        [briefing]
        inject_on_session_start = true
        # max_chars = 4000
        # inject_on_subagent_start = false

        [handoff]
        # deliver_on_session_start = true

        [recovery]
        # deliver_on_session_start = true

        [recall]
        # default_global = false

        [profile]
        # contribute = true
        # consume = true

        [capture]
        # ignore_paths = []

        """
    }

    /// The name the memory already gives the project: its main checkout's folder (the rule of
    /// MemoryProject.mainRoot and the engine's project_key.rs). Pinning it keeps the memory where
    /// it is.
    public nonisolated static func projectName(folder: String) -> String {
        let name = (MemoryProject.mainRoot(cwd: folder) as NSString).lastPathComponent
        return name.isEmpty ? (folder as NSString).lastPathComponent : name
    }

    /// Makes `<root>/.ai-memory.toml` from the template when there is none; never overwrites
    /// (another process, or the owner, may have written one a moment ago: the file goes in by
    /// `link`, which fails when the name exists). true when this call made it. Off the main
    /// thread at launch: one call per project.
    @discardableResult
    public nonisolated static func ensure(root: String, project: String) -> Bool {
        let path = (root as NSString).appendingPathComponent(fileName)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue,
              !FileManager.default.fileExists(atPath: path) else { return false }
        let temporary = (root as NSString).appendingPathComponent(".\(fileName).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(atPath: temporary, contents: Data(template(project: project).utf8)) else { return false }
        defer { unlink(temporary) }
        return link(temporary, path) == 0
    }

    /// `ensure` for a project's folder, named as the memory names it.
    @discardableResult
    public nonisolated static func ensure(folder: String) -> Bool {
        ensure(root: folder, project: projectName(folder: folder))
    }
}

/// "Only on this Mac": the line `/.ai-memory.toml` in the repository's `info/exclude`, in the
/// git common dir (a worktree's `.git` file leads there; every worktree reads it). Read from the
/// files, no `git` process; Cadex never adds or commits (plan 35, decided with the owner).
public enum MemoryMarkerPlace {
    public static let excludeLine = "/" + MemoryMarker.fileName

    /// The exclude file of the repository `folder` is in; nil outside git.
    public nonisolated static func excludeFile(folder: String) -> String? {
        MemoryProject.gitCommonDir(cwd: folder).map { $0 + "/info/exclude" }
    }

    /// The file is kept out of git on this Mac.
    public nonisolated static func isLocalOnly(folder: String) -> Bool {
        guard let file = excludeFile(folder: folder), let text = MemoryProject.read(file) else { return false }
        return text.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == excludeLine }
    }

    /// Adds the line (once) or removes exactly that line; the rest of the file stays. false when
    /// the folder is not in git or the file cannot be written.
    @discardableResult
    public nonisolated static func setLocalOnly(_ on: Bool, folder: String) -> Bool {
        guard let file = excludeFile(folder: folder) else { return false }
        let old = MemoryProject.read(file) ?? ""
        let new = excluding(on, in: old)
        guard new != old else { return true }
        try? FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        return (try? new.write(toFile: file, atomically: true, encoding: .utf8)) != nil
    }

    /// The exclude file's text with the line, or without it. Pure.
    static func excluding(_ on: Bool, in text: String) -> String {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let has = lines.contains { $0.trimmingCharacters(in: .whitespaces) == excludeLine }
        guard on != has else { return text }
        if on { lines.append(excludeLine) }
        if !on { lines.removeAll { $0.trimmingCharacters(in: .whitespaces) == excludeLine } }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
}
