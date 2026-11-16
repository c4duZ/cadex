import Checks
import Foundation
@testable import Orchestration

// The state on disk, races, automations and the controller's "off costs
// nothing" (plan 24 phase B).

let storeTests: [(name: String, body: Checks.Body)] = [
    ("the file: 0600 in a 0700 folder, kept across opens, read by parent", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        let path = dir + "/orchestration/state.sqlite"
        do {
            let book = RunBook(store: try OrchestrationStore(path: path))
            let run = try book.newRun(name: "r", repository: "/repo", caps: Caps(budgetUsd: 2, maxMinutes: 30))
            try book.addTask(run: run.id, title: "a", spec: "x")
            let other = try book.newRun(name: "s", repository: "/repo", caps: Caps(budgetUsd: 2, maxMinutes: 30))
            try book.addTask(run: other.id, title: "b", spec: "y")
        }
        let mode = { (p: String) in (try? fm.attributesOfItem(atPath: p)[.posixPermissions] as? Int) ?? -1 }
        expect(mode(path) == 0o600 && mode(dir + "/orchestration") == 0o700, "\(String(mode(path), radix: 8))")
        let again = RunBook(store: try OrchestrationStore(path: path))
        let runs: [Run] = try again.store.all(.runs)
        expect(runs.map(\.name) == ["r", "s"])
        expect(try again.tasks(of: runs[0].id).map(\.title) == ["a"], "only the run's own")
    }),
    ("a row that no longer reads is skipped; a failed batch leaves nothing", {
        let store = try OrchestrationStore(path: ":memory:")
        try store.put(.runs, id: "bad", ["name": 1])
        try store.put(.runs, id: "good", Run(id: "good", name: "g", repository: "/r", caps: Caps(budgetUsd: 1, maxMinutes: 1), createdAt: Date()))
        expect((try store.all(.runs) as [Run]).map(\.id) == ["good"])
        struct Boom: Error {}
        do {
            try store.batch {
                try store.put(.tasks, id: "t", parent: "good", ["x": 1])
                throw Boom()
            }
        } catch {}
        expect((try store.get(.tasks, id: "t") as [String: Int]?) == nil, "rolled back")
    }),
    ("races: 2 to maxAgents contenders, numbered from 1; the winner stays, the others discarded", {
        let races = RaceBook(store: try OrchestrationStore(path: ":memory:"))
        let three = [AgentChoice(model: "opus"), AgentChoice(account: "/a/bkdg", model: "haiku"), AgentChoice(machine: "pc")]
        do { _ = try races.newRace(name: "x", prompt: "p", repository: "/r", base: "abc", caps: Caps(budgetUsd: 1, maxMinutes: 1),
                                   agents: [three[0]], worktree: { "w\($0)" }, maxAgents: 6); expect(false, "one is no race") } catch RunError.noSlot(_) {}
        do { _ = try races.newRace(name: "x", prompt: "p", repository: "/r", base: "abc", caps: Caps(budgetUsd: 1, maxMinutes: 1),
                                   agents: three, worktree: { "w\($0)" }, maxAgents: 2); expect(false, "past the cap") } catch RunError.noSlot(2) {}
        let (race, contenders) = try races.newRace(name: "fix-login", prompt: "fix it", repository: "/r", base: "abc",
                                                   caps: Caps(budgetUsd: 3, maxMinutes: 20), agents: three,
                                                   worktree: { "/r.worktrees/fix-login-\($0)" }, maxAgents: 6)
        expect(contenders.map(\.index) == [1, 2, 3] && contenders[1].worktree == "/r.worktrees/fix-login-2")
        try races.update(contenders[0].id, state: .finished, session: SessionLink(kit: "k1", claude: "c1", transcript: "/t.jsonl"))
        let losers = try races.pickWinner(race: race.id, contender: contenders[0].id)
        expect(Set(losers.map(\.id)) == [contenders[1].id, contenders[2].id])
        _ = try races.discard(race: race.id)
        let after = try races.contenders(of: race.id)
        expect(after[0].state == .finished && after[0].session?.transcript == "/t.jsonl")
        expect(after[1].state == .discarded && after[2].state == .discarded)
        expect(try races.races().first?.winner == contenders[0].id)
    }),
    ("automations: born off, toggled, history newest first, a running one known", {
        let book = AutomationBook(store: try OrchestrationStore(path: ":memory:"))
        let auto = Automation(id: "a1", name: "triage", prompt: "look at the issues", recurrence: .weekdays(hour: 9, minute: 0),
                              target: .newWorktree(repository: "/r"), agent: AgentChoice(model: "haiku"), permissionMode: "default",
                              allowedTools: ["Read"], caps: Caps(budgetUsd: 1, maxMinutes: 15))
        try book.save(auto)
        expect(try book.enabled().isEmpty && !auto.useSubscription && auto.missed == .runOnWake)
        try book.setEnabled("a1", true)
        expect(try book.enabled().map(\.id) == ["a1"])
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        try book.record(AutomationRun(id: "r1", automation: "a1", scheduledAt: t0, result: .done))
        try book.record(AutomationRun(id: "r2", automation: "a1", scheduledAt: t0 + 3600, result: .running))
        expect(try book.history(of: "a1").map(\.id) == ["r2", "r1"])
        expect(try book.running("a1")?.id == "r2")
        let saved = try book.automations().first
        expect(saved?.recurrence == .weekdays(hour: 9, minute: 0) && saved?.target == .newWorktree(repository: "/r"))
    }),
    ("the controller: off opens no file; on opens on first use; off again closes; automations need their own switch", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        let controller = OrchestrationController()
        controller.folder = dir + "/orchestration"
        expect(controller.runs() == nil && controller.automations() == nil)
        expect(!fm.fileExists(atPath: controller.statePath) && !controller.isOpen, "nothing on disk with the feature off")
        controller.isEnabled = true
        expect(!fm.fileExists(atPath: controller.statePath), "turning on alone opens nothing")
        expect(controller.runs() != nil && controller.isOpen && fm.fileExists(atPath: controller.statePath))
        expect(controller.automations() == nil, "orchestration.automations is apart")
        controller.automationsEnabled = true
        expect(controller.automations() != nil)
        controller.isEnabled = false
        expect(controller.isOpen, "automations still on")
        controller.automationsEnabled = false
        expect(!controller.isOpen && controller.runs() == nil)
        expect(controller.defaultCaps == Caps(budgetUsd: 5, maxMinutes: 60) && controller.limits.maxAgents == 6 && controller.limits.maxDepth == 2)
        expect(OrchestrationController.sessionEnvironment(dispatch: "d1") == ["CADEX_DISPATCH_ID": "d1"])
    }),
]
