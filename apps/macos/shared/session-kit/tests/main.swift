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

func json(_ path: String) -> [String: Any] {
    (fm.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

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
        let settings = dir + "/kit/settings-" + SessionKit.accountKey(dir + "/acct") + ".json"
        expect(command == "env -u CLAUDECODE -u CLAUDE_CODE_CHILD_SESSION CLAUDE_CONFIG_DIR=\(dir)/acct claude --settings \(settings) --resume abc", command)
        let line = json(settings)["statusLine"] as? [String: Any]
        expect(line?["command"] as? String == "/App/Cadex.app/Contents/Helpers/cadex statusline")
        expect(line?["padding"] as? Int == 2, "the owner's padding kept")
    }),
    ("the default account: no folder, a stray CLAUDE_CONFIG_DIR dropped; no tools, no settings", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: nil, environment: ["CLAUDE_CONFIG_DIR": "/other"])
        expect(kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/none.json") == "env -u CLAUDE_CONFIG_DIR claude")
        let clean = SessionKit(folder: dir + "/kit", toolsPath: nil, environment: [:])
        expect(clean.claudeCommand(configDir: nil, arguments: ["--dangerously-skip-permissions"], defaultClaudeJSON: dir + "/none.json")
               == "claude --dangerously-skip-permissions")
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
        let settings = json(dir + "/kit/settings-" + SessionKit.accountKey(fm.homeDirectoryForCurrentUser.path + "/.claude") + ".json")
        let stop = (settings["hooks"] as? [String: Any])?["Stop"] as? [Any]
        expect(stop?.count == 2, "\(settings)")
        kit.withdraw("a")
        expect(!kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/none.json").contains("--plugin-dir"))
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
exit(exitCode)
