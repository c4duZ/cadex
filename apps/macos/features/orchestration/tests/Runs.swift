import Checks
import Foundation
@testable import Orchestration

// A run's rules on a fresh store each (plan 24 phase B): dependencies,
// cycles, failures, gates, spawn depth, stopping, orphans, reports, caps
// and the inbox.

let runTests: [(name: String, body: Checks.Body)] = [
    ("dependencies: a chain becomes ready one done at a time", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "do a")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "do b", dependsOn: [a.id])
        let c = try f.book.addTask(run: run.id, title: "c", spec: "do c", dependsOn: [b.id])
        expect(a.state == .ready && b.state == .pending && c.state == .pending, "\(a.state) \(b.state) \(c.state)")
        let da = try f.dispatch(a.id)
        expect(try f.state(a.id) == .dispatched)
        expect(try f.book.reportDone(da.id, summary: "a done") == [b.id])
        expect(try f.state(a.id) == .done && f.state(b.id) == .ready && f.state(c.id) == .pending)
        let db = try f.dispatch(b.id)
        try f.book.reportDone(db.id, summary: "b done")
        expect(try f.state(c.id) == .ready)
    }),
    ("a dependency cycle is refused with the cycle, and so is an unknown task", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "", dependsOn: [a.id])
        let c = try f.book.addTask(run: run.id, title: "c", spec: "", dependsOn: [b.id])
        do { try f.book.setDependencies(task: a.id, [c.id]); expect(false, "a cycle went in") }
        catch RunError.cycle(let path) { expect(path == [a.id, c.id, b.id, a.id], "\(path)") }
        do { try f.book.setDependencies(task: a.id, [a.id]); expect(false, "self") } catch RunError.cycle(_) {}
        do { _ = try f.book.addTask(run: run.id, title: "x", spec: "", dependsOn: ["nope"]); expect(false) } catch RunError.unknown("nope") {}
        expect(try f.book.tasks(of: run.id).count == 3 && f.state(a.id) == .ready, "nothing changed")
        expect(RunGraph.cycle(adding: [b.id], to: "new", in: try f.book.tasks(of: run.id)) == nil, "a new task never closes one")
    }),
    ("a failure blocks what depends on it, down the chain; a retry unblocks", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "", dependsOn: [a.id])
        let c = try f.book.addTask(run: run.id, title: "c", spec: "", dependsOn: [b.id])
        let d = try f.dispatch(a.id)
        try f.book.fail(d.id, reason: "the agent said no")
        expect(try f.state(a.id) == .failed && f.state(b.id) == .blocked && f.state(c.id) == .blocked)
        try f.book.retry(task: a.id)
        expect(try f.state(a.id) == .ready && f.state(b.id) == .pending && f.state(c.id) == .pending)
        let second = try f.dispatch(a.id)
        expect(second.attempt == 2, "the first try kept: \(second.attempt)")
        expect((try f.book.dispatches(of: run.id)).count == 2)
    }),
    ("a gate holds a ready task until approved; rejected, it is blocked", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let gated = try f.book.addTask(run: run.id, title: "g", spec: "", dependsOn: [a.id], gate: true)
        try f.book.reportDone(try f.dispatch(a.id).id, summary: "")
        expect(try f.state(gated.id) == .pending, "waits for the owner")
        do { _ = try f.dispatch(gated.id); expect(false) } catch RunError.notReady(_, .pending) {}
        try f.book.approveGate(task: gated.id)
        expect(try f.state(gated.id) == .ready)
        let other = try f.book.addTask(run: run.id, title: "h", spec: "", gate: true)
        try f.book.rejectGate(task: other.id, reason: "not now")
        expect(try f.state(other.id) == .blocked)
        do { try f.book.approveGate(task: a.id); expect(false) } catch RunError.noGate(_) {}
    }),
    ("spawn: one deeper each time, refused past orchestration.maxDepth", {
        let f = try Fixture()
        let run = try f.run()
        let root = try f.book.addTask(run: run.id, title: "root", spec: "")
        let d0 = try f.dispatch(root.id)
        let child = try f.book.spawn(from: d0.id, title: "child", spec: "$(rm -rf ~) `x`\nline", maxDepth: 2)
        expect(child.depth == 1 && child.spawnedBy == d0.id && child.state == .ready)
        expect(child.spec == "$(rm -rf ~) `x`\nline", "kept as text")
        let d1 = try f.dispatch(child.id)
        let grand = try f.book.spawn(from: d1.id, title: "grand", spec: "", maxDepth: 2)
        let d2 = try f.dispatch(grand.id)
        do { _ = try f.book.spawn(from: d2.id, title: "too deep", spec: "", maxDepth: 2); expect(false) } catch RunError.tooDeep(2) {}
        try f.book.reportDone(d2.id, summary: "")
        do { _ = try f.book.spawn(from: d2.id, title: "late", spec: "", maxDepth: 5); expect(false) } catch RunError.alreadyEnded(_) {}
    }),
    ("stopping a parent stops its children and theirs; their tasks go back to ready", {
        let f = try Fixture()
        let run = try f.run()
        let root = try f.book.addTask(run: run.id, title: "root", spec: "")
        let other = try f.book.addTask(run: run.id, title: "other", spec: "")
        let d0 = try f.dispatch(root.id)
        let dOther = try f.dispatch(other.id)
        let d1 = try f.dispatch(try f.book.spawn(from: d0.id, title: "c", spec: "", maxDepth: 2).id)
        let d2 = try f.dispatch(try f.book.spawn(from: d1.id, title: "g", spec: "", maxDepth: 2).id)
        let stopped = try f.book.stop(d0.id).map(\.id)
        expect(Set(stopped) == [d0.id, d1.id, d2.id], "\(stopped)")
        expect(try f.state(root.id) == .ready, "back to ready")
        let all = try f.book.dispatches(of: run.id)
        expect(all.first { $0.id == dOther.id }?.state == .starting, "a sibling keeps running")
        expect(all.filter { $0.state == .stopped }.allSatisfy { $0.reason == "stopped" && $0.endedAt != nil })
    }),
    ("orphans: a live dispatch whose session is gone fails, 'exited without reporting'; its dependents block", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "", dependsOn: [a.id])
        let alive = try f.book.addTask(run: run.id, title: "c", spec: "")
        let gone = try f.dispatch(a.id, session: "kit-a")
        _ = try f.dispatch(alive.id, session: "kit-c")
        expect(try f.book.reapOrphans { $0 == "kit-c" } == [gone.id])
        expect(try f.state(a.id) == .failed && f.state(b.id) == .blocked && f.state(alive.id) == .dispatched)
        let line: RunTask? = try f.book.store.get(.tasks, id: a.id)
        expect(line?.reason == "exited without reporting")
        expect(try f.book.reapOrphans { _ in false }.count == 1, "only the live one is left to reap")
    }),
    ("reports: a second done is refused, a heartbeat moves the sign, stalled after the minutes", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.book.addTask(run: run.id, title: "a", spec: "")
        let b = try f.book.addTask(run: run.id, title: "b", spec: "")
        let da = try f.dispatch(a.id)
        let db = try f.dispatch(b.id)
        f.clock += 60
        try f.book.sign(da.id)
        try f.book.sign(db.id)
        f.clock += 9 * 60
        try f.book.sign(da.id)
        f.clock += 60
        expect(RunGraph.stalled(try f.book.dispatches(of: run.id), minutes: 10, now: f.clock) == [db.id])
        try f.book.reportDone(da.id, summary: "ok")
        do { try f.book.reportDone(da.id, summary: "again"); expect(false) } catch RunError.alreadyEnded(_) {}
    }),
    ("caps: no dispatch past orchestration.maxAgents live agents, nor in a stopped run", {
        let f = try Fixture()
        let run = try f.run()
        let tasks = try (0..<3).map { try f.book.addTask(run: run.id, title: "t\($0)", spec: "") }
        _ = try f.dispatch(tasks[0].id, max: 2)
        _ = try f.dispatch(tasks[1].id, max: 2)
        do { _ = try f.dispatch(tasks[2].id, max: 2); expect(false) } catch RunError.noSlot(2) {}
        expect(try f.state(tasks[2].id) == .ready, "waits for a slot")
        let stopped = try f.book.stopRun(run.id)
        expect(stopped.count == 2)
        do { _ = try f.dispatch(tasks[2].id); expect(false) } catch RunError.stopped(_) {}
    }),
    ("inbox: a question goes to the owner, the answer back to the asker; messages stay in the run", {
        let f = try Fixture()
        let run = try f.run()
        let a = try f.dispatch(try f.book.addTask(run: run.id, title: "a", spec: "").id)
        let b = try f.dispatch(try f.book.addTask(run: run.id, title: "b", spec: "").id)
        let question = try f.book.ask(from: a.id, question: "blue or green?")
        expect(question.to == "owner")
        expect(try f.book.unread(run: run.id, to: "owner", markRead: true).map(\.text) == ["blue or green?"])
        try f.book.answer(question.id, text: "green")
        try f.book.send(from: b.id, to: a.id, text: "the API is in api/")
        let inbox = try f.book.inbox(a.id)
        expect(inbox.map(\.text) == ["green", "the API is in api/"] && inbox[0].answers == question.id, "\(inbox)")
        expect(try f.book.inbox(a.id).isEmpty, "read once")
        let otherRun = try f.run()
        let c = try f.dispatch(try f.book.addTask(run: otherRun.id, title: "c", spec: "").id)
        do { try f.book.send(from: a.id, to: c.id, text: "x"); expect(false) } catch RunError.wrongRun(_) {}
        let coordinated = try f.book.newRun(name: "k", repository: "/r", coordinator: "kit-coord", caps: Caps(budgetUsd: 1, maxMinutes: 1))
        let d = try f.dispatch(try f.book.addTask(run: coordinated.id, title: "d", spec: "").id)
        expect(try f.book.ask(from: d.id, question: "?").to == "coordinator")
    }),
]
