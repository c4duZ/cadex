import Checks
import Foundation
@testable import SessionKit

// The kit as pieces (SessionKitLaunch) and the `claude` typed by hand in a
// Cadex zsh tab (plan 22, phase C).

@MainActor let launchChecks: [(name: String, body: Checks.Body)] = [
    ("the typed command is the kit's pieces composed", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/H/cadex", environment: ["CLAUDECODE": "1"])
        kit.agentToolsOnPath = true
        kit.contribute("p", SessionKitPart(pluginDirs: ["/plug"]))
        let pieces = kit.launch(configDir: dir + "/acct", arguments: ["-c"], defaultClaudeJSON: dir + "/none.json")
        expect(pieces.unset == ["CLAUDECODE"] && pieces.pathFirst == "/H", "\(pieces)")
        expect(pieces.arguments.count == 4 && pieces.arguments[0] == "--settings" && pieces.arguments[2] == "--plugin-dir", "\(pieces.arguments)")
        expect(pieces.arguments[1].hasSuffix("session-\(pieces.session).json"))
        let composed = SessionKit.compose(unset: pieces.unset, configDir: dir + "/acct", arguments: pieces.arguments + ["-c"], pathFirst: pieces.pathFirst)
        let typed = kit.claudeCommand(configDir: dir + "/acct", arguments: ["-c"], session: pieces.session, defaultClaudeJSON: dir + "/none.json")
        expect(typed == composed, "\(typed)\n\(composed)")
    }),
    ("per-session settings come with the session's folder, for Cadex's launches and the typed claude", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/H/cadex", environment: [:])
        kit.contribute("p", SessionKitPart(perSession: { account, cwd in ["where": SessionKit.accountKey(account) + "@" + cwd] }))
        let opened = json(settingsPath(kit.claudeCommand(configDir: dir + "/acct", cwd: "/w/app", defaultClaudeJSON: dir + "/none.json")))
        expect(opened["where"] as? String == SessionKit.accountKey(dir + "/acct") + "@/w/app", "\(opened)")
        expect(json(settingsPath(kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json")))["where"] == nil,
               "no folder known: nothing")
        guard case .success(let typed) = kit.typedLaunch(configDir: "", cwd: "/w/tab", ownerSettings: nil, arguments: [], defaultClaudeJSON: dir + "/none.json")
        else { return expect(false, "refused") }
        expect((json(typed.arguments[1])["where"] as? String)?.hasSuffix("@/w/tab") == true, "the tab's folder")
    }),
    ("a launch's own variables (a dispatch's CADEX_DISPATCH_ID) reach only that session, under the kit's names", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/H/cadex", environment: [:])
        let command = kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json",
                                        sessionEnvironment: ["CADEX_DISPATCH_ID": "d-1", "CADEX_SESSION_TOKEN": "forged"])
        let env = json(settingsPath(command))["env"] as? [String: String] ?? [:]
        expect(env["CADEX_DISPATCH_ID"] == "d-1", "\(env)")
        expect(env["CADEX_SESSION_TOKEN"] != nil && env["CADEX_SESSION_TOKEN"] != "forged", "the kit's token wins")
        expect(!command.contains("d-1"), "never typed in the terminal")
        let other = json(settingsPath(kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json")))["env"] as? [String: String] ?? [:]
        expect(other["CADEX_DISPATCH_ID"] == nil, "another session does not get it")
    }),
    ("a typed claude: the tab's account, the owner's --settings merged in one file", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/H/cadex", environment: [:])
        let owner = #"{"model":"opus","statusLine":{"type":"command","command":"mine"},"hooks":{"Stop":[{"hooks":[{"command":"own-stop"}]}],"PreToolUse":[{"x":1}]},"env":{"A":"1","CADEX_SESSION_TOKEN":"fake","CLAUDE_CODE_FORCE_SYNC_OUTPUT":"0"}}"#
        fm.createFile(atPath: dir + "/own.json", contents: Data(owner.utf8))
        guard case .success(let pieces) = kit.typedLaunch(configDir: "", cwd: dir, ownerSettings: "own.json", arguments: ["go"], defaultClaudeJSON: dir + "/none.json")
        else { return expect(false, "refused") }
        expect(pieces.arguments.filter { $0 == "--settings" }.count == 1, "one --settings: \(pieces.arguments)")
        let file = json(pieces.arguments[1])
        expect(file["model"] as? String == "opus", "the owner's keys win")
        expect((file["statusLine"] as? [String: Any])?["command"] as? String == "/H/cadex statusline", "the kit's status line wins")
        let stop = (file["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
        let commands = stop.compactMap { ($0["hooks"] as? [[String: Any]])?.first?["command"] as? String }
        expect(commands == ["/H/cadex hook Stop", "own-stop"], "hooks add up, the kit's first: \(commands)")
        expect((file["hooks"] as? [String: Any])?["PreToolUse"] != nil && (file["hooks"] as? [String: Any])?["SessionStart"] != nil)
        let env = file["env"] as? [String: String] ?? [:]
        expect(env["A"] == "1" && env["CADEX_SESSION_TOKEN"]?.count == 64 && env["CLAUDE_CODE_FORCE_SYNC_OUTPUT"] == "0", "\(env)")
        expect(kit.arguments(of: pieces.session) == ["go"])
        // Inline JSON works the same.
        guard case .success(let inline) = kit.typedLaunch(configDir: dir + "/acct", cwd: dir, ownerSettings: #"{"model":"haiku"}"#, arguments: [],
                                                          defaultClaudeJSON: dir + "/none.json")
        else { return expect(false, "inline refused") }
        expect(json(inline.arguments[1])["model"] as? String == "haiku")
    }),
    ("a typed claude: the kit's own file and settings that do not read are refused", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/H/cadex", environment: [:])
        let command = kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/none.json")
        let own = kit.typedLaunch(configDir: "", cwd: "/", ownerSettings: settingsPath(command), arguments: [])
        expect(own == .failure(SessionKitRefusal(reason: "a session the kit already set up")), "\(own)")
        let missing = kit.typedLaunch(configDir: "", cwd: dir, ownerSettings: "nope.json", arguments: [])
        expect(missing == .failure(SessionKitRefusal(reason: "the --settings given do not read")), "\(missing)")
        expect((try? kit.typedLaunch(configDir: "", cwd: dir, ownerSettings: nil, arguments: [], defaultClaudeJSON: dir + "/none.json").get()) != nil)
    }),
]
