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
            list(.retry, "orchestration.retry", T("Retry a Failed Task", "Tentar de novo uma tarefa que falhou"), ["retry", "again", "de novo"]),
            list(.markDone, "orchestration.mark-done", T("Mark a Dispatch Done", "Marcar um despacho como concluído"), ["done", "concluída", "finish"]),
            list(.stopDispatch, "orchestration.stop-dispatch", T("Stop a Dispatch", "Parar um despacho"), ["stop", "parar", "kill"]),
            list(.stopRun, "orchestration.stop-run", T("Stop a Run", "Parar uma execução"), ["stop", "parar"]),
            list(.setDependencies, "orchestration.set-dependencies", T("Change a Task's Dependencies", "Mudar as dependências de uma tarefa"),
                 ["dependencies", "dependências", "after", "depois", "order", "ordem"]),
        ]
    }
}

/// ⌘K's list of runs, tasks or dispatches for one of the run's commands.
@MainActor
final class RunSource: PaletteSource {
    enum Kind { case show, addTask, dispatch, retry, markDone, stopDispatch, stopRun, setDependencies }
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
