import Foundation

/// A run's life on top of the store and RunGraph (docs/spec/orchestration.md,
/// "Execuções", "Agentes supervisionados", "Portões"): adding tasks without
/// cycles, dispatching only ready ones within the caps, the agent's reports,
/// spawning within orchestration.maxDepth, gates, stopping a parent with its
/// children and failing the dispatches whose agent left without a word.
/// Launching the agent is not here: the caller does it and records it.
public final class RunBook {
    public let store: OrchestrationStore
    public var now: () -> Date = Date.init
    public var newId: () -> String = { UUID().uuidString.lowercased() }

    public init(store: OrchestrationStore) { self.store = store }

    // MARK: Runs and tasks

    public func newRun(name: String, repository: String, coordinator: String? = nil, caps: Caps) throws -> Run {
        let run = Run(id: newId(), name: name, repository: repository, coordinator: coordinator, caps: caps, createdAt: now())
        try store.put(.runs, id: run.id, run)
        return run
    }

    public func run(_ id: String) throws -> Run? { try store.get(.runs, id: id) }
    public func tasks(of run: String) throws -> [RunTask] { try store.all(.tasks, parent: run) }
    public func dispatches(of run: String) throws -> [Dispatch] { try store.all(.dispatches, parent: run) }

    /// A task of `run`. Refused when a dependency is not a task of the run
    /// or would close a cycle; settled at once (no dependency: ready).
    @discardableResult
    public func addTask(run: String, title: String, spec: String, dependsOn: [String] = [], gate: Bool = false,
                        spawnedBy: String? = nil, depth: Int = 0) throws -> RunTask {
        let id = newId()
        let existing = try tasks(of: run)
        try check(dependsOn, for: id, in: existing)
        let task = RunTask(id: id, run: run, title: title, spec: spec, dependsOn: dependsOn, gate: gate ? .waiting : .none,
                           state: .pending, spawnedBy: spawnedBy, depth: depth)
        try store.put(.tasks, id: id, parent: run, task)
        try settle(run: run)
        return try store.get(.tasks, id: id) ?? task
    }

    public func setDependencies(task id: String, _ deps: [String]) throws {
        guard var task: RunTask = try store.get(.tasks, id: id) else { throw RunError.unknown(id) }
        try check(deps, for: id, in: try tasks(of: task.run))
        task.dependsOn = deps
        try store.put(.tasks, id: id, parent: task.run, task)
        try settle(run: task.run)
    }

    func check(_ deps: [String], for id: String, in tasks: [RunTask]) throws {
        let known = Set(tasks.map(\.id))
        if let missing = deps.first(where: { !known.contains($0) }) { throw RunError.unknown(missing) }
        if let cycle = RunGraph.cycle(adding: deps, to: id, in: tasks) { throw RunError.cycle(cycle) }
    }

    /// Applies RunGraph.settle to the run; returns the tasks that became ready.
    @discardableResult
    public func settle(run: String) throws -> [String] {
        let all = try tasks(of: run)
        let next = RunGraph.settle(all)
        var ready: [String] = []
        try store.batch {
            for var task in all where next[task.id] != task.state {
                task.state = next[task.id] ?? task.state
                if task.state == .ready { ready.append(task.id) }
                try store.put(.tasks, id: task.id, parent: run, task)
            }
        }
        return ready
    }

    // MARK: Gates

    public func approveGate(task id: String) throws { try setGate(id, .approved) }
    public func rejectGate(task id: String, reason: String) throws { try setGate(id, .rejected, reason: reason) }

    func setGate(_ id: String, _ gate: GateState, reason: String? = nil) throws {
        guard var task: RunTask = try store.get(.tasks, id: id), task.gate == .waiting else { throw RunError.noGate(id) }
        task.gate = gate
        task.reason = reason ?? task.reason
        try store.put(.tasks, id: id, parent: task.run, task)
        try settle(run: task.run)
    }

    // MARK: Dispatches

    /// A try of a ready task, recorded before the agent opens. Refused when
    /// the task is not ready, the run was stopped, or orchestration.maxAgents
    /// agents are already live (the caller queues it).
    public func dispatch(task id: String, agent: AgentChoice, worktree: String, session: SessionLink?, maxAgents: Int) throws -> Dispatch {
        guard var task: RunTask = try store.get(.tasks, id: id) else { throw RunError.unknown(id) }
        guard task.state == .ready else { throw RunError.notReady(id, task.state) }
        guard let run = try run(task.run), !run.stopped else { throw RunError.stopped(task.run) }
        let all: [Dispatch] = try store.all(.dispatches)
        guard RunGraph.hasSlot(all, maxAgents: maxAgents) else { throw RunError.noSlot(maxAgents) }
        let attempt = all.filter { $0.task == id }.count + 1
        let dispatch = Dispatch(id: newId(), run: task.run, task: id, attempt: attempt, agent: agent, worktree: worktree,
                                launch: .tab, state: .starting, session: session, startedAt: now(), lastSign: now())
        task.state = .dispatched
        try store.batch {
            try store.put(.dispatches, id: dispatch.id, parent: task.run, dispatch)
            try store.put(.tasks, id: id, parent: task.run, task)
        }
        return dispatch
    }

    /// The owner's or the coordinator's new try of a failed or stopped task.
    public func retry(task id: String) throws {
        guard var task: RunTask = try store.get(.tasks, id: id), task.state == .failed || task.state == .ready else {
            throw RunError.notReady(id, .dispatched)
        }
        task.state = .pending
        try store.put(.tasks, id: id, parent: task.run, task)
        try settle(run: task.run)
    }

    /// A sign of life (heartbeat, report, hook): the agent is working.
    public func sign(_ id: String) throws {
        guard var dispatch: Dispatch = try store.get(.dispatches, id: id), dispatch.state == .starting || dispatch.state == .working else { return }
        dispatch.state = .working
        dispatch.lastSign = now()
        try store.put(.dispatches, id: id, parent: dispatch.run, dispatch)
    }

    /// `report-done`: the dispatch and its task are done; the tasks that
    /// waited for it may become ready (returned).
    @discardableResult
    public func reportDone(_ id: String, summary: String) throws -> [String] {
        guard var dispatch: Dispatch = try store.get(.dispatches, id: id) else { throw RunError.unknown(id) }
        guard dispatch.state == .starting || dispatch.state == .working else { throw RunError.alreadyEnded(id) }
        dispatch.state = .done
        dispatch.summary = summary
        dispatch.endedAt = now()
        try end(dispatch, task: .done, reason: nil)
        return try settle(run: dispatch.run)
    }

    /// The dispatch failed (the agent's error, a cap): its task fails and
    /// whatever depends on it is blocked.
    public func fail(_ id: String, reason: String) throws {
        guard var dispatch: Dispatch = try store.get(.dispatches, id: id), RunGraph.live([dispatch]).count == 1 else { return }
        dispatch.state = .failed
        dispatch.reason = reason
        dispatch.endedAt = now()
        try end(dispatch, task: .failed, reason: reason)
        try settle(run: dispatch.run)
    }

    func end(_ dispatch: Dispatch, task state: TaskState, reason: String?) throws {
        try store.batch {
            try store.put(.dispatches, id: dispatch.id, parent: dispatch.run, dispatch)
            if var task: RunTask = try store.get(.tasks, id: dispatch.task) {
                task.state = state
                task.reason = reason
                try store.put(.tasks, id: task.id, parent: task.run, task)
            }
        }
    }

    /// `orchestration.stop-dispatch`: the dispatch and every one below it
    /// stop; their tasks go back to ready, marked "stopped". Returns the
    /// stopped ids, for the caller to end their agents.
    @discardableResult
    public func stop(_ id: String) throws -> [Dispatch] {
        guard let root: Dispatch = try store.get(.dispatches, id: id) else { throw RunError.unknown(id) }
        let all = try dispatches(of: root.run)
        let ids = Set(RunGraph.descendants(of: id, dispatches: all, tasks: try tasks(of: root.run)))
        var stopped: [Dispatch] = []
        for var dispatch in RunGraph.live(all) where ids.contains(dispatch.id) {
            dispatch.state = .stopped
            dispatch.reason = "stopped"
            dispatch.endedAt = now()
            try end(dispatch, task: .pending, reason: "stopped")
            stopped.append(dispatch)
        }
        try settle(run: root.run)
        return stopped
    }

    /// Every live dispatch of a run stops, and the run takes no new ones.
    @discardableResult
    public func stopRun(_ id: String) throws -> [Dispatch] {
        guard var run = try run(id) else { throw RunError.unknown(id) }
        run.stopped = true
        try store.put(.runs, id: id, run)
        return try RunGraph.live(dispatches(of: id)).flatMap { try stop($0.id) }
    }

    /// The live dispatches whose agent is gone without a report fail,
    /// "exited without reporting"; returns their ids.
    @discardableResult
    public func reapOrphans(alive: (String) -> Bool) throws -> [String] {
        let all: [Dispatch] = try store.all(.dispatches)
        let gone = RunGraph.orphaned(all, alive: alive)
        for id in gone { try fail(id, reason: "exited without reporting") }
        return gone
    }
}

public enum RunError: Error, Equatable {
    case unknown(String)
    case cycle([String])
    case notReady(String, TaskState)
    case noSlot(Int)
    case stopped(String)
    case alreadyEnded(String)
    case noGate(String)
    case tooDeep(Int)
    case wrongRun(String)
}
