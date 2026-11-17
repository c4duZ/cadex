import Foundation
import Strings

/// The owner's dispatches waiting for a free slot (docs/spec/orchestration.md
/// "Estados": "waiting for a free slot (6 of 6)"; plan 24 D1): kept on the
/// task, so a queue survives the app closing, and handed back oldest first
/// when an agent ends.
extension RunBook {
    /// Queues a ready task's dispatch; refused for a task that is not ready
    /// or a stopped run.
    public func queue(_ request: DispatchRequest) throws {
        guard var task: RunTask = try store.get(.tasks, id: request.task) else { throw RunError.unknown(request.task) }
        guard task.state == .ready else { throw RunError.notReady(task.id, task.state) }
        guard let run = try run(task.run), !run.stopped else { throw RunError.stopped(task.run) }
        task.queued = QueuedDispatch(agent: request.agent, base: request.base, reuseShell: request.reuseShell, at: now())
        try store.put(.tasks, id: task.id, parent: task.run, task)
    }

    /// The owner took it out of the queue (orchestration.stop-dispatch on a waiting one).
    public func unqueue(task id: String) throws {
        guard var task: RunTask = try store.get(.tasks, id: id), task.queued != nil else { return }
        task.queued = nil
        try store.put(.tasks, id: id, parent: task.run, task)
    }

    /// What waits, oldest first: only ready tasks of runs still going (a
    /// task that stopped being ready leaves the queue when it is drained).
    public func waiting() throws -> [DispatchRequest] {
        let open = Set((try store.all(.runs) as [Run]).filter { !$0.stopped }.map(\.id))
        return try (store.all(.tasks) as [RunTask])
            .filter { $0.queued != nil && open.contains($0.run) }
            .sorted { $0.queued!.at < $1.queued!.at }
            .compactMap { task in
                guard task.state == .ready, let queued = task.queued else {
                    try? unqueue(task: task.id)
                    return nil
                }
                return DispatchRequest(task: task.id, agent: queued.agent, base: queued.base, reuseShell: queued.reuseShell)
            }
    }
}

extension RunError {
    /// What the owner reads; a cycle by the tasks' titles ("a → c → b → a").
    public func message(titles: [String: String]) -> String {
        let name = { (id: String) in titles[id] ?? id }
        switch self {
        case .unknown(let id): return T("\(name(id)) is not a task of this run.", "\(name(id)) não é uma tarefa desta execução.")
        case .cycle(let ids):
            return T("That would close a cycle: ", "Isso fecharia um ciclo: ") + ids.map(name).joined(separator: " → ")
        case .notReady(let id, let state): return T("\(name(id)) is \(RunRows.stateLabel(state).lowercased()).", "\(name(id)) está \(RunRows.stateLabel(state).lowercased()).")
        case .noSlot(let max): return DispatchRefusal.noSlot(max).message
        case .stopped: return DispatchRefusal.runStopped.message
        case .alreadyEnded(_): return T("That try already ended.", "Essa tentativa já terminou.")
        case .noGate(let id): return T("\(name(id)) has no gate waiting.", "\(name(id)) não tem portão esperando.")
        case .tooDeep(let max): return T("Sub-tasks go at most \(max) deep (Settings › Many Agents).", "Sub-tarefas vão no máximo \(max) níveis (Configurações › Muitos agentes).")
        case .wrongRun(_): return T("That dispatch is of another run.", "Esse despacho é de outra execução.")
        }
    }
}
