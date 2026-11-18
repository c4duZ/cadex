import Checks
import Foundation
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
]
