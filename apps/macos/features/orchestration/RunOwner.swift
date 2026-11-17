import Foundation

/// What the app records of a dispatch while the owner coordinates (plan 24
/// D1, docs/spec/orchestration.md "Execuções"): the session its tab got, its
/// cost as the status line keeps it, the owner's "Mark Done", and the run's
/// cap. The agent's own reports (`report-done` and the rest) are D2.
extension RunBook {
    /// The tab's session, known only once the dispatch is recorded: its id
    /// goes into the session's environment (CADEX_DISPATCH_ID).
    public func attach(_ id: String, session: SessionLink) throws {
        guard var dispatch: Dispatch = try store.get(.dispatches, id: id) else { throw RunError.unknown(id) }
        dispatch.session = session
        try store.put(.dispatches, id: id, parent: dispatch.run, dispatch)
    }

    /// The session's cost and Claude's id, as the app last read them; a
    /// write only when something changed (said by the result).
    @discardableResult
    public func record(_ id: String, cost: Double?, claude: String?) throws -> Bool {
        guard var dispatch: Dispatch = try store.get(.dispatches, id: id) else { return false }
        let before = dispatch
        if let cost { dispatch.costUsd = cost }
        if let claude, dispatch.session != nil { dispatch.session?.claude = claude }
        guard dispatch != before else { return false }
        try store.put(.dispatches, id: id, parent: dispatch.run, dispatch)
        return true
    }

    /// The owner's "Mark Done": the owner looked at the work and says it is
    /// done. Also for a dispatch that already failed ("exited without
    /// reporting": in D1 no agent reports, so an agent closed before the
    /// owner marked it fails first). Returns the tasks that became ready.
    @discardableResult
    public func markDone(_ id: String, summary: String) throws -> [String] {
        guard var dispatch: Dispatch = try store.get(.dispatches, id: id) else { throw RunError.unknown(id) }
        guard [.starting, .working, .failed].contains(dispatch.state) else { throw RunError.alreadyEnded(id) }
        // Only the task's latest try: an older failed one does not finish it.
        let tries = try dispatches(of: dispatch.run).filter { $0.task == dispatch.task }
        guard tries.map(\.attempt).max() == dispatch.attempt else { throw RunError.alreadyEnded(id) }
        dispatch.state = .done
        dispatch.summary = summary
        dispatch.reason = nil
        dispatch.endedAt = dispatch.endedAt ?? now()
        try end(dispatch, task: .done, reason: nil)
        return try settle(run: dispatch.run)
    }

    /// Stops the run when it passed its cap; the stopped dispatches, for the
    /// caller to end their agents (empty when under the cap).
    public func enforceCap(run id: String) throws -> [Dispatch] {
        guard let run = try run(id), !run.stopped else { return [] }
        guard RunGraph.overCap(run.caps, dispatches: try dispatches(of: id), now: now(), extra: run.coordinatorCostUsd ?? 0) else { return [] }
        return try stopRun(id, reason: "hit the cap")
    }
}

extension RunGraph {
    /// What a run spent: every dispatch's last known cost.
    public static func spent(_ dispatches: [Dispatch]) -> Double {
        dispatches.reduce(0) { $0 + ($1.costUsd ?? 0) }
    }

    /// How long the run had at least one agent working: the union of the
    /// dispatches' spans (a live one runs to `now`). Not the time since the
    /// run was made: a run the owner fills over a day would hit its cap
    /// before any agent ran (decided 2026-11-16, plan 24 D1).
    public static func busySeconds(_ dispatches: [Dispatch], now: Date) -> TimeInterval {
        let spans = dispatches.map { ($0.startedAt, $0.endedAt ?? (live([$0]).isEmpty ? $0.startedAt : now)) }
            .filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for span in spans {
            if let open = current, span.0 <= open.1 {
                current = (open.0, max(open.1, span.1))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = span
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return total
    }

    /// Past the run's cap, in money or in time with agents working.
    /// `extra`: the coordinating agent's cost, which counts too.
    public static func overCap(_ caps: Caps, dispatches: [Dispatch], now: Date, extra: Double = 0) -> Bool {
        spent(dispatches) + extra > caps.budgetUsd || busySeconds(dispatches, now: now) > TimeInterval(caps.maxMinutes * 60)
    }
}
