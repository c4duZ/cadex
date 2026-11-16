import Checks
import Foundation
@testable import SessionKit

// Tests of the session kit. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

nonisolated(unsafe) let fm = FileManager.default

func scratch() -> String {
    let dir = NSTemporaryDirectory() + "cadex-kit-\(UUID().uuidString)"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

/// The --settings file a command names.
func settingsPath(_ command: String) -> String {
    let parts = command.components(separatedBy: " --settings ")
    guard parts.count > 1 else { return "" }
    var rest = parts[1]
    if rest.hasPrefix("'") { rest.removeFirst(); return String(rest.prefix { $0 != "'" }) }
    return String(rest.prefix { $0 != " " })
}

func json(_ path: String) -> [String: Any] {
    (fm.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

let launchExit = await Checks.run(launchChecks)
let exitCode = await Checks.run([
    ("the account key is the same rule as cadex statusline", {
        expect(SessionKit.accountKey("/Users/a/.claude-x") == "-Users-a--claude-x")
        expect(SessionKit.accountKey("/Users/a/My Acct_é") == "-Users-a-My-Acct---", "per UTF-8 byte, like the Zig side")
        expect(SessionKit.accountKey("/Users/a/.claude/") == "-Users-a--claude")
    }),
    ("an account's command: its folder, the kit's settings with the status line, the inherited CLAUDE_CODE_* dropped", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        try? fm.createDirectory(atPath: dir + "/acct", withIntermediateDirectories: true)
        fm.createFile(atPath: dir + "/acct/settings.json", contents: Data(#"{"statusLine":{"type":"command","command":"x","padding":2}}"#.utf8))
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/App/Cadex.app/Contents/Helpers/cadex",
                             environment: ["CLAUDECODE": "1", "CLAUDE_CODE_CHILD_SESSION": "1", "PATH": "/bin"])
        let command = kit.claudeCommand(configDir: dir + "/acct", arguments: ["--resume", "abc"], defaultClaudeJSON: dir + "/none.json")
        let settings = settingsPath(command)
        expect(command == "env -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION CLAUDE_CONFIG_DIR=\(dir)/acct claude --settings \(settings) --resume abc", command)
        expect(settings.hasPrefix(dir + "/kit/session-"), "one settings file per session")
        let session = String(settings.dropFirst((dir + "/kit/session-").count).dropLast(5))
        expect(kit.arguments(of: session) == ["--resume", "abc"], "the session's arguments kept for a hibernated agent")
        let file = json(settings)
        let line = file["statusLine"] as? [String: Any]
        expect(line?["command"] as? String == "/App/Cadex.app/Contents/Helpers/cadex statusline")
        expect(line?["padding"] as? Int == 2, "the owner's padding kept")
        // The session's token in env, never in the command; its file 0600 in the kit's tokens.
        let token = (file["env"] as? [String: String])?["CADEX_SESSION_TOKEN"] ?? ""
        expect(token.count == 64 && !command.contains(token), "a 32-byte token, kept out of the typed command")
        expect((file["env"] as? [String: String])?["CLAUDE_CODE_FORCE_SYNC_OUTPUT"] == "1", "synchronized output on: the terminal honors DEC 2026")
        let tokenFiles = ((try? fm.contentsOfDirectory(atPath: dir + "/kit/tokens")) ?? []).filter { $0.hasSuffix(".token") }
        expect(tokenFiles.count == 1 && (try? String(contentsOfFile: dir + "/kit/tokens/" + tokenFiles[0], encoding: .utf8)) == token)
        let mode = (try? fm.attributesOfItem(atPath: settings)[.posixPermissions] as? Int) ?? 0
        expect(mode == 0o600, "the settings carry the token: 0600")
        let hooks = file["hooks"] as? [String: Any]
        expect(Set(hooks?.keys.map { $0 } ?? []) == ["SessionStart", "Stop", "Notification", "PermissionRequest", "SessionEnd", "CwdChanged"], "\(String(describing: hooks?.keys))")
        let stop = ((hooks?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        expect(stop?["command"] as? String == "/App/Cadex.app/Contents/Helpers/cadex hook Stop")
        // agentTools.enabled: the folder of cadex first on the session's PATH (plan 20).
        kit.agentToolsOnPath = true
        let withTools = kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json")
        expect(withTools.hasPrefix("env -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION PATH=/App/Cadex.app/Contents/Helpers:\"$PATH\" CLAUDE_CONFIG_DIR="), withTools)
        kit.agentToolsOnPath = false
        kit.hooksEnabled = false
        expect(json(settingsPath(kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json")))["hooks"] == nil, "agents.stateHooks off: no hooks")
    }),
    ("the default account: no folder, a stray CLAUDE_CONFIG_DIR dropped; no tools, only the synchronized output", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: nil, environment: ["CLAUDE_CONFIG_DIR": "/other"])
        let command = kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/none.json")
        expect(command == "env -u CLAUDE_CONFIG_DIR claude --settings \(settingsPath(command))", command)
        let file = json(settingsPath(command))
        expect(file.keys.sorted() == ["env"] && (file["env"] as? [String: String]) == ["CLAUDE_CODE_FORCE_SYNC_OUTPUT": "1"], "\(file)")
        let clean = SessionKit(folder: dir + "/kit", toolsPath: nil, environment: [:])
        let plain = clean.claudeCommand(configDir: nil, arguments: ["--dangerously-skip-permissions"], defaultClaudeJSON: dir + "/none.json")
        expect(plain == "claude --settings \(settingsPath(plain)) --dangerously-skip-permissions", plain)
    }),
    ("the default account's MCP servers reach the others in a private file, never the default itself", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        fm.createFile(atPath: dir + "/home.json", contents: Data(#"{"mcpServers":{"docs":{"command":"docs-mcp"}}}"#.utf8))
        let kit = SessionKit(folder: dir + "/kit", toolsPath: nil, environment: [:])
        let other = kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/home.json")
        let mcp = dir + "/kit/mcp-" + SessionKit.accountKey(dir + "/acct") + ".json"
        expect(other.hasSuffix("--mcp-config " + mcp), other)
        expect((json(mcp)["mcpServers"] as? [String: Any])?["docs"] != nil)
        let mode = (try? fm.attributesOfItem(atPath: mcp)[.posixPermissions] as? Int) ?? 0
        expect(mode == 0o600, "mode \(String(mode, radix: 8))")
        expect(!kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/home.json").contains("--mcp-config"))
        let before = try? fm.contents(atPath: dir + "/home.json")
        expect(before == Data(#"{"mcpServers":{"docs":{"command":"docs-mcp"}}}"#.utf8), "the account's file never changes")
    }),
    ("features contribute: hooks on the same event add up, plugin folders become flags", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: nil, environment: [:])
        kit.contribute("a", SessionKitPart(settings: ["hooks": ["Stop": [["command": "a"]]]], pluginDirs: ["/p/a"]))
        kit.contribute("b", SessionKitPart(settings: ["hooks": ["Stop": [["command": "b"]]]]))
        let command = kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/none.json")
        expect(command.contains("--plugin-dir /p/a"), command)
        let settings = json(settingsPath(command))
        let stop = (settings["hooks"] as? [String: Any])?["Stop"] as? [Any]
        expect(stop?.count == 2, "\(settings)")
        kit.withdraw("a")
        expect(!kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/none.json").contains("--plugin-dir"))
    }),
    ("contributed hooks stay with agents.stateHooks off; per-account settings follow the session's account", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/bin/cadex", environment: [:])
        kit.hooksEnabled = false
        kit.contribute("memory", SessionKitPart(settings: ["hooks": ["Stop": [["command": "m"]]]],
                                                perAccount: { ["env": ["ACCOUNT": SessionKit.accountKey($0)]] }))
        let other = json(settingsPath(kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json")))
        let hooks = other["hooks"] as? [String: Any]
        expect(hooks?.keys.sorted() == ["Stop"] && (hooks?["Stop"] as? [Any])?.count == 1, "only the contributed hook: \(other)")
        let env = other["env"] as? [String: String]
        expect(env?["ACCOUNT"] == SessionKit.accountKey(dir + "/acct") && env?["CADEX_SESSION_TOKEN"]?.count == 64,
               "merged into the env, the token kept: \(other)")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let main = json(settingsPath(kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/none.json")))
        expect((main["env"] as? [String: String])?["ACCOUNT"] == SessionKit.accountKey(home + "/.claude"), "\(main)")
    }),
    ("words are quoted only when the shell needs it", {
        expect(SessionKit.quote("/a/b-c.json") == "/a/b-c.json")
        expect(SessionKit.quote("/a/Application Support/x") == "'/a/Application Support/x'")
        expect(SessionKit.quote("it's") == "'it'\\''s'")
    }),
    ("the cadex program is found in the bundle, else in the core's build", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let helper = dir + "/Cadex.app/Contents/Helpers/cadex"
        try? fm.createDirectory(atPath: (helper as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: helper, contents: Data(), attributes: [.posixPermissions: 0o755])
        expect(SessionKit.findTools(bundle: dir + "/Cadex.app", source: "/nowhere/a/b/c/d/e/f.swift") == helper)
        expect(SessionKit.findTools(bundle: dir + "/none.app", source: "/nowhere/a/b/c/d/e/f.swift") == nil)
    }),
])
exit(launchExit != 0 ? launchExit : exitCode)
