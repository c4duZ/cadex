import AppKit
import StateGlyph
import UILooks
import Strings
import Tabs

/// What the run page's buttons do: each runs one of the feature's commands
/// on that task or dispatch, given by the app (ADR 0005).
@MainActor
public struct RunPageActions {
    public var addTask: () -> Void = {}
    public var stopRun: () -> Void = {}
    public var dispatch: (String) -> Void = { _ in }
    public var goToTerminal: (String) -> Void = { _ in }
    /// A task's live try stopped, or its waiting dispatch taken out of the queue.
    public var stop: (String) -> Void = { _ in }
    public var editDependencies: (String) -> Void = { _ in }
    public var addGate: (String) -> Void = { _ in }
    public var approveGate: (String) -> Void = { _ in }
    public var rejectGate: (String) -> Void = { _ in }
    /// A question to the owner, by its id.
    public var answer: (String) -> Void = { _ in }
    public var markDone: (String) -> Void = { _ in }
    public var retry: (String) -> Void = { _ in }
    public init() {}
}

/// The run's page (docs/spec/orchestration.md, "A página da execução"; plan 24 D1, in the new
/// frame's face in plan 30 B): the run's name, its folder and who coordinates, Add Task and Stop
/// Run; what it spent against its cap; the tasks as cards in dependency order (each one step
/// right of what it waits for) with their state, what they wait for, the latest dispatch, the
/// gate and the actions that fit; then the inbox.
@MainActor
enum RunPageView {
    static func sections(run: Run, summary: String, rows: [RunRow], inbox: [InboxLine], actions: RunPageActions) -> [NSView] {
        let coordinator = run.coordinator == nil ? T("coordinated by you", "coordenada por você") : T("coordinated by an agent", "coordenada por um agente")
        var buttons: [NSView] = []
        if !run.stopped {
            buttons.append(OrchestrationPage.button(T("Stop run…", "Parar a execução…")) { actions.stopRun() })
            buttons.append(OrchestrationPage.button(T("Add task…", "Adicionar tarefa…"), primary: true) { actions.addTask() })
        }
        var sections: [NSView] = [
            OrchestrationPage.head(run.name, meta: (run.repository as NSString).abbreviatingWithTildeInPath + " · " + coordinator, buttons: buttons),
            boardLabel(summary, size: DesignTokens.FontSize.body, color: run.stopped ? DesignTokens.Color.textMuted : DesignTokens.Color.textBody),
        ]
        var tasks: [NSView] = [OrchestrationPage.section(T("TASKS", "TAREFAS"))]
        if rows.isEmpty {
            tasks.append(boardLabel(T("No tasks yet: add one, then dispatch it when it is ready.", "Nenhuma tarefa ainda: adicione uma e despache quando estiver pronta."),
                                    size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textMuted))
        }
        tasks += rows.map { card($0, actions: actions) }
        sections.append(stretched(tasks, gap: DesignTokens.Board.Column.gap))
        guard !inbox.isEmpty else { return sections }
        var lines: [NSView] = [OrchestrationPage.section(T("INBOX", "CAIXA DE ENTRADA"))]
        for line in inbox.prefix(30) {
            lines.append(OrchestrationPage.card(state: line.canAnswer ? .needs : nil, title: line.text, lines: [],
                                                buttons: line.canAnswer ? [OrchestrationPage.button(T("Answer…", "Responder…")) { actions.answer(line.id) }] : []))
        }
        sections.append(stretched(lines, gap: DesignTokens.Board.Column.gap))
        return sections
    }

    /// A column whose rows (all but its label) take its width.
    private static func stretched(_ views: [NSView], gap: CGFloat) -> NSView {
        let column = OrchestrationPage.stack(views, gap: gap)
        for view in views.dropFirst() { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        return column
    }

    /// The task's state as the glyph of its card.
    static func glyph(_ row: RunRow) -> GlyphState {
        if row.isStalled || row.canDecideGate { return .needs }
        switch row.state {
        case RunRows.stateLabel(.done): return .done
        case RunRows.stateLabel(.failed), RunRows.stateLabel(.blocked): return .failed
        case RunRows.stateLabel(.dispatched): return .working
        default: return .idle
        }
    }

    private static func card(_ row: RunRow, actions: RunPageActions) -> NSView {
        typealias C = DesignTokens.Board.Card
        var lines: [(String, NSColor)] = [(row.after, C.Meta.color)]
        // "stalled?" amber (docs/spec/orchestration.md "Estados"); a queued try in the link's blue.
        lines.append((row.dispatch, row.isStalled ? DesignTokens.Color.stateNeeds : row.isQueued ? DesignTokens.Color.accentLink : C.Text.color))
        lines.append((row.gate, row.canDecideGate ? DesignTokens.Color.stateNeeds : C.Meta.color))
        lines += row.delivered.map { ("· " + $0, C.Meta.color) }
        lines.append((row.reason, C.Meta.color))
        lines += row.history.map { ($0, C.Meta.color) }
        var buttons: [NSView] = []
        if row.canDispatch { buttons.append(OrchestrationPage.button(T("Dispatch…", "Despachar…"), primary: true) { actions.dispatch(row.task) }) }
        if let id = row.dispatchID, row.canGoToTerminal { buttons.append(OrchestrationPage.button(T("Go to terminal", "Ir ao terminal")) { actions.goToTerminal(id) }) }
        if row.canStop {
            buttons.append(OrchestrationPage.button(row.isQueued ? T("Stop waiting", "Parar de esperar") : T("Stop…", "Parar…")) { actions.stop(row.task) })
        }
        if let id = row.dispatchID, row.canMarkDone { buttons.append(OrchestrationPage.button(T("Mark done", "Marcar concluída")) { actions.markDone(id) }) }
        if row.canRetry { buttons.append(OrchestrationPage.button(T("Retry…", "Tentar de novo…")) { actions.retry(row.task) }) }
        if row.canDecideGate {
            buttons.append(OrchestrationPage.button(T("Approve", "Aprovar"), primary: true) { actions.approveGate(row.task) })
            buttons.append(OrchestrationPage.button(T("Reject…", "Recusar…")) { actions.rejectGate(row.task) })
        }
        if row.canAddGate { buttons.append(OrchestrationPage.button(T("Add gate", "Pôr portão")) { actions.addGate(row.task) }) }
        if row.canEditDependencies { buttons.append(OrchestrationPage.button(T("Dependencies…", "Dependências…")) { actions.editDependencies(row.task) }) }
        return OrchestrationPage.card(state: glyph(row), title: row.title, trailing: row.state, lines: lines, buttons: buttons, indent: row.level)
    }
}

/// A run's page in a tab (orchestration.show-run): reads the state when it
/// opens and on `refresh` (a hook, a report, the app's timer while it is
/// open); closed, it lets go of everything.
@MainActor
public final class RunPageDocument: TabDocument {
    public let runID: String
    public var onChange: (() -> Void)?
    public var onClose: (() -> Void)?
    public private(set) var title = "Run"
    private let page = OrchestrationPage()
    private let actions: RunPageActions
    private let book: RunBook
    private let live: (Dispatch) -> ContenderLive?
    /// The agents alive now in races and runs, and orchestration.maxAgents: the queue's line.
    public var slots: () -> (live: Int, max: Int) = { (0, 6) }
    /// orchestration.heartbeatMinutes: "stalled?" after that long without a sign of life.
    public var heartbeatMinutes: () -> Int = { 10 }

    public init(runID: String, book: RunBook, actions: RunPageActions, live: @escaping (Dispatch) -> ContenderLive?) {
        self.runID = runID
        self.book = book
        self.live = live
        self.actions = actions
        refresh()
    }

    public static func identity(for run: String) -> String { "run:\(run)" }
    public var identity: String { Self.identity(for: runID) }
    public var view: NSView { page }
    public var hasUnsavedChanges: Bool { false }
    public var isPage: Bool { true }

    public func refresh() {
        guard let run = try? book.run(runID) else { return }
        let tasks = (try? book.tasks(of: runID)) ?? []
        let dispatches = (try? book.dispatches(of: runID)) ?? []
        let now = Date()
        let messages: [RunMessage] = (try? book.store.all(.messages, parent: runID)) ?? []
        page.show(RunPageView.sections(run: run, summary: RunRows.summary(run: run, dispatches: dispatches, now: now),
                                       rows: RunRows.make(run: run, tasks: tasks, dispatches: dispatches, live: live, now: now,
                                                          maxAgents: slots().max, liveAgents: slots().live, heartbeatMinutes: heartbeatMinutes()),
                                       inbox: RunRows.inbox(messages, tasks: tasks, dispatches: dispatches), actions: actions))
        if title != run.name {
            title = run.name
            onChange?()
        }
    }

    public func focus() { page.window?.makeFirstResponder(page) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() { onClose?() }
}
