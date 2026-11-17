import Foundation
import Strings

/// Why a dispatch does not start; said before any worktree or tab (plan 24
/// D1, docs/spec/orchestration.md "Antes de rodar").
public enum DispatchRefusal: Error, Equatable {
    case off
    case runStopped
    case notReady(TaskState)
    case emptySpec
    case specTooBig(Int)
    /// orchestration.maxAgents agents are live: "waiting for a free slot (6 of 6)".
    case noSlot(Int)
    /// The account (its folder's name, and the folder: nil is ~/.claude)
    /// whose Claude Code does not trust the repository: "Open Claude to Trust".
    case notTrusted(String, dir: String?)

    public var message: String {
        switch self {
        case .off: return RaceRefusal.off.message
        case .runStopped: return T("The run was stopped; it takes no new dispatches.", "A execução foi parada; ela não aceita despachos novos.")
        case .notReady(let state): return T("The task is not ready (\(RunRows.stateLabel(state))).", "A tarefa não está pronta (\(RunRows.stateLabel(state))).")
        case .emptySpec: return T("The task has no specification to send.", "A tarefa não tem especificação para mandar.")
        case .specTooBig(let bytes): return RaceRefusal.promptTooBig(bytes).message
        case .noSlot(let max): return T("No free slot: \(max) of \(max) agents are working (Settings › Many Agents).",
                                        "Sem vaga: \(max) de \(max) agentes trabalhando (Configurações › Muitos agentes).")
        case .notTrusted(let account, _):
            return T("Claude Code does not trust this repository yet in \(account). Open Claude there with that account and accept, then dispatch again.",
                     "O Claude Code ainda não confia neste repositório em \(account). Abra o Claude lá com essa conta e aceite, depois despache de novo.")
        }
    }
}

/// What the dispatch sheet asks: who runs the task and where it starts.
public struct DispatchRequest: Equatable, Sendable {
    public var task: String
    public var agent: AgentChoice
    /// The branch the worktree starts from: the repository's, or a done
    /// dependency's (its work is there).
    public var base: String
    /// An idle terminal to run it in instead of a new worktree and tab (its
    /// shell's pid): the spec's "terminal parado reaproveitado".
    public var reuseShell: Int32?
    public init(task: String, agent: AgentChoice, base: String, reuseShell: Int32? = nil) {
        self.task = task
        self.agent = agent
        self.base = base
        self.reuseShell = reuseShell
    }
}

public enum RunLaunch {
    /// The checks before a dispatch, in the order the owner can fix them.
    /// `all` is every dispatch of every run and `othersLive` the races'
    /// agents alive now (the cap is for the whole app); `trusts` answers for
    /// an account's folder (nil, the default). No slot is said last: the
    /// app queues the dispatch then, everything else being fine.
    public static func check(_ request: DispatchRequest, run: Run, task: RunTask, all: [Dispatch], othersLive: Int = 0, enabled: Bool,
                             maxAgents: Int, trusts: (String?) -> Bool) -> DispatchRefusal? {
        guard enabled else { return .off }
        guard !run.stopped else { return .runStopped }
        guard task.state == .ready else { return .notReady(task.state) }
        let prompt = Self.prompt(task)
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .emptySpec }
        let bytes = Data(prompt.utf8).count
        guard bytes <= PromptFiles.maxBytes else { return .specTooBig(bytes) }
        guard trusts(request.agent.account) else {
            return .notTrusted(request.agent.account.map { ($0 as NSString).lastPathComponent } ?? "~/.claude", dir: request.agent.account)
        }
        guard RunGraph.hasSlot(all, maxAgents: maxAgents - othersLive) else { return .noSlot(maxAgents) }
        return nil
    }

    /// The agent's prompt: the task's specification (the title when it has none).
    public static func prompt(_ task: RunTask) -> String {
        task.spec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? task.title : task.spec
    }

    /// The worktree's task name, `<run>-<task>`; New Task turns it into a
    /// branch and adds "-2", "-3"… for a retry.
    public static func taskName(run: Run, task: RunTask) -> String {
        String((run.name + "-" + task.title).prefix(60))
    }

    /// Where the dispatch may start: each done dependency's branch, the
    /// latest first, then the repository's branch now. A chain's next task
    /// sees the work before it (the worktree's folder is its branch's name).
    public static func bases(for task: RunTask, dispatches: [Dispatch], repositoryBranch: String) -> [String] {
        let done = dispatches.filter { $0.state == .done && task.dependsOn.contains($0.task) }
            .sorted { ($0.endedAt ?? $0.startedAt) > ($1.endedAt ?? $1.startedAt) }
            .map { ($0.worktree as NSString).lastPathComponent }
        var seen: Set<String> = []
        return (done + [repositoryBranch]).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
