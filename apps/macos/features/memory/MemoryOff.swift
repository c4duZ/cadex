import Foundation

/// The memory turned off (plan 35 I; docs/spec/memory.md, "Desligar"), a switch ai-memory does not
/// have. Two files in the memory's folder, read by the engine
/// (core/features/memory/server/src/off.rs) and, for a pause, by `cadex memory-hook`
/// (core/features/memory/hook_client.zig):
/// - `off-projects.json`, `{"roots":[…]}`: the main repository roots of the projects with the
///   memory off, written by the app from Cadex's projects file (the flag is this Mac's, not the
///   repository's .ai-memory.toml). The kit reads it too: a session Cadex opens in such a project
///   gets no memory hooks, tools or briefing (`MemoryKit.part`).
/// - `paused/<session id>`: a conversation whose memory is paused ("Pause Memory in This
///   Session"); from then on nothing of it is recorded. Removing it resumes.
/// Nothing recorded before is deleted.
public enum MemoryOff {
    public static let fileName = "off-projects.json"
    static let pausedFolder = "paused"
    /// A pause mark older than this belongs to a conversation long over (`prunePaused`).
    static let pausedDays = 30.0

    /// The roots in the file now; empty without one.
    public nonisolated static func roots(memory: String = MemoryKit.folder()) -> Set<String> {
        guard let data = FileManager.default.contents(atPath: memory + "/" + fileName),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let roots = object["roots"] as? [String] else { return [] }
        return Set(roots)
    }

    /// Writes the off roots (0600, by rename); unchanged, the file is left as it is.
    @discardableResult
    public nonisolated static func write(roots: Set<String>, memory: String = MemoryKit.folder()) -> Bool {
        let sorted = roots.map(MemoryProject.canonical).sorted()
        guard let data = try? JSONSerialization.data(withJSONObject: ["roots": sorted], options: [.sortedKeys, .withoutEscapingSlashes]) else { return false }
        let fm = FileManager.default
        let path = memory + "/" + fileName
        if fm.contents(atPath: path) == data { return true }
        try? fm.createDirectory(atPath: memory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tmp = path + ".tmp"
        guard fm.createFile(atPath: tmp, contents: data, attributes: [.posixPermissions: 0o600]) else { return false }
        return rename(tmp, path) == 0
    }

    /// Whether `cwd` is in an off project: under one of `roots`, or its main checkout is (a task's
    /// worktree outside the root). The engine's rule (off.rs).
    public nonisolated static func isOff(cwd: String, roots: Set<String>) -> Bool {
        guard !roots.isEmpty, !cwd.isEmpty else { return false }
        let canonical = roots.map(MemoryProject.canonical)
        let under = { (path: String) in canonical.contains { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") } }
        return under(MemoryProject.canonical(cwd)) || under(MemoryProject.mainRoot(cwd: cwd))
    }

    /// The same, reading the file (the kit, at each launch).
    public nonisolated static func isOff(cwd: String, memory: String = MemoryKit.folder()) -> Bool {
        isOff(cwd: cwd, roots: roots(memory: memory))
    }

    // MARK: Paused conversations

    nonisolated static func plain(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    nonisolated static func pausedPath(_ sessionID: String, memory: String) -> String {
        memory + "/" + pausedFolder + "/" + sessionID
    }

    public nonisolated static func isPaused(sessionID: String, memory: String = MemoryKit.folder()) -> Bool {
        plain(sessionID) && FileManager.default.fileExists(atPath: pausedPath(sessionID, memory: memory))
    }

    /// Pauses (or resumes) the memory of a Claude session; false for an id that is not plain.
    @discardableResult
    public nonisolated static func setPaused(_ paused: Bool, sessionID: String, memory: String = MemoryKit.folder()) -> Bool {
        guard plain(sessionID) else { return false }
        let fm = FileManager.default
        let path = pausedPath(sessionID, memory: memory)
        guard paused else {
            try? fm.removeItem(atPath: path)
            return true
        }
        try? fm.createDirectory(atPath: memory + "/" + pausedFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return fm.fileExists(atPath: path) || fm.createFile(atPath: path, contents: Data(), attributes: [.posixPermissions: 0o600])
    }

    /// The marks of conversations paused more than 30 days ago go (each is an empty file).
    public nonisolated static func prunePaused(memory: String = MemoryKit.folder(), now: Date = Date()) {
        let fm = FileManager.default
        let dir = memory + "/" + pausedFolder
        for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
            let date = (try? fm.attributesOfItem(atPath: dir + "/" + name)[.modificationDate] as? Date) ?? now
            if now.timeIntervalSince(date) > pausedDays * 86_400 { try? fm.removeItem(atPath: dir + "/" + name) }
        }
    }
}
