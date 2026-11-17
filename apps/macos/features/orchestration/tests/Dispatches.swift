import Checks
import Foundation
@testable import Orchestration
@testable import SessionKit

// The run with the owner coordinating (plan 24 D1): "Mark Done", the cost
// and the cap, the checks before a dispatch, where it starts, the page's
// rows and the dispatch's command with CADEX_DISPATCH_ID.

let dispatchTests: [(name: String, body: Checks.Body)] = [
    ("mark done: the owner finishes a live try, or the latest one that failed; the chain moves on", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "do a")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "do b", dependsOn: [a.id])
        let first = try f.dispatch(a.id)
        try f.book.fail(first.id, reason: "exited without reporting")
        expect(try f.state(b.id) == .blocked)
        try f.book.retry(task: a.id)
        let second = try f.dispatch(a.id)
        try f.book.fail(second.id, reason: "exited without reporting")
        do { try f.book.markDone(first.id, summary: ""); expect(false, "an older try finished the task") } catch RunError.alreadyEnded(_) {}
        expect(try f.book.markDone(second.id, summary: "looked fine") == [b.id])
        expect(try f.state(a.id) == .done && f.state(b.id) == .ready)
        let db = try f.dispatch(b.id)
        try f.book.markDone(db.id, summary: "")
        do { try f.book.markDone(db.id, summary: ""); expect(false, "twice") } catch RunError.alreadyEnded(_) {}
    }),
    ("the cost is recorded only when it changes, and the session keeps Claude's id", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let d = try f.dispatch(a.id)
        try f.book.attach(d.id, session: SessionLink(kit: "k1"))
        try f.book.record(d.id, cost: 0.25, claude: "c-1")
        try f.book.record(d.id, cost: nil, claude: nil)
        let read: Dispatch? = try f.book.store.get(.dispatches, id: d.id)
        expect(read?.costUsd == 0.25 && read?.session == SessionLink(kit: "k1", claude: "c-1"), "\(String(describing: read))")
    }),
    ("time with agents working is the union of the tries' spans, not the time since the run was made", {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func d(_ id: String, _ start: Double, _ end: Double?, _ state: DispatchState) -> Dispatch {
            Dispatch(id: id, run: "r", task: id, attempt: 1, agent: AgentChoice(), worktree: "/w", launch: .tab, state: state,
                     startedAt: t0.addingTimeInterval(start), endedAt: end.map { t0.addingTimeInterval($0) }, lastSign: t0)
        }
        let spans = [d("a", 0, 60, .done), d("b", 30, 120, .done), d("c", 600, nil, .working), d("x", 700, nil, .stopped)]
        expect(RunGraph.busySeconds(spans, now: t0.addingTimeInterval(660)) == 180, "\(RunGraph.busySeconds(spans, now: t0.addingTimeInterval(660)))")
        expect(!RunGraph.overCap(Caps(budgetUsd: 1, maxMinutes: 3), dispatches: spans, now: t0.addingTimeInterval(660)))
        expect(RunGraph.overCap(Caps(budgetUsd: 1, maxMinutes: 3), dispatches: spans, now: t0.addingTimeInterval(661)))
    }),
    ("past the run's cap every live try stops, the run says why and takes no new one", {
        let f = try Fixture()
        let run = try f.book.newRun(name: "r", repository: "/repo", caps: Caps(budgetUsd: 0.10, maxMinutes: 60))
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "")
        let da = try f.dispatch(a.id)
        _ = try f.dispatch(b.id)
        try f.book.record(da.id, cost: 0.08, claude: nil)
        expect(try f.book.enforceCap(run: run.id).isEmpty, "under the cap")
        try f.book.record(da.id, cost: 0.11, claude: nil)
        expect(try f.book.enforceCap(run: run.id).count == 2)
        let stopped = try f.book.run(run.id)
        expect(stopped?.stopped == true && stopped?.reason == "hit the cap")
        expect(try f.book.tasks(of: run.id).allSatisfy { $0.state == .ready && $0.reason == "hit the cap" })
        expect(try f.book.enforceCap(run: run.id).isEmpty, "once")
    }),
    ("the checks before a dispatch, in order: off, stopped, not ready, empty, too big, trust, then no slot (the app queues)", {
        let task = RunTask(id: "t", run: "r", title: "t", spec: "fix it", dependsOn: [], gate: .none, state: .ready, depth: 0)
        var run = Run(id: "r", name: "r", repository: "/repo", caps: Caps(budgetUsd: 1, maxMinutes: 5), createdAt: Date())
        let request = DispatchRequest(task: "t", agent: AgentChoice(account: "/a/bkdg"), base: "main")
        func check(_ task: RunTask, all: [Dispatch] = [], trusts: Bool = true) -> DispatchRefusal? {
            RunLaunch.check(request, run: run, task: task, all: all, enabled: true, maxAgents: 1) { _ in trusts }
        }
        expect(RunLaunch.check(request, run: run, task: task, all: [], enabled: false, maxAgents: 1) { _ in true } == .off)
        expect(check(task) == nil)
        var other = task
        other.state = .pending
        expect(check(other) == .notReady(.pending))
        other = task
        other.spec = "  "
        expect(check(other) == nil && RunLaunch.prompt(other) == "t", "the title when there is no spec")
        other.title = " "
        expect(check(other) == .emptySpec)
        other.spec = String(repeating: "x", count: PromptFiles.maxBytes + 1)
        expect(check(other) == .specTooBig(PromptFiles.maxBytes + 1))
        let busy = Dispatch(id: "d", run: "x", task: "x", attempt: 1, agent: AgentChoice(), worktree: "/w", launch: .tab, state: .working,
                            startedAt: Date(), lastSign: Date())
        expect(check(task, all: [busy]) == .noSlot(1))
        expect(check(task, trusts: false) == .notTrusted("bkdg", dir: "/a/bkdg"))
        run.stopped = true
        expect(check(task) == .runStopped)
    }),
    ("where a dispatch starts: the latest done dependency's branch first, then the repository's", {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        func d(_ task: String, _ folder: String, _ state: DispatchState, ended: Double) -> Dispatch {
            Dispatch(id: folder, run: "r", task: task, attempt: 1, agent: AgentChoice(), worktree: "/repo.worktrees/" + folder, launch: .tab,
                     state: state, startedAt: t0, endedAt: t0.addingTimeInterval(ended), lastSign: t0)
        }
        let task = RunTask(id: "c", run: "r", title: "c", spec: "", dependsOn: ["a", "b"], gate: .none, state: .ready, depth: 0)
        let all = [d("a", "r-a", .done, ended: 10), d("b", "r-b", .failed, ended: 20), d("b", "r-b-2", .done, ended: 30), d("z", "r-z", .done, ended: 40)]
        expect(RunLaunch.bases(for: task, dispatches: all, repositoryBranch: "main") == ["r-b-2", "r-a", "main"])
        expect(RunLaunch.bases(for: task, dispatches: [], repositoryBranch: "main") == ["main"])
        let run = Run(id: "r", name: "login", repository: "/repo", caps: Caps(budgetUsd: 1, maxMinutes: 5), createdAt: t0)
        expect(RunLaunch.taskName(run: run, task: task) == "login-c")
    }),
    ("the page: tasks after their dependencies, the latest try, and only the actions that fit", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "", dependsOn: [a.id])
        let first = try f.dispatch(a.id)
        try f.book.fail(first.id, reason: "exited without reporting")
        try f.book.retry(task: a.id)
        let second = try f.book.dispatch(task: a.id, agent: AgentChoice(model: "haiku"), worktree: "/w/a-2", session: nil, maxAgents: 6)
        try f.book.record(second.id, cost: 0.0123, claude: nil)
        let tasks = try f.book.tasks(of: run.id).reversed()
        let rows = RunRows.make(run: run, tasks: Array(tasks), dispatches: try f.book.dispatches(of: run.id),
                                live: { _ in ContenderLive(state: .finished, since: f.clock.addingTimeInterval(-65)) }, now: f.clock)
        expect(rows.map(\.task) == [a.id, b.id], "order")
        expect(rows[0].dispatch == "try 2 · haiku · ~/.claude · Finished: Mark Done? · 1m 5s · US$ 0.0123", rows[0].dispatch)
        expect(rows[0].dispatchID == second.id && rows[0].canStop && rows[0].canMarkDone && !rows[0].canDispatch && !rows[0].canRetry)
        expect(rows[1].after == "after: a" && rows[1].state == "Pending" && rows[1].dispatch.isEmpty && !rows[1].canDispatch)
        try f.book.fail(second.id, reason: "exited without reporting")
        let failed = RunRows.make(run: run, tasks: try f.book.tasks(of: run.id), dispatches: try f.book.dispatches(of: run.id), live: { _ in nil }, now: f.clock)
        expect(failed[0].canRetry && failed[0].canMarkDone && !failed[0].canStop && failed[0].reason == "exited without reporting")
        expect(failed[1].state == "Blocked")
        expect(RunRows.summary(run: run, dispatches: try f.book.dispatches(of: run.id), now: f.clock).hasPrefix("US$ 0.0123 of 5.00 · "))
    }),
    ("a dispatch's command: the spec in a file, CADEX_DISPATCH_ID only in that session's settings", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit.forTests(folder: dir + "/kit")
        kit.toolsPath = "/H/cadex"
        guard case .success(let opened) = RaceLaunch.localCommand(kit: kit, agent: AgentChoice(), cwd: "/w", prompt: "spec $(id)", skipPermissions: false,
                                                                   sessionEnvironment: OrchestrationController.sessionEnvironment(dispatch: "dispatch-xyz"),
                                                                   promptFolder: dir + "/prompts")
        else { return expect(false, "refused") }
        expect(!opened.command.contains("dispatch-xyz") && !opened.command.contains("$(id)"), opened.command)
        let settings = (try? fm.contentsOfDirectory(atPath: dir + "/kit")) ?? []
        let texts = settings.compactMap { fm.contents(atPath: dir + "/kit/" + $0) }.map { String(decoding: $0, as: UTF8.self) }
        expect(texts.contains { $0.contains("CADEX_DISPATCH_ID") && $0.contains("dispatch-xyz") }, "\(settings)")
    }),
]
