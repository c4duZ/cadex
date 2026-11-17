import Checks
import Foundation
@testable import Orchestration

// The rest of D1 (plan 24): the queue at orchestration.maxAgents, the
// dependencies changed after the fact, errors by title, and the page's
// graph, history and queued line.

let queueTests: [(name: String, body: Checks.Body)] = [
    ("the queue: oldest first, only ready tasks of runs going; a dispatch or a stopped run takes it out", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "")
        let c = try f.book.addTask(run: run.id, title: "c", spec: "", dependsOn: [a.id])
        do { try f.book.queue(DispatchRequest(task: c.id, agent: AgentChoice(), base: "")); expect(false, "a pending one queued") } catch RunError.notReady(_, .pending) {}
        try f.book.queue(DispatchRequest(task: b.id, agent: AgentChoice(model: "haiku"), base: "main", reuseShell: 42))
        f.clock = f.clock.addingTimeInterval(1)
        try f.book.queue(DispatchRequest(task: a.id, agent: AgentChoice(), base: ""))
        expect(try f.book.waiting().map(\.task) == [b.id, a.id], "oldest first")
        expect(try f.book.waiting().first == DispatchRequest(task: b.id, agent: AgentChoice(model: "haiku"), base: "main", reuseShell: 42))
        _ = try f.dispatch(b.id)
        expect(try f.book.waiting().map(\.task) == [a.id], "dispatched leaves the queue")
        try f.book.unqueue(task: a.id)
        expect(try f.book.waiting().isEmpty)
        try f.book.queue(DispatchRequest(task: a.id, agent: AgentChoice(), base: ""))
        try f.book.stopRun(run.id)
        expect(try f.book.waiting().isEmpty && f.book.tasks(of: run.id).allSatisfy { $0.queued == nil }, "a stopped run waits for nothing")
    }),
    ("the slot is shared with the races' agents", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "")
        _ = try f.dispatch(a.id, max: 3)
        do {
            _ = try f.book.dispatch(task: b.id, agent: AgentChoice(), worktree: "/w", session: nil, maxAgents: 3, othersLive: 2)
            expect(false, "past the cap with two race agents")
        } catch RunError.noSlot(3) {}
        let task: RunTask? = try f.book.store.get(.tasks, id: b.id)
        let request = DispatchRequest(task: b.id, agent: AgentChoice(), base: "")
        expect(RunLaunch.check(request, run: run, task: task!, all: try f.book.dispatches(of: run.id), othersLive: 2, enabled: true, maxAgents: 3) { _ in true } == .noSlot(3))
        expect(RunLaunch.check(request, run: run, task: task!, all: try f.book.dispatches(of: run.id), othersLive: 1, enabled: true, maxAgents: 3) { _ in true } == nil)
    }),
    ("dependencies changed later: a cycle refused and said by titles; not on a dispatched task", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "design", spec: "")
        let b = try f.book.addTask(run: run.id, title: "build", spec: "", dependsOn: [a.id])
        let c = try f.book.addTask(run: run.id, title: "ship", spec: "")
        try f.book.setDependencies(task: c.id, [b.id])
        expect(try f.state(c.id) == .pending, "now waits for build")
        do { try f.book.setDependencies(task: a.id, [c.id]); expect(false, "cycle") } catch let error as RunError {
            let titles = Dictionary(try f.book.tasks(of: run.id).map { ($0.id, $0.title) }, uniquingKeysWith: { x, _ in x })
            expect(error.message(titles: titles) == "That would close a cycle: design → ship → build → design", error.message(titles: titles))
        }
        _ = try f.dispatch(a.id)
        do { try f.book.setDependencies(task: a.id, []); expect(false, "dispatched") } catch RunError.notReady(_, .dispatched) {}
    }),
    ("the page: the graph's levels, earlier tries with their reasons, and a queued task's line and actions", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "", dependsOn: [a.id])
        let c = try f.book.addTask(run: run.id, title: "c", spec: "", dependsOn: [a.id, b.id])
        let d = try f.book.addTask(run: run.id, title: "d", spec: "")
        let first = try f.dispatch(a.id)
        try f.book.stop(first.id)
        try f.book.queue(DispatchRequest(task: d.id, agent: AgentChoice(), base: ""))
        let rows = RunRows.make(run: run, tasks: try f.book.tasks(of: run.id), dispatches: try f.book.dispatches(of: run.id), live: { _ in nil },
                                now: f.clock, maxAgents: 6, liveAgents: 6)
        let byTask = Dictionary(rows.map { ($0.task, $0) }, uniquingKeysWith: { x, _ in x })
        expect(byTask[a.id]?.level == 0 && byTask[b.id]?.level == 1 && byTask[c.id]?.level == 2 && byTask[d.id]?.level == 0)
        expect(byTask[a.id]?.dispatch.contains("Stopped") == true && byTask[a.id]?.canDispatch == true && byTask[a.id]?.canGoToTerminal == false)
        let queued = byTask[d.id]!
        expect(queued.isQueued && queued.dispatch == "waiting for a free slot (6 of 6)" && queued.canStop && !queued.canDispatch && !queued.canEditDependencies)
        expect(byTask[b.id]?.canEditDependencies == true)
        _ = try f.dispatch(a.id)
        let again = RunRows.make(run: run, tasks: try f.book.tasks(of: run.id), dispatches: try f.book.dispatches(of: run.id), live: { _ in nil }, now: f.clock)
        let row = again.first { $0.task == a.id }!
        expect(row.history.count == 1 && row.history[0].hasPrefix("try 1") && row.history[0].hasSuffix("— stopped"), "\(row.history)")
        expect(row.dispatch.hasPrefix("try 2") && !row.canEditDependencies)
    }),
]
