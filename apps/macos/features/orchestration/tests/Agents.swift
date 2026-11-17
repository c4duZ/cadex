import Checks
import Foundation
@testable import Orchestration

// Supervised agents (plan 24 D2): the caller by its session, each command
// of the agent's list, the coordinator, gates, tasks on their own, and what
// the page shows of them.

/// A run with one dispatched task whose session is "k1".
func supervised(_ f: Fixture, coordinator: String? = nil) throws -> (run: Run, task: RunTask, dispatch: Dispatch) {
    let run = try f.book.newRun(name: "r", repository: "/repo", coordinator: coordinator, caps: Caps(budgetUsd: 5, maxMinutes: 60))
    let task = try f.book.addTask(run: run.id, title: "a", spec: "do a")
    let dispatch = try f.dispatch(task.id, session: "k1")
    return (run, task, dispatch)
}

func api(_ f: Fixture, _ id: String, _ args: [String: String], kit: String = "k1", claimed: String? = nil, slot: Bool = true) throws -> RunAgentAPI.Outcome {
    try RunAgentAPI.handle(id, args, caller: try f.book.caller(kitSession: kit, claimed: claimed), book: f.book, maxDepth: 2, hasSlot: slot)
}

let agentTests: [(name: String, body: Checks.Body)] = [
    ("the caller is the dispatch of the token's session; another run's id, or no dispatch, is refused", {
        let f = try Fixture()
        let s = try supervised(f)
        expect(try f.book.caller(kitSession: "k1", claimed: s.dispatch.id) == .dispatch(s.dispatch))
        do { _ = try f.book.caller(kitSession: "k1", claimed: "other-dispatch"); expect(false, "claimed another") } catch RunError.wrongRun("other-dispatch") {}
        do { _ = try f.book.caller(kitSession: "nobody", claimed: nil); expect(false, "no dispatch") } catch RunError.notSupervised {}
        do { _ = try f.book.caller(kitSession: "", claimed: nil); expect(false, "empty") } catch RunError.notSupervised {}
    }),
    ("report-done finishes the task and frees what waited; a second one hears already done", {
        let f = try Fixture()
        let s = try supervised(f)
        let b = try f.book.addTask(run: s.run.id, title: "b", spec: "", dependsOn: [s.task.id])
        expect(try api(f, "orchestration.report-done", ["summary": "did a"]).text == "done; 1 task(s) can start now")
        expect(try f.state(s.task.id) == .done && f.state(b.id) == .ready)
        expect((try f.book.store.get(.dispatches, id: s.dispatch.id) as Dispatch?)?.summary == "did a")
        let again = try api(f, "orchestration.report-done", ["summary": "x"])
        expect(again.text == "already done" && !again.changed)
        do { _ = try api(f, "orchestration.report-done", [:]); expect(false, "no summary") } catch RunError.missing("summary") {}
    }),
    ("heartbeat: a sign of life with its note; stalled after the minutes without one, cleared by the next", {
        let f = try Fixture()
        let s = try supervised(f)
        _ = try api(f, "orchestration.report-heartbeat", ["note": "writing tests"])
        f.clock = f.clock.addingTimeInterval(11 * 60)
        let all = try f.book.dispatches(of: s.run.id)
        expect(RunGraph.stalled(all, minutes: 10, now: f.clock) == [s.dispatch.id])
        let rows = RunRows.make(run: s.run, tasks: try f.book.tasks(of: s.run.id), dispatches: all, live: { _ in nil }, now: f.clock, heartbeatMinutes: 10)
        expect(rows[0].isStalled && rows[0].dispatch.contains("“writing tests”") && rows[0].dispatch.hasSuffix("stalled?"), rows[0].dispatch)
        _ = try api(f, "orchestration.report-heartbeat", [:])
        expect(RunGraph.stalled(try f.book.dispatches(of: s.run.id), minutes: 10, now: f.clock).isEmpty)
    }),
    ("ask goes to the owner and waits; the owner's answer reaches the agent's inbox and clears the wait", {
        let f = try Fixture()
        let s = try supervised(f)
        let asked = try api(f, "orchestration.ask", ["question": "which db?"])
        expect(asked.ownerQuestion?.to == "owner" && asked.text.contains("orchestration.inbox"))
        expect((try f.book.store.get(.dispatches, id: s.dispatch.id) as Dispatch?)?.waitingFor == asked.ownerQuestion?.id)
        let inbox = RunRows.inbox(try f.book.store.all(.messages, parent: s.run.id), tasks: try f.book.tasks(of: s.run.id), dispatches: try f.book.dispatches(of: s.run.id))
        expect(inbox.count == 1 && inbox[0].canAnswer && inbox[0].text == "Question from a to you: which db?", "\(inbox)")
        try f.book.answer(asked.ownerQuestion!.id, text: "sqlite")
        expect((try f.book.store.get(.dispatches, id: s.dispatch.id) as Dispatch?)?.waitingFor == nil)
        expect(try api(f, "orchestration.inbox", [:]).text == "[answer to \(asked.ownerQuestion!.id) from owner] sqlite")
        expect(try api(f, "orchestration.inbox", [:]).text == "nothing new")
        let after = RunRows.inbox(try f.book.store.all(.messages, parent: s.run.id), tasks: [], dispatches: [])
        expect(!after.contains { $0.canAnswer }, "answered")
    }),
    ("send-message only within the run; the coordinator answers a question and hears how tasks end", {
        let f = try Fixture()
        let s = try supervised(f, coordinator: "kc")
        let other = try f.book.newRun(name: "o", repository: "/repo", caps: Caps(budgetUsd: 5, maxMinutes: 60))
        let elsewhere = try f.dispatch(try f.book.addTask(run: other.id, title: "x", spec: "").id, session: "k9")
        do { _ = try api(f, "orchestration.send-message", ["to": elsewhere.id, "text": "hi"]); expect(false, "other run") } catch RunError.wrongRun(_) {}
        let asked = try api(f, "orchestration.ask", ["question": "ok?"])
        expect(asked.ownerQuestion == nil && asked.text.contains("coordinator"))
        let lines = try api(f, "orchestration.inbox", [:], kit: "kc").text
        expect(lines.hasPrefix("[question ") && lines.contains("ok?"), lines)
        let qid = String(lines.dropFirst("[question ".count).prefix { $0 != " " })
        _ = try api(f, "orchestration.send-message", ["to": s.dispatch.id, "answers": qid, "text": "yes"], kit: "kc")
        expect(try api(f, "orchestration.inbox", [:]).text.hasSuffix("from coordinator] yes"))
        _ = try api(f, "orchestration.report-done", ["summary": "fine"])
        expect(try api(f, "orchestration.inbox", [:], kit: "kc").text.contains("a (task \(s.task.id)) done: fine"))
        do { _ = try api(f, "orchestration.report-done", ["summary": "x"], kit: "kc"); expect(false, "coordinator reporting") } catch RunError.notYours(_) {}
        do { _ = try api(f, "orchestration.retry", ["task": s.task.id]); expect(false, "an agent retrying") } catch RunError.notYours(_) {}
    }),
    ("spawn: one deeper and refused at maxDepth, after= by title, gate, the spawner's agent; stopping the parent stops the child", {
        let f = try Fixture()
        let run = try f.book.newRun(name: "r", repository: "/repo", caps: Caps(budgetUsd: 5, maxMinutes: 60))
        let root = try f.book.addTask(run: run.id, title: "root", spec: "")
        _ = try f.book.dispatch(task: root.id, agent: AgentChoice(model: "haiku"), worktree: "/w", session: SessionLink(kit: "k1"), maxAgents: 6)
        let out = try api(f, "orchestration.spawn", ["title": "child", "spec": "do \"it\" $(x)"])
        let child = try f.book.tasks(of: run.id).first { $0.title == "child" }!
        expect(out.text.contains(child.id) && child.depth == 1 && child.auto == AgentChoice(model: "haiku") && child.spec == "do \"it\" $(x)")
        let gated = try api(f, "orchestration.spawn", ["title": "g", "spec": "s", "after": "child", "gate": "yes"])
        let g = try f.book.tasks(of: run.id).first { $0.title == "g" }!
        expect(g.dependsOn == [child.id] && g.gate == .waiting && gated.text.contains("approves its gate"))
        do { _ = try api(f, "orchestration.spawn", ["title": "n", "spec": "s"], slot: false); expect(false, "no slot") } catch RunError.noSlot(_) {}
        let dc = try f.book.dispatch(task: child.id, agent: child.auto!, worktree: "/w2", session: SessionLink(kit: "k2"), maxAgents: 6)
        _ = try api(f, "orchestration.spawn", ["title": "grandchild", "spec": "s"], kit: "k2")
        do { _ = try api(f, "orchestration.spawn", ["title": "too deep", "spec": "s"], kit: "k2", slot: true)
             let gc = try f.book.tasks(of: run.id).first { $0.title == "grandchild" }!
             _ = try f.book.dispatch(task: gc.id, agent: AgentChoice(), worktree: "/w3", session: SessionLink(kit: "k3"), maxAgents: 6)
             _ = try api(f, "orchestration.spawn", ["title": "x", "spec": "s"], kit: "k3")
             expect(false, "depth 3 spawned")
        } catch RunError.tooDeep(2) {}
        let parent = try f.book.dispatches(of: run.id).first { $0.session?.kit == "k1" }!
        let stopped = try f.book.stop(parent.id)
        expect(Set(stopped.map(\.id)).isSuperset(of: [parent.id, dc.id]), "the child stops with its parent")
        expect(try !f.book.readyOnTheirOwn().contains { $0.task.id == child.id }, "a stopped task does not start again on its own")
    }),
    ("the coordinator spawns at the top as the run's agent; ready tasks go on their own; a gate waits for the owner", {
        let f = try Fixture()
        let run = try f.book.newRun(name: "r", repository: "/repo", coordinator: "kc", caps: Caps(budgetUsd: 5, maxMinutes: 60))
        do { _ = try api(f, "orchestration.spawn", ["title": "a", "spec": "s"], kit: "kc"); expect(false, "no agent") } catch RunError.notYours(_) {}
        try f.book.configure(run: run.id, autoAgent: AgentChoice(model: "haiku"), goal: "build it")
        _ = try api(f, "orchestration.spawn", ["title": "a", "spec": "s"], kit: "kc")
        _ = try api(f, "orchestration.spawn", ["title": "b", "spec": "s", "after": "a", "gate": "yes"], kit: "kc")
        expect(try f.book.readyOnTheirOwn().map(\.task.title) == ["a"])
        let a = try f.book.tasks(of: run.id).first { $0.title == "a" }!
        expect(a.depth == 0 && a.spawnedBy == nil)
        try f.book.markDone(try f.dispatch(a.id).id, summary: "a's summary")
        let rows = RunRows.make(run: run, tasks: try f.book.tasks(of: run.id), dispatches: try f.book.dispatches(of: run.id), live: { _ in nil }, now: f.clock)
        let b = rows.first { $0.title == "b" }!
        expect(b.gate == "Gate: waiting for your approval" && b.delivered == ["a: a's summary"] && b.canDecideGate && !b.canDispatch, "\(b)")
        expect(try f.book.readyOnTheirOwn().isEmpty, "gated")
        try f.book.approveGate(task: b.task)
        expect(try f.book.readyOnTheirOwn().map(\.task.title) == ["b"])
        try f.book.failTask(b.task, reason: "failed to start: no trust")
        expect(try f.state(b.task) == .failed && f.book.readyOnTheirOwn().isEmpty)
        _ = try api(f, "orchestration.retry", ["task": b.task], kit: "kc")
        expect(try f.state(b.task) == .ready)
    }),
    ("add-gate holds a ready task; the owner rejects with the reason; the coordinator's prompt carries the goal", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        try f.book.addGate(task: a.id)
        expect(try f.state(a.id) == .pending)
        try f.book.rejectGate(task: a.id, reason: "not now")
        let row = RunRows.make(run: run, tasks: try f.book.tasks(of: run.id), dispatches: [], live: { _ in nil }, now: f.clock)[0]
        expect(row.state == "Blocked" && row.gate == "Gate: rejected: not now" && !row.canDecideGate, "\(row)")
        let prompt = RunLaunch.coordinatorPrompt(run: run, goal: "ship \"it\"\nfast")
        expect(prompt.contains("cadex run orchestration.spawn") && prompt.hasSuffix("Goal:\nship \"it\"\nfast"), prompt)
    }),
]
