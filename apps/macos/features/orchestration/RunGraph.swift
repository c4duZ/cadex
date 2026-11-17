import Foundation

/// The rules of a run, pure (docs/spec/orchestration.md, "Execuções"): when a
/// task is ready or blocked, which dependency would close a cycle, how deep a
/// spawned task may go, which dispatches are stalled or orphaned, and who
/// stops with a parent. No disk, no clock of its own: the tests feed it.
public enum RunGraph {
    /// The state each pending, ready or blocked task should be in now. A task
    /// is ready when every dependency is done and its gate (if any) approved;
    /// blocked when a dependency failed or is blocked, or its gate was
    /// rejected. Dispatched, done and failed tasks keep theirs.
    public static func settle(_ tasks: [RunTask]) -> [String: TaskState] {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [String: TaskState] = [:]
        // Blocked spreads down a chain: settle in dependency order, so a
        // task sees what its dependencies just became.
        for id in order(tasks) {
            guard let task = byId[id] else { continue }
            out[id] = next(task, depState: { out[$0] ?? byId[$0]?.state })
        }
        return out
    }

    static func next(_ task: RunTask, depState: (String) -> TaskState?) -> TaskState {
        switch task.state {
        case .dispatched, .done, .failed: return task.state
        case .pending, .ready, .blocked: break
        }
        if task.gate == .rejected { return .blocked }
        let deps = task.dependsOn.map(depState)
        // A dependency that does not exist (removed by hand) blocks: it
        // will never be done.
        if deps.contains(where: { $0 == nil || $0 == .failed || $0 == .blocked }) { return .blocked }
        guard deps.allSatisfy({ $0 == .done }) else { return .pending }
        return task.gate == .waiting ? .pending : .ready
    }

    /// The tasks with each one after its dependencies; a task in a cycle
    /// (only from a file edited by hand: `cycle` refuses them) goes last.
    static func order(_ tasks: [RunTask]) -> [String] {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var visiting: Set<String> = []
        var out: [String] = []
        func visit(_ id: String) {
            guard !seen.contains(id), !visiting.contains(id), let task = byId[id] else { return }
            visiting.insert(id)
            task.dependsOn.forEach(visit)
            visiting.remove(id)
            seen.insert(id)
            out.append(id)
        }
        tasks.map(\.id).forEach(visit)
        return out + tasks.map(\.id).filter { !seen.contains($0) }
    }

    /// The cycle that giving `task` the dependencies `deps` would close, as
    /// task ids from `task` back to itself; nil when there is none.
    public static func cycle(adding deps: [String], to task: String, in tasks: [RunTask]) -> [String]? {
        var edges = Dictionary(tasks.map { ($0.id, $0.dependsOn) }, uniquingKeysWith: { first, _ in first })
        edges[task] = deps
        // Depth-first from each new dependency: reaching `task` again is a cycle.
        func path(from id: String, _ trail: [String], _ seen: inout Set<String>) -> [String]? {
            if id == task { return trail + [id] }
            guard seen.insert(id).inserted else { return nil }
            for dep in edges[id] ?? [] {
                if let found = path(from: dep, trail + [id], &seen) { return found }
            }
            return nil
        }
        for dep in deps {
            var seen: Set<String> = []
            if let found = path(from: dep, [task], &seen) { return found }
        }
        return nil
    }

    /// Whether a dispatch at `parentDepth` may spawn a task: the new one is
    /// one deeper, and orchestration.maxDepth is the deepest allowed.
    public static func maySpawn(parentDepth: Int, maxDepth: Int) -> Bool {
        parentDepth + 1 <= maxDepth
    }

    /// Live dispatches (starting or working): what counts against
    /// orchestration.maxAgents.
    public static func live(_ dispatches: [Dispatch]) -> [Dispatch] {
        dispatches.filter { $0.state == .starting || $0.state == .working }
    }

    public static func hasSlot(_ dispatches: [Dispatch], maxAgents: Int) -> Bool {
        live(dispatches).count < maxAgents
    }

    /// Live dispatches (starting or working) with no sign of life for `minutes` before `now`.
    public static func stalled(_ dispatches: [Dispatch], minutes: Int, now: Date) -> [String] {
        // Starting counts too: a dispatch that never sent a hook or a report is as quiet (2026-11-16, plan 24 D2).
        let limit = TimeInterval(minutes * 60)
        return live(dispatches).filter { now.timeIntervalSince($0.lastSign) >= limit }.map(\.id)
    }

    /// Live dispatches whose session is gone without a report: the agent
    /// exited (or the app lost it) and the task must fail, "exited without
    /// reporting". `alive` answers for a kit session key.
    public static func orphaned(_ dispatches: [Dispatch], alive: (String) -> Bool) -> [String] {
        live(dispatches).filter { dispatch in
            guard let session = dispatch.session else { return dispatch.state == .working }
            return !alive(session.kit)
        }.map(\.id)
    }

    /// `root` and every dispatch below it: the dispatches of tasks it
    /// spawned, and theirs (stopping a parent stops them all).
    public static func descendants(of root: String, dispatches: [Dispatch], tasks: [RunTask]) -> [String] {
        var out = [root]
        var index = 0
        while index < out.count {
            let parent = out[index]
            let children = Set(tasks.filter { $0.spawnedBy == parent }.map(\.id))
            out += dispatches.filter { children.contains($0.task) && !out.contains($0.id) }.map(\.id)
            index += 1
        }
        return out
    }
}
