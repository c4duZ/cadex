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
]
