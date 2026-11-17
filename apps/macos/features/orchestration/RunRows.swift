import Foundation
import Strings

/// One task of the run's page, ready to draw (plan 24 D1): its state, what
/// it waits for, its current dispatch as the app sees it, and which of the
/// owner's actions fit now.
public struct RunRow: Equatable, Sendable {
    public let task: String
    public let title: String
    public let state: String
    /// How deep in the graph: 0 waits for nothing, else one more than the
    /// deepest task it waits for (the page indents by it).
    public let level: Int
    /// "after: a, b"; empty with no dependency.
    public let after: String
    /// The latest dispatch: "try 2 · haiku · bkdg · Working · 2m 5s · US$ 0.0100";
    /// "waiting for a free slot (6 of 6)" while queued; empty before any.
    public let dispatch: String
    /// The earlier tries, each with why it ended ("try 1 · haiku · bkdg · Stopped · US$ 0.0042 — stopped").
    public let history: [String]
    /// Why it failed or stopped, when it did.
    public let reason: String
    /// The latest dispatch's id, for the actions.
    public let dispatchID: String?
    public let isQueued: Bool
    public let canDispatch: Bool
    /// Stop a live try, or take a waiting one out of the queue.
    public let canStop: Bool
    public let canMarkDone: Bool
    public let canRetry: Bool
    public let canGoToTerminal: Bool
    public let canEditDependencies: Bool
}

public enum RunRows {
    /// The page's rows, each task after what it depends on. `liveAgents`:
    /// how many agents are alive now (races too), for the queue's line.
    public static func make(run: Run, tasks: [RunTask], dispatches: [Dispatch], live: (Dispatch) -> ContenderLive?, now: Date,
                            maxAgents: Int = 6, liveAgents: Int = 0) -> [RunRow] {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let levels = RunRows.levels(tasks)
        return RunGraph.order(tasks).compactMap { byId[$0] }.map { task in
            let tries = dispatches.filter { $0.task == task.id }.sorted { $0.attempt < $1.attempt }
            let latest = tries.last
            let isLive = latest.map { !RunGraph.live([$0]).isEmpty } ?? false
            let queued = task.queued != nil && task.state == .ready && !run.stopped
            let line = queued ? T("waiting for a free slot (\(liveAgents) of \(maxAgents))", "esperando uma vaga (\(liveAgents) de \(maxAgents))")
                              : latest.map { dispatchLabel($0, info: live($0), now: now) } ?? ""
            return RunRow(
                task: task.id,
                title: task.title,
                state: stateLabel(task.state),
                level: levels[task.id] ?? 0,
                after: task.dependsOn.isEmpty ? "" : T("after: ", "depois de: ") + task.dependsOn.map { byId[$0]?.title ?? "?" }.joined(separator: ", "),
                dispatch: line,
                history: (queued ? tries : tries.dropLast()).map { earlier in
                    dispatchLabel(earlier, info: nil, now: now) + (earlier.reason.map { " — " + $0 } ?? "")
                },
                reason: task.reason ?? "",
                dispatchID: latest?.id,
                isQueued: queued,
                canDispatch: task.state == .ready && !run.stopped && !queued,
                canStop: isLive || queued,
                canMarkDone: latest.map { isLive || ($0.state == .failed && task.state == .failed) } ?? false,
                canRetry: task.state == .failed && !run.stopped,
                canGoToTerminal: latest.map { $0.session != nil && $0.state != .stopped && !queued } ?? false,
                canEditDependencies: [.pending, .ready, .blocked].contains(task.state) && !run.stopped && !queued)
        }
    }

    /// Each task's depth in the graph (a task in a cycle, only from a file
    /// edited by hand, counts as 0 there).
    static func levels(_ tasks: [RunTask]) -> [String: Int] {
        let byId = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [String: Int] = [:]
        for id in RunGraph.order(tasks) {
            let deps = byId[id]?.dependsOn ?? []
            out[id] = deps.isEmpty ? 0 : (deps.compactMap { out[$0] }.max() ?? -1) + 1
        }
        return out
    }

    public static func stateLabel(_ state: TaskState) -> String {
        switch state {
        case .pending: return T("Pending", "Pendente")
        case .ready: return T("Ready", "Pronta")
        case .dispatched: return T("Dispatched", "Despachada")
        case .done: return T("Done", "Concluída")
        case .failed: return T("Failed", "Falhou")
        case .blocked: return T("Blocked", "Bloqueada")
        }
    }

    static func dispatchLabel(_ dispatch: Dispatch, info: ContenderLive?, now: Date) -> String {
        var parts = [T("try \(dispatch.attempt)", "tentativa \(dispatch.attempt)"), RaceColumns.agentLabel(dispatch.agent)]
        switch dispatch.state {
        case .starting, .working:
            parts.append(liveLabel(info?.state))
            if let since = info?.since { parts.append(RaceColumns.duration(now.timeIntervalSince(since))) }
        case .done: parts.append(T("Done", "Concluído"))
        case .failed: parts.append(T("Failed", "Falhou"))
        case .stopped: parts.append(T("Stopped", "Parado"))
        }
        parts.append(RaceColumns.costLabel(info?.costUsd ?? dispatch.costUsd, remote: false))
        return parts.joined(separator: " · ")
    }

    static func liveLabel(_ state: ContenderLive.State?) -> String {
        switch state {
        case .starting?: return T("Starting", "Começando")
        case .working?: return T("Working", "Trabalhando")
        case .waiting?: return T("Waiting for you", "Esperando você")
        // In D1 the owner coordinates: a quiet agent waits for "Mark Done".
        case .finished?: return T("Finished: Mark Done?", "Terminou: marcar como concluída?")
        case .exited?: return T("Exited", "Saiu")
        case .unknown?, nil: return T("Unknown", "Desconhecido")
        }
    }

    /// "US$ 0.0100 of 5.00 · 3m 10s of 60 min with agents working · stopped: hit the cap".
    public static func summary(run: Run, dispatches: [Dispatch], now: Date) -> String {
        let spent = RunGraph.spent(dispatches)
        // A test cap of US$ 0.001 read "of 0.00" (2026-11-16): the cap keeps its digits too.
        var parts = [T("US$ \(cost(spent)) of \(cost(run.caps.budgetUsd))", "US$ \(cost(spent)) de \(cost(run.caps.budgetUsd))"),
                     T("\(RaceColumns.duration(RunGraph.busySeconds(dispatches, now: now))) of \(run.caps.maxMinutes) min with agents working",
                       "\(RaceColumns.duration(RunGraph.busySeconds(dispatches, now: now))) de \(run.caps.maxMinutes) min com agentes trabalhando")]
        if run.stopped { parts.append(T("stopped: ", "parada: ") + (run.reason ?? "stopped")) }
        return parts.joined(separator: " · ")
    }

    static func cost(_ value: Double) -> String { String(format: value < 0.1 ? "%.4f" : "%.2f", value) }
}
