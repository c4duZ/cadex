import Foundation
import SessionKit

/// What the memory adds to every session Cadex opens (plan 22, phase C;
/// docs/adr/0028-project-memory.md): `cadex memory-hook <event>` on the
/// events the engine takes, and in the settings' env where the engine and
/// its data are. The hooks never make the session wait outside SessionStart
/// (core/features/memory/hook_client.zig).
public enum MemoryKit {
    /// The kit's id for this part.
    public static let partID = "memory"

    /// The Claude Code events the memory captures. PostToolUse has no
    /// matcher, so every tool counts; the review's own PostToolUse entry
    /// (a matcher on edits) stays apart, and both run on an edit (ADR 0028,
    /// ~4 ms more).
    public static let hookEvents = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PreCompact", "PostCompact",
                                    "SubagentStart", "SubagentStop", "Stop", "SessionEnd"]

    /// `~/Library/Application Support/Cadex/memory`; CADEX_MEMORY_DIR for a
    /// test instance, which must not touch the owner's memory.
    public nonisolated static func folder(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let dir = environment["CADEX_MEMORY_DIR"], !dir.isEmpty { return dir }
        return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Cadex/memory"
    }

    /// The engine, `cadex-memory`: in the app bundle (Contents/Helpers,
    /// where packaging puts it), else the debug build `make app` makes next
    /// to this source (`make run`). nil: the hooks still queue the events,
    /// but nothing can start the engine.
    public nonisolated static func findEngine(bundle: String = Bundle.main.bundlePath, source: String = #filePath) -> String? {
        let fm = FileManager.default
        let bundled = bundle + "/Contents/Helpers/cadex-memory"
        if fm.isExecutableFile(atPath: bundled) { return bundled }
        var root = URL(fileURLWithPath: source)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let built = root.path + "/core/features/memory/server/target/debug/cadex-memory"
        return fm.isExecutableFile(atPath: built) ? built : nil
    }

    /// The plugin with ai-memory's own skills (when to search, save, hand
    /// off; `cadex-memory export-plugin`, plan 22 phase D): in the bundle's
    /// Resources (packaging writes it), else where `make app` writes it.
    public nonisolated static func findPlugin(bundle: String = Bundle.main.bundlePath, source: String = #filePath) -> String? {
        let fm = FileManager.default
        let bundled = bundle + "/Contents/Resources/memory-plugin"
        if fm.fileExists(atPath: bundled + "/.claude-plugin/plugin.json") { return bundled }
        var root = URL(fileURLWithPath: source)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let built = root.path + "/core/features/memory/server/target/memory-plugin"
        return fm.fileExists(atPath: built + "/.claude-plugin/plugin.json") ? built : nil
    }

    /// The part the kit merges into each session's `--settings`. `tools` is
    /// the `cadex` program. With `shareAcrossAccounts` off each account
    /// writes and reads its own workspace in the engine, named by the
    /// account's key (the rule of `cadex statusline`); on, all share
    /// `default`. A session whose folder is known saves Claude's automatic
    /// memory in the project's folder under the memory (`autoMemoryDirectory`,
    /// MemoryProject.swift), the account's own with sharing off; unknown,
    /// Claude's default folder stays.
    public nonisolated static func part(tools: String, engine: String?, shareAcrossAccounts: Bool, plugin: String? = nil,
                                        consolidateAt: Int? = nil,
                                        environment: [String: String] = ProcessInfo.processInfo.environment) -> SessionKitPart {
        let command = SessionKit.quote(tools) + " memory-hook "
        var hooks: [String: Any] = [:]
        for event in hookEvents {
            hooks[event] = [["hooks": [["type": "command", "command": command + event, "timeout": 5]]]]
        }
        let memory = folder(environment: environment)
        var env = env(engine: engine, environment: environment)
        // Consolidation in the session (plan 22 phase F): the hook's
        // milestone percent; absent, the hook never asks.
        if let consolidateAt { env["CADEX_MEMORY_CONSOLIDATE_AT"] = String(consolidateAt) }
        return SessionKitPart(settings: ["hooks": hooks, "env": env],
                              pluginDirs: plugin.map { [$0] } ?? [],
                              perAccount: shareAcrossAccounts ? nil : { accountDir in
                                  ["env": ["CADEX_MEMORY_WORKSPACE": SessionKit.accountKey(accountDir)]]
                              },
                              perSession: { accountDir, cwd in
                                  let account = shareAcrossAccounts ? nil : SessionKit.accountKey(accountDir)
                                  guard let dir = MemoryProject.autoFolder(memory: memory, cwd: cwd, account: account) else { return [:] }
                                  return ["autoMemoryDirectory": dir]
                              })
    }

    /// "The task is ready" for a session (plan 22 phase F): the file
    /// `cadex memory-hook` looks for at the session's next Stop
    /// (core/features/memory/consolidate.zig). False for a session id that
    /// is not a plain id.
    @discardableResult
    public nonisolated static func requestConsolidation(sessionID: String,
                                                       environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard !sessionID.isEmpty, sessionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return false }
        let dir = folder(environment: environment) + "/consolidate/requests"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return FileManager.default.createFile(atPath: dir + "/" + sessionID + ".ready", contents: Data(), attributes: [.posixPermissions: 0o600])
    }

    /// What "Consolidate Memory Now" pastes (no Enter); the hook knows it
    /// (`asked_prefix` in consolidate.zig) and adds the request next to it.
    public static let consolidateNowText = "Consolidate this session into the project memory."

    /// What `cadex memory-hook` reads (hook_client.zig): the engine, the
    /// data folder and, for a test instance only (CADEX_SOCKETS_DIR,
    /// CADEX_SESSIONS_DIR in the app's environment), its socket and tokens,
    /// as the kit does for CADEX_APP_SOCKET.
    nonisolated static func env(engine: String?, environment: [String: String]) -> [String: String] {
        var env = ["CADEX_MEMORY_DIR": folder(environment: environment)]
        if let engine { env["CADEX_MEMORY_BIN"] = engine }
        if let sockets = environment["CADEX_SOCKETS_DIR"], !sockets.isEmpty { env["CADEX_MEMORY_SOCKET"] = sockets + "/memory.sock" }
        if let tokens = environment["CADEX_SESSIONS_DIR"], !tokens.isEmpty { env["CADEX_SESSIONS_DIR"] = tokens }
        return env
    }
}
