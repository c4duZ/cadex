import Checks
import Foundation
import SessionKit
@testable import Agents

// The usage without a token (docs/adr/0021-cadex-managed-accounts.md, plan
// 18 phase B): the login from .claude.json, the numbers from the files
// `cadex statusline` writes, and opening an account's agent with the kit.

/// A usage file as `cadex statusline` writes it.
func usageFile(_ folder: String, _ dir: String, at: TimeInterval, session: Double, resets: Any) {
    let resetsText = resets is String ? "\"\(resets)\"" : "\(resets)"
    write(folder + "/" + SessionKit.accountKey(dir) + ".json",
          #"{"at":\#(Int(at)),"config_dir":"\#(dir)","rate_limits":{"five_hour":{"used_percentage":\#(session),"resets_at":\#(resetsText)},"seven_day":{"used_percentage":12,"resets_at":\#(Int(at) + 86_400 * 3)}}}"#)
}

let usageChecks: [(name: String, body: Checks.Body)] = [
    ("the login: oauthAccount says there is one, its plan and who; no token anywhere", {
        let login = AgentAccountLogin.parse(Data(#"{"oauthAccount":{"accountUuid":"a1","organizationUuid":"o1","organizationType":"claude_max"}}"#.utf8))
        expect(login == AgentAccountLogin(plan: "max", fingerprint: "a1/o1"), "\(String(describing: login))")
        expect(AgentAccountLogin.parse(Data(#"{"oauthAccount":{}}"#.utf8)) == nil)
        expect(AgentAccountLogin.parse(Data(#"{"projects":{}}"#.utf8)) == nil)
        let home = AgentAccount(dir: "/Users/me/.claude", name: "d", isDefault: true)
        expect(AgentAccountLogin.file(of: home) == "/Users/me/.claude.json", "the default keeps it beside the folder")
        expect(AgentAccountLogin.file(of: AgentAccount(dir: "/Users/me/.claude-w", name: "w", isDefault: false)) == "/Users/me/.claude-w/.claude.json")
    }),
    ("the usage file: percentages and resets, in seconds or ISO text; a window that reset shows 0%", {
        let folder = NSTemporaryDirectory() + "cadex-usage-file-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: folder) }
        let now = Date()
        usageFile(folder, "/a", at: now.timeIntervalSince1970 - 60, session: 42.5, resets: Int(now.timeIntervalSince1970) + 3600)
        let (usage, at) = AgentUsage.parseFile(fm.contents(atPath: folder + "/-a.json")!, now: now)!
        expect(usage.session?.percent == 42.5 && usage.week?.percent == 12 && usage.session?.resets != nil, "\(usage)")
        expect(abs(at.timeIntervalSince(now) + 60) < 2)
        usageFile(folder, "/b", at: now.timeIntervalSince1970 - 30_000, session: 80, resets: "2020-01-01T00:00:00Z")
        let reset = AgentUsage.parseFile(fm.contents(atPath: folder + "/-b.json")!, now: now)?.0
        expect(reset?.session?.percent == 0, "reset since: 0%")
        expect(AgentUsage.parseFile(Data("{broken".utf8)) == nil && AgentUsage.parseFile(Data(#"{"rate_limits":{}}"#.utf8)) == nil)
    }),
    ("reading usage: numbers from the file, no file says open from Cadex, no login stays out, an auth failure until a later session", {
        let home = NSTemporaryDirectory() + "cadex-usage-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: home) }
        write(home + "/.claude-ok/.claude.json", #"{"oauthAccount":{"accountUuid":"u","organizationType":"claude_team"}}"#)
        write(home + "/.claude-new/.claude.json", #"{"oauthAccount":{"accountUuid":"v"}}"#)
        write(home + "/.claude-none/.claude.json", "{}")
        let usage = AgentUsageController.shared
        usage.accounts = { AgentAccount.find(home: home) }
        usage.folder = home + "/usage"
        usageFile(usage.folder, home + "/.claude-ok", at: Date().timeIntervalSince1970, session: 2, resets: Int(Date().timeIntervalSince1970) + 3600)
        expect(!usage.isRunning, "nobody watching: no timer")
        let token = usage.watch {}
        let done = await eventually { usage.states[home + "/.claude-none"] == .noLogin }
        expect(done, "\(usage.states)")
        expect(usage.states[home + "/.claude-ok"]?.usage?.session?.percent == 2 && usage.plans[home + "/.claude-ok"] == "team")
        expect(usage.states[home + "/.claude-new"] == .noUsage)
        expect(usage.isStale(home + "/.claude-none") && !usage.isStale(home + "/.claude-new"))

        usage.loginFailed(home + "/.claude-ok", at: Date().addingTimeInterval(5))
        usage.tick()
        expect(usage.states[home + "/.claude-ok"] == .expired, "the old numbers do not undo a failure")
        usage.expiredSince[home + "/.claude-ok"] = Date().addingTimeInterval(-3 * 86_400)
        expect(usage.isStale(home + "/.claude-ok"), "out for over a day: left out")
        usage.expiredSince[home + "/.claude-ok"] = Date().addingTimeInterval(5)
        usageFile(usage.folder, home + "/.claude-new", at: Date().timeIntervalSince1970, session: 7, resets: Int(Date().timeIntervalSince1970) + 3600)
        let seen = await eventually { usage.states[home + "/.claude-new"]?.usage?.session?.percent == 7 }
        expect(seen, "a new file is seen without asking: \(String(describing: usage.states[home + "/.claude-new"]))")
        usageFile(usage.folder, home + "/.claude-ok", at: Date().timeIntervalSince1970 + 10, session: 3, resets: Int(Date().timeIntervalSince1970) + 3600)
        usage.tick()
        expect(usage.states[home + "/.claude-ok"]?.usage?.session?.percent == 3, "a later session works: the failure is gone")
        write(home + "/.claude-later/.claude.json", #"{"oauthAccount":{"accountUuid":"w"}}"#)
        usage.tick()
        let later = await eventually { usage.states[home + "/.claude-later"] == .noUsage }
        expect(later, "an account that shows up later is read at once, not in 5 min")
        usage.stop(token)
        expect(!usage.isRunning)
        usage.folder = AgentUsageFile.folder()
    }),
    ("a hidden login kept before plan 18 (the token's expiry) does not bring the account back", {
        expect(AgentUsageController.isLegacy("1763100000000") && !AgentUsageController.isLegacy("a1/o1") && !AgentUsageController.isLegacy("login"))
    }),
    ("the agent's own report says why it stopped: permission, question, finished", {
        expect(AgentStop.fromReport(state: "blocked", kind: "permission", message: "approve Bash: touch x") == .permission(tool: "Bash", subject: "touch x"))
        expect(AgentStop.fromReport(state: "blocked", kind: "question", message: "answer: Qual cor? (Azul · Verde)") == .question("Qual cor? (Azul · Verde)"))
        expect(AgentStop.fromReport(state: "done", kind: "none", message: "") == .finished(""))
        expect(AgentStop.fromReport(state: "working", kind: "none", message: "Creating…") == nil, "working is no stop")
    }),
    ("a turn that failed to log in is a stop of its own", {
        let line = #"{"type":"assistant","error":"authentication_failed","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"Login expired · Please run /login"}]}}"#
        expect(AgentStop.classify([line]) == .loginExpired)
    }),
    ("opening an account's agent: the kit's command, the flag only when asked; Codex as before", {
        let folder = NSTemporaryDirectory() + "cadex-launch-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: folder) }
        let kit = SessionKit.forTests(folder: folder)
        let work = AgentAccount(dir: "/Users/me/.claude-work", name: "W", isDefault: false)
        let none = folder + "/none.json"
        expect(AgentLaunch.command(for: work, skipPermissions: false, kit: kit, defaultClaudeJSON: none) == "CLAUDE_CONFIG_DIR=/Users/me/.claude-work claude")
        expect(AgentLaunch.command(for: work, skipPermissions: true, kit: kit, defaultClaudeJSON: none)
               == "CLAUDE_CONFIG_DIR=/Users/me/.claude-work claude --dangerously-skip-permissions")
        expect(AgentLaunch.command(for: AgentAccount(dir: "/Users/me/.claude", name: "D", isDefault: true), skipPermissions: false, kit: kit, defaultClaudeJSON: none) == "claude")
        var codex = AgentAccount(dir: "/Users/me/.codex-2", name: "C", isDefault: false)
        codex.provider = .codex
        expect(AgentLaunch.command(for: codex, skipPermissions: true, kit: kit) == "CODEX_HOME='/Users/me/.codex-2' codex --dangerously-bypass-approvals-and-sandbox")
        let odd = AgentAccount(dir: "/tmp/it's", name: "x", isDefault: false)
        expect(AgentLaunch.command(for: odd, skipPermissions: false, kit: kit, defaultClaudeJSON: none) == "CLAUDE_CONFIG_DIR='/tmp/it'\\''s' claude")
    }),
    ("an account with no login, or out for over a day, is left out; a short pause is not", {
        let usage = AgentUsageController.shared
        usage.states["/x/none"] = .noLogin
        usage.states["/x/old"] = .expired
        usage.expiredSince["/x/old"] = Date().addingTimeInterval(-3 * 86_400)
        usage.states["/x/pause"] = .expired
        usage.expiredSince["/x/pause"] = Date().addingTimeInterval(-3600)
        expect(usage.isStale("/x/none") && usage.isStale("/x/old") && !usage.isStale("/x/pause") && !usage.isStale("/x/unread"))
    }),
]
