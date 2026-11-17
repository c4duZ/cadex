import AppKit
import Strings
import Tabs

/// What the run page's buttons do: each runs one of the feature's commands
/// on that task or dispatch, given by the app (ADR 0005).
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

/// The run's page (docs/spec/orchestration.md, "A página da execução"; plan
/// 24 D1): a header with the run, its coordinator and what it spent against
/// its cap, then the tasks in dependency order, each with its state, what it
/// waits for, its latest dispatch and the actions that fit. The inbox and
/// the gates come with the supervised agents (D2).
final class RunPageView: NSView {
    var colors: RaceBoardColors { didSet { layer?.backgroundColor = colors.background.cgColor } }
    var actions = RunPageActions()
    private let content = NSStackView()
    private let scroll = NSScrollView()

    init(colors: RaceBoardColors) {
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = colors.background.cgColor
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        content.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor), content.topAnchor.constraint(equalTo: document.topAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor), content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func show(run: Run, summary: String, rows: [RunRow], inbox: [InboxLine] = []) {
        content.arrangedSubviews.forEach { $0.removeFromSuperview() }
        content.addArrangedSubview(label(run.name, size: 18, weight: .semibold, color: colors.text))
        let coordinator = run.coordinator == nil ? T("coordinated by you", "coordenada por você") : T("coordinated by an agent", "coordenada por um agente")
        content.addArrangedSubview(label((run.repository as NSString).abbreviatingWithTildeInPath + " · " + coordinator, size: 11, color: colors.secondary))
        content.addArrangedSubview(label(summary, size: 12, color: run.stopped ? colors.secondary : colors.text))
        var top: [NSView] = []
        if !run.stopped {
            top.append(button(T("Add Task…", "Adicionar tarefa…")) { [weak self] in self?.actions.addTask() })
            top.append(button(T("Stop Run…", "Parar a execução…")) { [weak self] in self?.actions.stopRun() })
        }
        if !top.isEmpty { content.addArrangedSubview(NSStackView(views: top)) }
        if rows.isEmpty {
            content.addArrangedSubview(label(T("No tasks yet: add one, then dispatch it when it is ready.",
                                               "Nenhuma tarefa ainda: adicione uma e despache quando estiver pronta."), size: 12, color: colors.secondary))
        }
        rows.forEach { content.addArrangedSubview(rowView($0)) }
        guard !inbox.isEmpty else { return }
        content.addArrangedSubview(label(T("Inbox", "Caixa de entrada"), size: 14, weight: .semibold, color: colors.text))
        for line in inbox.prefix(30) {
            let text = label(line.text, size: 12, color: line.canAnswer ? colors.accent : colors.secondary, lines: 3)
            guard line.canAnswer else { content.addArrangedSubview(text); continue }
            content.addArrangedSubview(NSStackView(views: [text, button(T("Answer…", "Responder…")) { [weak self] in self?.actions.answer(line.id) }]))
        }
    }

    private func rowView(_ row: RunRow) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        // The graph: a task sits one step right of the deepest task it waits for.
        stack.edgeInsets = NSEdgeInsets(top: 0, left: CGFloat(min(row.level, 8)) * 28, bottom: 0, right: 0)
        let prefix = row.level > 0 ? "↳ " : ""
        stack.addArrangedSubview(label(prefix + row.title + "  ·  " + row.state, size: 13, weight: .semibold, color: colors.text))
        if !row.after.isEmpty { stack.addArrangedSubview(label(row.after, size: 11, color: colors.secondary)) }
        if !row.dispatch.isEmpty {
            // "stalled?" in yellow (docs/spec/orchestration.md "Estados").
            let color = row.isStalled ? NSColor.systemYellow : row.isQueued ? colors.accent : colors.text
            stack.addArrangedSubview(label(row.dispatch, size: 12, color: color))
        }
        if !row.gate.isEmpty { stack.addArrangedSubview(label(row.gate, size: 12, color: row.canDecideGate ? colors.accent : colors.secondary)) }
        row.delivered.forEach { stack.addArrangedSubview(label("· " + $0, size: 11, color: colors.secondary, lines: 3)) }
        if !row.reason.isEmpty { stack.addArrangedSubview(label(row.reason, size: 11, color: colors.secondary, lines: 2)) }
        row.history.forEach { stack.addArrangedSubview(label($0, size: 11, color: colors.secondary)) }
        var buttons: [NSView] = []
        if row.canDispatch { buttons.append(button(T("Dispatch…", "Despachar…")) { [weak self] in self?.actions.dispatch(row.task) }) }
        if let id = row.dispatchID, row.canGoToTerminal {
            buttons.append(button(T("Go to Terminal", "Ir ao terminal")) { [weak self] in self?.actions.goToTerminal(id) })
        }
        if row.canStop {
            buttons.append(button(row.isQueued ? T("Stop Waiting", "Parar de esperar") : T("Stop…", "Parar…")) { [weak self] in self?.actions.stop(row.task) })
        }
        if let id = row.dispatchID, row.canMarkDone {
            buttons.append(button(T("Mark Done", "Marcar concluída")) { [weak self] in self?.actions.markDone(id) })
        }
        if row.canRetry { buttons.append(button(T("Retry…", "Tentar de novo…")) { [weak self] in self?.actions.retry(row.task) }) }
        if row.canDecideGate {
            buttons.append(button(T("Approve", "Aprovar")) { [weak self] in self?.actions.approveGate(row.task) })
            buttons.append(button(T("Reject…", "Recusar…")) { [weak self] in self?.actions.rejectGate(row.task) })
        }
        if row.canAddGate { buttons.append(button(T("Add Gate", "Pôr portão")) { [weak self] in self?.actions.addGate(row.task) }) }
        if row.canEditDependencies {
            buttons.append(button(T("Dependencies…", "Dependências…")) { [weak self] in self?.actions.editDependencies(row.task) })
        }
        if !buttons.isEmpty { stack.addArrangedSubview(NSStackView(views: buttons)) }
        return stack
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, lines: Int = 1) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
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
    private let page: RunPageView
    private let book: RunBook
    private let live: (Dispatch) -> ContenderLive?
    /// The agents alive now in races and runs, and orchestration.maxAgents: the queue's line.
    public var slots: () -> (live: Int, max: Int) = { (0, 6) }
    /// orchestration.heartbeatMinutes: "stalled?" after that long without a sign of life.
    public var heartbeatMinutes: () -> Int = { 10 }

    public init(runID: String, book: RunBook, colors: RaceBoardColors, actions: RunPageActions, live: @escaping (Dispatch) -> ContenderLive?) {
        self.runID = runID
        self.book = book
        self.live = live
        page = RunPageView(colors: colors)
        page.actions = actions
        refresh()
    }

    public static func identity(for run: String) -> String { "run:\(run)" }
    public var identity: String { Self.identity(for: runID) }
    public var view: NSView { page }
    public var hasUnsavedChanges: Bool { false }
    public var colors: RaceBoardColors {
        get { page.colors }
        set { page.colors = newValue; refresh() }
    }

    public func refresh() {
        guard let run = try? book.run(runID) else { return }
        let tasks = (try? book.tasks(of: runID)) ?? []
        let dispatches = (try? book.dispatches(of: runID)) ?? []
        let now = Date()
        let messages: [RunMessage] = (try? book.store.all(.messages, parent: runID)) ?? []
        page.show(run: run, summary: RunRows.summary(run: run, dispatches: dispatches, now: now),
                  rows: RunRows.make(run: run, tasks: tasks, dispatches: dispatches, live: live, now: now,
                                     maxAgents: slots().max, liveAgents: slots().live, heartbeatMinutes: heartbeatMinutes()),
                  inbox: RunRows.inbox(messages, tasks: tasks, dispatches: dispatches))
        if title != run.name {
            title = run.name
            onChange?()
        }
    }

    public func focus() { page.window?.makeFirstResponder(page) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() { onClose?() }
}
