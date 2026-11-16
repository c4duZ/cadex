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

    /// The part the kit merges into each session's `--settings`. `tools` is
    /// the `cadex` program. With `shareAcrossAccounts` off each account
    /// writes and reads its own workspace in the engine, named by the
    /// account's key (the rule of `cadex statusline`); on, all share
    /// `default`.
    public nonisolated static func part(tools: String, engine: String?, shareAcrossAccounts: Bool,
                                        environment: [String: String] = ProcessInfo.processInfo.environment) -> SessionKitPart {
        let command = SessionKit.quote(tools) + " memory-hook "
        var hooks: [String: Any] = [:]
        for event in hookEvents {
            hooks[event] = [["hooks": [["type": "command", "command": command + event, "timeout": 5]]]]
        }
        return SessionKitPart(settings: ["hooks": hooks, "env": env(engine: engine, environment: environment)],
                              perAccount: shareAcrossAccounts ? nil : { accountDir in
                                  ["env": ["CADEX_MEMORY_WORKSPACE": SessionKit.accountKey(accountDir)]]
                              })
    }

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
