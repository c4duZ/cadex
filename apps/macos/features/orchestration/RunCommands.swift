import AppKit
import CommandPalette
import Icons
import Strings

/// What the run's commands ask of the app: the sheets, the worktrees, the
/// tabs and the agents are the app's (it joins worktrees, agents and tabs).
public struct RunCommandActions {
    public var newRun: () -> Void = {}
    public var show: (Run) -> Void = { _ in }
    public var addTask: (Run) -> Void = { _ in }
    public var dispatch: (RunTask) -> Void = { _ in }
    public var retry: (RunTask) -> Void = { _ in }
    public var stopDispatch: (Dispatch) -> Void = { _ in }
    public var markDone: (Dispatch) -> Void = { _ in }
    public var stopRun: (Run) -> Void = { _ in }
    public var setDependencies: (RunTask) -> Void = { _ in }
    /// A dispatch waiting for a free slot, taken out of the queue.
    public var stopWaiting: (RunTask) -> Void = { _ in }
    public var addGate: (RunTask) -> Void = { _ in }
    public var approveGate: (RunTask) -> Void = { _ in }
    public var rejectGate: (RunTask) -> Void = { _ in }
    /// The owner's answer to a question in a run's inbox, by its id.
    public var answer: (String) -> Void = { _ in }
    /// A run's agent asking by `cadex run` (the six of ADR 0033, and retry
    /// from the coordinator): the app finds the caller by the token's session.
    public var agent: (String, CommandRequest) -> CommandReply = { _, _ in .failed("not ready") }
    public init() {}
}

/// The run's commands (docs/spec/orchestration.md "Execuções", plan 24 D1;
/// ADR 0005), each with its list in ⌘K. orchestration.mark-done is the
/// owner's "it is done" while no agent reports (D1); the agent's own
/// `report-done` comes in D2.
@MainActor
public enum RunCommands {
    public static func all(palette: CommandPaletteController, actions: RunCommandActions) -> [Command] {
        let controller = OrchestrationController.shared
        let off: @MainActor () -> String? = {
            controller.isEnabled ? nil : T("Races and runs are off (Settings › Many Agents)", "Corridas e execuções estão desligadas (Configurações › Muitos agentes)")
        }
        let keywords = ["run", "execução", "task", "tarefa", "dispatch", "despacho", "agents", "agentes", "orchestration", "orquestração"]
        func list(_ kind: RunSource.Kind, _ id: String, _ title: String, _ more: [String]) -> Command {
            Command(id: id, title: title, keywords: keywords + more, category: .view,
                    action: .run { palette.open(RunSource(kind: kind, actions: actions)) }, unavailableReason: off)
        }
        return [
            Command(id: "orchestration.new-run", title: T("New Run: Tasks for Several Agents", "Nova execução: tarefas para vários agentes"),
                    keywords: keywords + ["new", "nova"], category: .view, action: .run { actions.newRun() }, unavailableReason: off),
            list(.show, "orchestration.show-run", T("Show a Run", "Mostrar uma execução"), ["show", "mostrar", "page", "página"]),
            list(.addTask, "orchestration.add-task", T("Add a Task to a Run", "Adicionar uma tarefa a uma execução"), ["add", "adicionar"]),
            list(.dispatch, "orchestration.dispatch", T("Dispatch a Ready Task", "Despachar uma tarefa pronta"), ["start", "começar", "ready", "pronta"]),
            {
                var retry = list(.retry, "orchestration.retry", T("Retry a Failed Task", "Tentar de novo uma tarefa que falhou"), ["retry", "again", "de novo"])
                // The coordinator's retry (task=<id>), by `cadex run`.
                retry.argumentHelp = "task=<task id>"
                retry.withArguments = { actions.agent("orchestration.retry", $0) }
                return retry
            }(),
            list(.markDone, "orchestration.mark-done", T("Mark a Dispatch Done", "Marcar um despacho como concluído"), ["done", "concluída", "finish"]),
            list(.stopDispatch, "orchestration.stop-dispatch", T("Stop a Dispatch", "Parar um despacho"), ["stop", "parar", "kill"]),
            list(.stopRun, "orchestration.stop-run", T("Stop a Run", "Parar uma execução"), ["stop", "parar"]),
            list(.setDependencies, "orchestration.set-dependencies", T("Change a Task's Dependencies", "Mudar as dependências de uma tarefa"),
                 ["dependencies", "dependências", "after", "depois", "order", "ordem"]),
            list(.addGate, "orchestration.add-gate", T("Add a Gate to a Task", "Pôr um portão numa tarefa"), ["gate", "portão", "approval", "aprovação"]),
            list(.approveGate, "orchestration.approve-gate", T("Approve a Task's Gate", "Aprovar o portão de uma tarefa"), ["gate", "portão", "approve", "aprovar"]),
            list(.rejectGate, "orchestration.reject-gate", T("Reject a Task's Gate", "Recusar o portão de uma tarefa"), ["gate", "portão", "reject", "recusar"]),
            list(.answer, "orchestration.answer-question", T("Answer an Agent's Question", "Responder a pergunta de um agente"),
                 ["question", "pergunta", "answer", "responder", "inbox", "caixa"]),
        ] + agentCommands(palette: palette, actions: actions, off: off, keywords: keywords)
    }

    /// The commands a run's agents run by `cadex run` (docs/adr/0033-cadex-launches-agents.md).
    /// From ⌘K they open the list of runs: the owner reads the same on a run's page.
    static func agentCommands(palette: CommandPaletteController, actions: RunCommandActions, off: @escaping @MainActor () -> String?,
                              keywords: [String]) -> [Command] {
        let help: [(String, String, String)] = [
            ("orchestration.report-done", "summary=<what you did>", T("A Run's Agent: Report Its Task Done", "Agente de uma execução: tarefa concluída")),
            ("orchestration.report-heartbeat", "note=<doing what>", T("A Run's Agent: Sign of Life", "Agente de uma execução: sinal de vida")),
            ("orchestration.ask", "question=<one question>", T("A Run's Agent: Ask the Coordinator or the Owner", "Agente de uma execução: perguntar")),
            ("orchestration.send-message", "to=<dispatch id> text=<note> [answers=<question id>]", T("A Run's Agent: Message Another Task", "Agente de uma execução: recado a outra tarefa")),
            ("orchestration.inbox", "", T("A Run's Agent: Read Its Inbox", "Agente de uma execução: ler a caixa de entrada")),
            ("orchestration.spawn", "title=<title> spec-file=<file> [after=<task ids>] [gate=yes]", T("A Run's Agent: Spawn a Sub-Task", "Agente de uma execução: criar sub-tarefa")),
        ]
        return help.map { id, args, title in
            var command = Command(id: id, title: title, keywords: keywords + ["agent", "agente"], category: .view,
                                  action: .run { palette.open(RunSource(kind: .show, actions: actions)) }, unavailableReason: off)
            command.argumentHelp = args
            command.withArguments = { actions.agent(id, $0) }
            return command
        }
    }
}

/// ⌘K's list of runs, tasks or dispatches for one of the run's commands.
@MainActor
final class RunSource: PaletteSource {
    enum Kind { case show, addTask, dispatch, retry, markDone, stopDispatch, stopRun, setDependencies, addGate, approveGate, rejectGate, answer }
    private let kind: Kind
    private let actions: RunCommandActions

    init(kind: Kind, actions: RunCommandActions) {
        self.kind = kind
        self.actions = actions
    }

    var placeholder: String {
        switch kind {
        case .show: T("Show a run", "Mostrar uma execução")
        case .addTask: T("The run to add a task to", "A execução que ganha a tarefa")
        case .dispatch: T("The ready task to dispatch", "A tarefa pronta para despachar")
        case .retry: T("The failed task to try again", "A tarefa que falhou, para tentar de novo")
        case .markDone: T("The dispatch that is done", "O despacho concluído")
        case .stopDispatch: T("The dispatch to stop", "O despacho para parar")
        case .stopRun: T("The run to stop", "A execução para parar")
        case .setDependencies: T("The task whose dependencies to change", "A tarefa cujas dependências mudar")
        case .addGate: T("The task to hold for your approval", "A tarefa que espera sua aprovação")
        case .approveGate: T("The gate to approve", "O portão para aprovar")
        case .rejectGate: T("The gate to reject", "O portão para recusar")
        case .answer: T("The question to answer", "A pergunta para responder")
        }
    }
    var emptyText: String {
        if case .show = kind { return T("No runs yet: New Run (orchestration.new-run)", "Nenhuma execução ainda: Nova execução (orchestration.new-run)") }
        return T("Nothing fits", "Nada serve")
    }
    var icon: Icon { .gitBranch }

    /// One entry: what the row shows and what choosing it does.
    struct Entry {
        let item: PaletteItem
        let choose: () -> Void
    }

    func entries() -> [Entry] {
        guard let book = OrchestrationController.shared.runs() else { return [] }
        let runs = ((try? book.store.all(.runs) as [Run]) ?? []).sorted { $0.createdAt > $1.createdAt }
        let names = Dictionary(runs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let open = runs.filter { !$0.stopped }
        let tasks = open.flatMap { (try? book.tasks(of: $0.id)) ?? [] }
        let byTask = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let dispatches = open.flatMap { (try? book.dispatches(of: $0.id)) ?? [] }
        func run(_ r: Run, _ go: @escaping (Run) -> Void) -> Entry {
            Entry(item: PaletteItem(id: r.id, title: r.name, detail: (r.repository as NSString).lastPathComponent, icon: .gitBranch), choose: { go(r) })
        }
        func task(_ t: RunTask, _ go: @escaping (RunTask) -> Void) -> Entry {
            Entry(item: PaletteItem(id: t.id, title: t.title, detail: (names[t.run] ?? "") + " · " + RunRows.stateLabel(t.state), icon: .gitBranch),
                  choose: { go(t) })
        }
        func dispatch(_ d: Dispatch, _ go: @escaping (Dispatch) -> Void) -> Entry {
            let title = (byTask[d.task]?.title ?? "?") + " · " + T("try \(d.attempt)", "tentativa \(d.attempt)")
            return Entry(item: PaletteItem(id: d.id, title: title, detail: (names[d.run] ?? "") + " · " + RaceColumns.agentLabel(d.agent), icon: .gitBranch),
                         choose: { go(d) })
        }
        let latest = Dictionary(dispatches.map { ($0.task, $0) }, uniquingKeysWith: { $0.attempt > $1.attempt ? $0 : $1 })
        func byDispatchTitle(_ id: String) -> String? { dispatches.first { $0.id == id }.flatMap { byTask[$0.task]?.title } }
        switch kind {
        case .show: return runs.map { run($0, actions.show) }
        case .addTask: return open.map { run($0, actions.addTask) }
        case .stopRun: return open.map { run($0, actions.stopRun) }
        case .dispatch: return tasks.filter { $0.state == .ready }.map { task($0, actions.dispatch) }
        case .retry: return tasks.filter { $0.state == .failed }.map { task($0, actions.retry) }
        case .stopDispatch:
            let waiting = tasks.filter { $0.queued != nil && $0.state == .ready }.map { t in
                Entry(item: PaletteItem(id: t.id, title: t.title, detail: (names[t.run] ?? "") + " · " + T("waiting for a free slot", "esperando uma vaga"),
                                        icon: .gitBranch), choose: { [actions] in actions.stopWaiting(t) })
            }
            return RunGraph.live(dispatches).map { dispatch($0, actions.stopDispatch) } + waiting
        case .setDependencies:
            return tasks.filter { [.pending, .ready, .blocked].contains($0.state) && $0.queued == nil }.map { task($0, actions.setDependencies) }
        case .addGate: return tasks.filter { $0.gate == .none && [.pending, .ready, .blocked].contains($0.state) }.map { task($0, actions.addGate) }
        case .approveGate: return tasks.filter { $0.gate == .waiting }.map { task($0, actions.approveGate) }
        case .rejectGate: return tasks.filter { $0.gate == .waiting }.map { task($0, actions.rejectGate) }
        case .answer:
            let messages = open.flatMap { (try? book.store.all(.messages, parent: $0.id) as [RunMessage]) ?? [] }
            let answered = Set(messages.compactMap(\.answers))
            return messages.filter { $0.kind == .question && $0.to == "owner" && !answered.contains($0.id) }.map { line in
                Entry(item: PaletteItem(id: line.id, title: line.text, detail: (names[line.run] ?? "") + " · " + (byDispatchTitle(line.from) ?? ""), icon: .gitBranch),
                      choose: { [actions] in actions.answer(line.id) })
            }
        case .markDone:
            return latest.values.filter { !RunGraph.live([$0]).isEmpty || ($0.state == .failed && byTask[$0.task]?.state == .failed) }
                .sorted { $0.startedAt > $1.startedAt }.map { dispatch($0, actions.markDone) }
        }
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let match = { (text: String) in query.isEmpty || text.localizedCaseInsensitiveContains(query) }
        show(entries().map(\.item).filter { match($0.title) || match($0.detail ?? "") }, nil)
    }

    func choose(_ item: PaletteItem) {
        guard let entry = entries().first(where: { $0.item.id == item.id }) else { return }
        // The palette just closed: a sheet opens on the next turn.
        DispatchQueue.main.async { entry.choose() }
    }

    func stop() {}
}
