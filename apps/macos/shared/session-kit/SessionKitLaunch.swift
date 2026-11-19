import Foundation

/// What a session gets from the kit, as pieces: the command Cadex types
/// (`claudeCommand`) is these composed for the shell, and the `claude`
/// typed by hand in a Cadex zsh tab (`cadex claude`, plan 22 phase C)
/// gets them as data over the app's socket.
public struct SessionKitLaunch: Equatable, Sendable {
    /// The kit session (the name of its settings and token files).
    public var session: String
    /// Names the session must not inherit (CLAUDECODE, CLAUDE_CODE_*, a
    /// stray CLAUDE_CONFIG_DIR for the default account).
    public var unset: [String]
    /// The folder of `cadex`, first on PATH (agentTools.enabled).
    public var pathFirst: String?
    /// `--settings …`, `--plugin-dir …`, `--mcp-config …`, before the
    /// session's own words.
    public var arguments: [String]
}

/// Why the kit was not given; the typed `claude` then runs as typed.
public struct SessionKitRefusal: Error, Equatable {
    public let reason: String
}

extension SessionKit {
    /// The kit for a session in an account (`configDir` nil: the default
    /// one), writing its files first; `arguments` are kept beside the token
    /// (a hibernated agent comes back with them). `owner`: the owner's own
    /// settings, merged into the kit's file. `cwd`: the session's folder,
    /// when known (the parts' `perSession`).
    public func launch(configDir: String?, arguments: [String] = [], session reused: String? = nil, cwd: String? = nil,
                       defaultClaudeJSON: String = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude.json",
                       owner: [String: Any]? = nil, sessionEnvironment: [String: String] = [:], leaving: Set<String> = []) -> SessionKitLaunch {
        let accountDir = configDir ?? FileManager.default.homeDirectoryForCurrentUser.path + "/.claude"
        var args: [String] = []
        let session = reused ?? UUID().uuidString.lowercased()
        let token = reused.flatMap(existingToken) ?? writeToken(session: session)
        writeArguments(arguments, session: session)
        let parts = parts(cwd: cwd, leaving: leaving)
        if let settings = writeSettings(session: session, token: token, accountDir: accountDir, cwd: cwd, owner: owner,
                                       sessionEnvironment: sessionEnvironment, parts: parts) { args += ["--settings", settings] }
        for dir in parts.flatMap(\.part.pluginDirs).sorted() { args += ["--plugin-dir", dir] }
        if let mcp = writeMCP(key: Self.accountKey(accountDir), isDefault: configDir == nil, defaultClaudeJSON: defaultClaudeJSON) { args += ["--mcp-config", mcp] }
        return SessionKitLaunch(session: session, unset: unsetNames(isDefault: configDir == nil),
                                pathFirst: agentToolsOnPath ? toolsPath.map { ($0 as NSString).deletingLastPathComponent } : nil,
                                arguments: args)
    }

    /// The kit for a `claude` typed in a Cadex terminal, in the tab's own
    /// account (`configDir`, its CLAUDE_CONFIG_DIR; empty is the default)
    /// and folder. `ownerSettings`: the value of the owner's `--settings`
    /// (a file, relative to `cwd`, or inline JSON), merged into the kit's.
    /// Refused when that file is the kit's own (the command Cadex types for
    /// a session goes through the same shell function) or does not read.
    public func typedLaunch(configDir: String, cwd: String, ownerSettings: String?, arguments: [String],
                            defaultClaudeJSON: String = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude.json")
        -> Result<SessionKitLaunch, SessionKitRefusal> {
        var owner: [String: Any]?
        if let value = ownerSettings {
            if isKitFile(value, cwd: cwd) { return .failure(SessionKitRefusal(reason: "a session the kit already set up")) }
            guard let read = Self.readOwnerSettings(value, cwd: cwd) else { return .failure(SessionKitRefusal(reason: "the --settings given do not read")) }
            owner = read
        }
        return .success(launch(configDir: configDir.isEmpty ? nil : configDir, arguments: arguments, cwd: cwd,
                               defaultClaudeJSON: defaultClaudeJSON, owner: owner))
    }

    /// A path inside the kit's folder (`session-….json`).
    func isKitFile(_ value: String, cwd: String) -> Bool {
        guard !value.trimmingCharacters(in: .whitespaces).hasPrefix("{") else { return false }
        let path = Self.absolute(value, cwd: cwd)
        let kit = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
        return path.hasPrefix(kit + "/") || path.hasPrefix((folder as NSString).standardizingPath + "/")
    }

    static func absolute(_ value: String, cwd: String) -> String {
        let path = value.hasPrefix("/") ? value : (cwd as NSString).appendingPathComponent(value)
        return URL(fileURLWithPath: (path as NSString).standardizingPath).resolvingSymlinksInPath().path
    }

    /// The owner's `--settings`: inline JSON (Claude Code takes a value
    /// starting with "{" as JSON) or a file; nil when neither reads as an
    /// object.
    static func readOwnerSettings(_ value: String, cwd: String) -> [String: Any]? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = trimmed.hasPrefix("{") ? Data(trimmed.utf8) : FileManager.default.contents(atPath: absolute(value, cwd: cwd))
        return data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    }

    /// The owner's settings over the kit's, in one file (two `--settings`
    /// do not add up: only the last counts, tested 2026-11-15): the owner's
    /// keys win, except `statusLine` (the kit's keeps the usage and calls
    /// the owner's own); `hooks` add up per event, the kit's first; `env`
    /// merges, the kit's CADEX_* winning (the session's token).
    static func mergeOwner(kit: [String: Any], owner: [String: Any]) -> [String: Any] {
        var out = kit
        for (key, value) in owner {
            switch key {
            case "statusLine":
                if kit["statusLine"] == nil { out[key] = value }
            case "hooks":
                guard let own = value as? [String: Any] else { continue }
                var hooks = kit["hooks"] as? [String: Any] ?? [:]
                for (event, groups) in own { hooks[event] = (hooks[event] as? [Any] ?? []) + (groups as? [Any] ?? []) }
                out["hooks"] = hooks
            case "env":
                guard let own = value as? [String: Any] else { continue }
                var env = kit["env"] as? [String: Any] ?? [:]
                for (name, v) in own where !(name.hasPrefix("CADEX_") && env[name] != nil) { env[name] = v }
                out["env"] = env
            default:
                out[key] = value
            }
        }
        return out
    }
}

extension SessionKit {
    static let permissionWords: Set<String> = ["--permission-mode", "--dangerously-skip-permissions", "--allow-dangerously-skip-permissions"]

    /// The typed `claude`'s permission flag (plan 33 F): with "Without permission prompts" on
    /// (agents.launchSkipPermissions), every `claude` typed in a Cadex tab skips them, as the ones
    /// Cadex opens, unless the line already says how to ask.
    public static func skipPermissions(on: Bool, typed: [String]) -> [String] {
        guard on, !typed.contains(where: { permissionWords.contains($0) || $0.hasPrefix("--permission-mode=") }) else { return [] }
        return ["--dangerously-skip-permissions"]
    }
}
