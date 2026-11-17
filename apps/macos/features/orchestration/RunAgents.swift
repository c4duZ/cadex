import Foundation

/// Who asks a run's command from an agent's session (plan 24 D2): the
/// dispatch whose session the token belongs to, or the run whose
/// coordinator it is. Found by the kit session the app matched to the
/// token, never by what the agent claims (docs/adr/0033-cadex-launches-agents.md).
public enum RunCaller: Equatable, Sendable {
    case dispatch(Dispatch)
    case coordinator(Run)

    public var run: String {
        switch self {
        case .dispatch(let dispatch): dispatch.run
        case .coordinator(let run): run.id
        }
    }
}

extension RunBook {
    /// The caller behind `kitSession`: its latest dispatch (ended ones too:
    /// a second report-done must hear "already done"), else the run it
    /// coordinates. A `claimed` CADEX_DISPATCH_ID that is not that dispatch
    /// is refused: a report never lands in another run.
    public func caller(kitSession: String, claimed: String?) throws -> RunCaller {
        guard !kitSession.isEmpty else { throw RunError.notSupervised }
        let mine = (try store.all(.dispatches) as [Dispatch]).filter { $0.session?.kit == kitSession }
        if let latest = mine.max(by: { $0.startedAt < $1.startedAt }) {
            if let claimed, claimed != latest.id { throw RunError.wrongRun(claimed) }
            return .dispatch(latest)
        }
        if claimed != nil { throw RunError.notSupervised }
        if let run = (try store.all(.runs) as [Run]).first(where: { $0.coordinator == kitSession && !$0.stopped }) {
            return .coordinator(run)
        }
        throw RunError.notSupervised
    }

    /// `report-heartbeat`: a sign of life with a short note.
    public func heartbeat(_ id: String, note: String) throws {
        guard var dispatch: Dispatch = try store.get(.dispatches, id: id), !RunGraph.live([dispatch]).isEmpty else { throw RunError.alreadyEnded(id) }
        dispatch.state = .working
        dispatch.lastSign = now()
        dispatch.note = note.isEmpty ? dispatch.note : String(note.prefix(300))
        try store.put(.dispatches, id: id, parent: dispatch.run, dispatch)
    }

    /// `orchestration.add-gate`: the task waits for the owner's approval
    /// (a ready one goes back to pending; a queued one leaves the queue).
    public func addGate(task id: String) throws {
        guard var task: RunTask = try store.get(.tasks, id: id), [.pending, .ready, .blocked].contains(task.state) else {
            throw RunError.noGate(id)
        }
        task.gate = .waiting
        task.queued = nil
        if task.state == .ready { task.state = .pending }
        try store.put(.tasks, id: id, parent: task.run, task)
        try settle(run: task.run)
    }

    /// A sub-task (`orchestration.spawn`): from a dispatch, one deeper than
    /// its task and refused at orchestration.maxDepth; from the coordinator,
    /// at the top. `after`: ids or titles of tasks of the same run. It is
    /// dispatched on its own (`auto`) when ready, as `agent`.
    public func spawnTask(by caller: RunCaller, title: String, spec: String, after: [String], gate: Bool,
                          maxDepth: Int, agent: AgentChoice) throws -> RunTask {
        guard try run(caller.run).map({ !$0.stopped }) ?? false else { throw RunError.stopped(caller.run) }
        var depth = 0
        var parent: String?
        if case .dispatch(let dispatch) = caller {
            guard !RunGraph.live([dispatch]).isEmpty else { throw RunError.alreadyEnded(dispatch.id) }
            guard let task: RunTask = try store.get(.tasks, id: dispatch.task) else { throw RunError.unknown(dispatch.task) }
            guard RunGraph.maySpawn(parentDepth: task.depth, maxDepth: maxDepth) else { throw RunError.tooDeep(maxDepth) }
            depth = task.depth + 1
            parent = dispatch.id
            try sign(dispatch.id)
        }
        let all = try tasks(of: caller.run)
        let deps = try after.map { name in
            guard let found = all.first(where: { $0.id == name }) ?? all.first(where: { $0.title == name }) else { throw RunError.unknown(name) }
            return found.id
        }
        var task = try addTask(run: caller.run, title: title, spec: spec, dependsOn: deps, gate: gate, spawnedBy: parent, depth: depth)
        task.auto = agent
        try store.put(.tasks, id: task.id, parent: task.run, task)
        return task
    }

    /// A ready task that could not start on its own (no trust, a spec too
    /// big…): it fails with the reason, instead of being tried at every
    /// tick; the owner retries it.
    public func failTask(_ id: String, reason: String) throws {
        guard var task: RunTask = try store.get(.tasks, id: id), task.state == .ready else { return }
        task.state = .failed
        task.reason = reason
        task.queued = nil
        try store.put(.tasks, id: id, parent: task.run, task)
        try settle(run: task.run)
    }

    /// The coordinator hears how each task ended, in its inbox.
    public func tellCoordinator(run id: String, from: String, text: String) throws {
        guard try run(id)?.coordinator != nil else { return }
        _ = try post(run: id, kind: .message, from: from, to: "coordinator", text: text)
    }

    /// How the run goes on its own: who runs ready tasks, and the
    /// coordinating agent's goal (plan 24 D2).
    public func configure(run id: String, autoAgent: AgentChoice?, goal: String?) throws {
        guard var run = try run(id) else { throw RunError.unknown(id) }
        run.autoAgent = autoAgent
        run.goal = goal
        try store.put(.runs, id: id, run)
    }

    /// The coordinating agent's session, once its tab opened; and its cost.
    public func setCoordinator(run id: String, kit: String?, cost: Double? = nil) throws {
        guard var run = try run(id) else { throw RunError.unknown(id) }
        if let kit { run.coordinator = kit }
        if let cost { run.coordinatorCostUsd = cost }
        try store.put(.runs, id: id, run)
    }

    /// The ready tasks that run on their own (spawned, or the run's
    /// autoAgent), with whom: what the app dispatches with no click.
    public func readyOnTheirOwn() throws -> [(task: RunTask, agent: AgentChoice)] {
        let open = (try store.all(.runs) as [Run]).filter { !$0.stopped }
        return try open.flatMap { run in
            try tasks(of: run.id).compactMap { task -> (task: RunTask, agent: AgentChoice)? in
                // A task the owner stopped waits for the owner: started again on
                // its own, the stop undid itself (found 2026-11-16, plan 24 D2).
                guard task.state == .ready, task.queued == nil, task.reason != "stopped",
                      let agent = task.auto ?? run.autoAgent else { return nil }
                return (task, agent)
            }
        }
    }
}
