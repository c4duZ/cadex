import Foundation
import Security

/// The kit's files: one settings file per account (the owner's status
/// line padding differs) and, for accounts other than the default, an MCP
/// file. Written atomically before each launch.
extension SessionKit {
    /// The kit's `--settings`: the status line through `cadex statusline`
    /// (it keeps the usage and calls the owner's own, which `--settings`
    /// replaces, tested 2026-11-14) and what the features contribute. Hooks
    /// passed this way add to the account's and the project's (tested), so
    /// the owner's keep running.
    ///
    /// CLAUDE_CODE_FORCE_SYNC_OUTPUT=1: Claude Code wraps each redraw in a
    /// synchronized update only for terminals it knows by TERM_PROGRAM; with
    /// it, 10 updates in a session's first seconds instead of 0 (tested
    /// 2026-11-15, 2.1.325, also through this env), and the terminal holds
    /// the frame until each ends (plan 19, phase E).
    /// `owner`: the owner's own `--settings` of a typed `claude`, merged in
    /// (SessionKitLaunch.swift), since two `--settings` do not add up.
    func writeSettings(session: String, token: String?, accountDir: String, owner: [String: Any]? = nil) -> String? {
        var settings: [String: Any] = [:]
        if let tools = toolsPath {
            var line: [String: Any] = ["type": "command", "command": Self.quote(tools) + " statusline"]
            if let padding = Self.ownerPadding(accountDir) { line["padding"] = padding }
            settings["statusLine"] = line
            if hooksEnabled { settings["hooks"] = Self.hooks(tools) }
        }
        // The settings' env reaches the hooks (tested 2026-11-15): the token
        // travels here, never typed in the terminal or kept in shell history.
        var env: [String: String] = [:]
        if synchronizedOutput { env["CLAUDE_CODE_FORCE_SYNC_OUTPUT"] = "1" }
        if let token, toolsPath != nil {
            env["CADEX_SESSION_TOKEN"] = token
            // A test instance's own socket (CADEX_SOCKETS_DIR): its sessions'
            // hooks go there, not to the owner's app (hook.zig reads this).
            if ProcessInfo.processInfo.environment["CADEX_SOCKETS_DIR"] != nil { env["CADEX_APP_SOCKET"] = SessionKit.socketsFolder + "/app.sock" }
        }
        if !env.isEmpty { settings["env"] = env }
        // Contributed hooks stay with agents.stateHooks off: that setting is
        // about the kit's own hooks only (the memory's run regardless).
        for id in parts.keys.sorted() {
            settings = Self.merge(settings, parts[id]!.settings)
            if let perAccount = parts[id]!.perAccount { settings = Self.merge(settings, perAccount(accountDir)) }
        }
        if let owner { settings = Self.mergeOwner(kit: settings, owner: owner) }
        guard !settings.isEmpty || owner != nil else { return nil }
        pruneSessions()
        return write(settings, name: "session-\(session).json", mode: 0o600)
    }

    /// The events that tell the app what a session does (plan 19, phase B):
    /// each runs `cadex hook <event>`, which never makes the session wait,
    /// save PermissionRequest (docs/adr/0023-answer-agent-permissions.md).
    static let hookEvents = ["SessionStart", "Stop", "Notification", "PermissionRequest", "SessionEnd", "CwdChanged"]

    static func hooks(_ tools: String) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: hookEvents.map { event in
            (event, [["hooks": [["type": "command", "command": quote(tools) + " hook " + event,
                                 "timeout": event == "PermissionRequest" ? 600 : 5]]]])
        })
    }

    /// A random token for the session, in its own file (0600): the app's
    /// socket takes the session's word only with it. nil when it cannot be
    /// kept (the session then works, without telling the app).
    /// The arguments a session was opened with (`--model`, the permission
    /// flag, …), beside its token for as long (30 days): a hibernated agent
    /// comes back with the same command (plan 19 phase F).
    func writeArguments(_ arguments: [String], session: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments) else { return }
        try? FileManager.default.createDirectory(atPath: tokens, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        FileManager.default.createFile(atPath: tokens + "/" + session + ".args.json", contents: data, attributes: [.posixPermissions: 0o600])
    }

    /// What `writeArguments` kept for `session`; nil when nothing was.
    public func arguments(of session: String) -> [String]? {
        guard let data = FileManager.default.contents(atPath: tokens + "/" + session + ".args.json") else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String]
    }

    /// The token a kit session already has, if its file is still there.
    func existingToken(session: String) -> String? {
        let token = (try? String(contentsOfFile: tokens + "/" + session + ".token", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.count == 64 ? token : nil
    }

    func writeToken(session: String) -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        let fm = FileManager.default
        try? fm.createDirectory(atPath: tokens, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let path = tokens + "/" + session + ".token"
        guard fm.createFile(atPath: path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600]) else { return nil }
        return token
    }

    /// Old sessions' settings go after 2 days (a session reads them at
    /// start), their tokens after 30 (a hibernated session comes back with
    /// its token, plan 19 phase F).
    func pruneSessions(now: Date = Date()) {
        let fm = FileManager.default
        for (dir, prefix, age) in [(folder, "session-", 2.0), (tokens, "", 30.0)] {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasPrefix(prefix) && (name.hasSuffix(".json") || name.hasSuffix(".token")) {
                let path = dir + "/" + name
                let date = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? now
                if now.timeIntervalSince(date) > age * 86_400 { try? fm.removeItem(atPath: path) }
            }
        }
    }

    /// The default account's MCP servers (read only from its .claude.json;
    /// the default account loads them itself) and the features' ones. The
    /// file is the user's own data, so only the user reads it (0600).
    func writeMCP(key: String, isDefault: Bool, defaultClaudeJSON: String) -> String? {
        var servers: [String: Any] = [:]
        if !isDefault, let data = FileManager.default.contents(atPath: defaultClaudeJSON),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let own = object["mcpServers"] as? [String: Any] {
            servers = own
        }
        for id in parts.keys.sorted() { servers.merge(parts[id]!.mcpServers) { _, new in new } }
        guard !servers.isEmpty else { return nil }
        return write(["mcpServers": servers], name: "mcp-\(key).json", mode: 0o600)
    }

    /// The `padding` of the owner's status line, so the line sits where it did.
    static func ownerPadding(_ accountDir: String) -> Any? {
        guard let data = FileManager.default.contents(atPath: accountDir + "/settings.json"),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let line = object["statusLine"] as? [String: Any] else { return nil }
        return line["padding"]
    }

    /// Objects merge key by key, arrays add up, anything else: the later wins.
    static func merge(_ a: [String: Any], _ b: [String: Any]) -> [String: Any] {
        var out = a
        for (key, new) in b {
            switch (out[key], new) {
            case (let old as [String: Any], let new as [String: Any]): out[key] = merge(old, new)
            case (let old as [Any], let new as [Any]): out[key] = old + new
            default: out[key] = new
            }
        }
        return out
    }

    private func write(_ object: [String: Any], name: String, mode: Int) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]) else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let path = folder + "/" + name
        if fm.contents(atPath: path) == data { return path }
        // Born with its mode, then renamed over: never readable by others,
        // never half written.
        let tmp = path + ".\(ProcessInfo.processInfo.processIdentifier).tmp"
        guard fm.createFile(atPath: tmp, contents: data, attributes: [.posixPermissions: mode]) else { return nil }
        guard rename(tmp, path) == 0 else {
            try? fm.removeItem(atPath: tmp)
            return nil
        }
        return path
    }
}
