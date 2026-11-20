import Checks
import Foundation
import Strings
@testable import Agents

/// Plan 33 E: the rules of switching a session's account.
@MainActor let switchChecks: [(name: String, body: Checks.Body)] = [
    ("an account is at its limit at 100% of its session or week; the other with the most room is offered", {
        func usage(_ session: Double?, _ week: Double?) -> AgentUsage {
            AgentUsage(session: session.map { .init(percent: $0, resets: nil) }, week: week.map { .init(percent: $0, resets: nil) }, sonnetWeek: nil)
        }
        expect(AgentSwitch.atLimit(usage(100, 40)) && AgentSwitch.atLimit(usage(20, 100)), "session or week")
        expect(!AgentSwitch.atLimit(usage(99, 60)) && !AgentSwitch.atLimit(nil), "under it, or no numbers")
        let a = AgentAccount(dir: "/a", name: "bkdg", isDefault: false), b = AgentAccount(dir: "/b", name: "bhband", isDefault: false)
        let c = AgentAccount(dir: "/c", name: "diogo", isDefault: false), d = AgentAccount(dir: "/d", name: "new", isDefault: false)
        let numbers = ["/a": usage(100, 50), "/b": usage(30, 70), "/c": usage(10, 20)]
        let next = AgentSwitch.roomiest([a, b, c, d], except: "/a") { numbers[$0.dir] }
        expect(next?.account.dir == "/c" && next?.used == 20, "the most room: \(String(describing: next))")
        let unknownOnly = AgentSwitch.roomiest([a, d], except: "/a") { numbers[$0.dir] }
        expect(unknownOnly?.account.dir == "/d" && unknownOnly?.used == nil, "one with no numbers still serves")
        let full = AgentSwitch.roomiest([a, b], except: "/a") { _ in usage(100, 100) }
        expect(full == nil, "every other at its limit: none")
        expect(AgentSwitch.usedText(32) == "32% used" || AgentSwitch.usedText(32) == "32% usado")
        expect(AgentSwitch.usedText(nil).isEmpty)
    }),
    ("the switch list's line: session, week, when it comes back once half used, and the folder", {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let account = AgentAccount(dir: home + "/.claude-bkdg", name: "fba. + BKDG", isDefault: false)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let low = AgentUsage(session: .init(percent: 15, resets: now.addingTimeInterval(3600)), week: .init(percent: 22, resets: nil), sonnetWeek: nil)
        let line = AgentSwitch.detail(account, usage: low, now: now)
        expect(line.contains("15%") && line.contains("22%") && line.hasSuffix("~/.claude-bkdg") && !line.contains("16"), line)
        let high = AgentUsage(session: .init(percent: 80, resets: now.addingTimeInterval(3600)), week: nil, sonnetWeek: nil)
        expect(AgentSwitch.detail(account, usage: high, now: now).contains(T("back at", "volta às")), "half used: when it comes back")
        let managed = AgentAccount(dir: home + "/Library/Application Support/Cadex/accounts/bkdg", name: "fba. + BKDG", isDefault: false)
        let empty = AgentSwitch.detail(managed, usage: AgentUsage(session: nil, week: nil, sonnetWeek: nil), now: now)
        expect(empty.contains(T("after a session", "depois de uma sessão")) && empty.hasSuffix(T("Cadex account", "conta do Cadex")), empty)
    }),
    ("the briefing of a new conversation: the owner's last requests and the last answer from the file, not Claude Code's own turns", {
        let file = NSTemporaryDirectory() + "cadex-brief-\(UUID().uuidString).jsonl"
        defer { try? FileManager.default.removeItem(atPath: file) }
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"first ask"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"old answer"}]}}"#,
            #"{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued…"}}"#,
            #"{"type":"user","message":{"role":"user","content":"<command-name>/compact</command-name>"}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"fix the briefing"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"a.swift"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Done: the briefing comes from the file."}]}}"#,
        ]
        try lines.joined(separator: "\n").write(toFile: file, atomically: true, encoding: .utf8)
        guard let stop = AgentBriefing.stop(transcript: file) else { return expect(false, "no stop") }
        expect(stop.prompts == ["first ask", "fix the briefing"] && stop.reply == "Done: the briefing comes from the file.", "\(stop)")
        let text = AgentBriefing.text(stop, transcript: file, fromAccount: "bkdg")
        expect(text.contains("(bkdg)") && text.contains(file) && text.contains("2. fix the briefing") && text.contains("Your last answer:"), text)
        expect(AgentBriefing.stop(transcript: file + ".gone") == nil, "no file, no briefing")
    }),
]
