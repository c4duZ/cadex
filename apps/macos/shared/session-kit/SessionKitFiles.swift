import Foundation

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
    /// Not yet: CLAUDE_CODE_FORCE_SYNC_OUTPUT and preferredNotifChannel
    /// (test 24, 2026-11-14) wait for the terminal to honor DEC 2026 and
    /// OSC 777 (plan 19, phase E); turning them on before would change
    /// nothing on screen.
    func writeSettings(key: String, accountDir: String) -> String? {
        var settings: [String: Any] = [:]
        if let tools = toolsPath {
            var line: [String: Any] = ["type": "command", "command": Self.quote(tools) + " statusline"]
            if let padding = Self.ownerPadding(accountDir) { line["padding"] = padding }
            settings["statusLine"] = line
        }
        for id in parts.keys.sorted() { settings = Self.merge(settings, parts[id]!.settings) }
        guard !settings.isEmpty else { return nil }
        return write(settings, name: "settings-\(key).json", mode: 0o644)
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
