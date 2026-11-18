import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The work's tree, the left column (docs/spec/sidebar.md; the Sidebar mockup; plan 27 phase B):
/// "New task ⌘N" and the filter on top; each project folding, with its tasks (a task's own
/// terminals under the chosen one) and the terminals in its own folder; "+ Add project"; the foot
/// with Automations and Archive & history. Every button runs a command by id (ADR 0005); a row says
/// what was picked (`onPick`) and the app shows it.
@MainActor
public final class WorkTreeView: NSView {
    typealias S = DesignTokens.Sidebar
    public var onPick: ((WorkTreePick) -> Void)?
    /// A task's right click: the app's menu for it (each entry runs a command), shown at the row.
    public var menuFor: ((String) -> [MenuEntry])?
    /// The foot's Automations line ("2 on · next 09:00"), from the app.
    public var automationsDetail = "" { didSet { if automationsDetail != oldValue { render() } } }
    /// The foot's Projects line: how many (plan 34 B).
    public var projectsDetail = "" { didSet { if projectsDetail != oldValue { render() } } }
    /// The foot's line whose page shows ("projects", "automations"), lit; nil, none.
    public var footChosen: String? { didSet { if footChosen != oldValue { render() } } }
    private let run: (String) -> Void
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private let foot = NSStackView()
    private(set) var projects: [WorkTreeProject] = []
    /// What is chosen: a task's folder or a terminal's id.
    private(set) var chosen: WorkTreePick?
    private var folded: Set<String> = []
    private let newTaskShortcut: String?
    private let archiveShortcut: String?

    public init(newTaskShortcut: String?, archiveShortcut: String? = nil, run: @escaping (String) -> Void) {
        self.run = run
        self.newTaskShortcut = newTaskShortcut
        self.archiveShortcut = archiveShortcut
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = S.bg.cgColor
        let top = buildTop()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(S.listPadding.left), bottom: 0, right: UILooks.pt(S.listPadding.right))
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(list)
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        foot.orientation = .vertical
        foot.alignment = .leading
        foot.spacing = UILooks.pt(S.Foot.gap)
        foot.edgeInsets = NSEdgeInsets(top: UILooks.pt(S.Foot.padding.top), left: UILooks.pt(S.Foot.padding.left),
                                       bottom: UILooks.pt(S.Foot.padding.bottom), right: UILooks.pt(S.Foot.padding.right))
        let footLine = NSView()
        footLine.wantsLayer = true
        footLine.layer?.backgroundColor = S.Foot.borderTop.cgColor
        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = S.borderRight.cgColor
        for view in [top, scroll, footLine, foot, border] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let hairline = DesignTokens.Stroke.hairline
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor),
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            footLine.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            footLine.leadingAnchor.constraint(equalTo: leadingAnchor),
            footLine.trailingAnchor.constraint(equalTo: trailingAnchor),
            footLine.heightAnchor.constraint(equalToConstant: hairline),
            foot.topAnchor.constraint(equalTo: footLine.bottomAnchor),
            foot.leadingAnchor.constraint(equalTo: leadingAnchor),
            foot.trailingAnchor.constraint(equalTo: trailingAnchor),
            foot.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: hairline),
            list.topAnchor.constraint(equalTo: document.topAnchor),
            list.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            // The document pinned to the scroll's top-left and as tall as the list: left to its
            // autoresizing frame, it kept a height of nothing and cut the rows (seen 2026-11-17).
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.bottomAnchor.constraint(equalTo: list.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkTreeView is created in code") }

    override public var mouseDownCanMoveWindow: Bool { false }

    /// The tree again, and what is chosen.
    public func show(_ projects: [WorkTreeProject], chosen: WorkTreePick?) {
        guard projects != self.projects || chosen != self.chosen else { return }
        self.projects = projects
        self.chosen = chosen
        render()
    }

    private func render() {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for project in projects { addProject(project) }
        let add = WorkTreeRows.addProject(T("Add project", "Adicionar projeto"))
        add.onPress = { [weak self] in self?.run("project.new") }
        place(add)
        foot.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Projects and Automations (plan 34 B): Archive & history went into each project's
        // Sessions; Automations opens its page, empty or not (it ran a list that was off).
        let projects = WorkTreeRows.foot(.folders, T("Projects", "Projetos"), detail: projectsDetail)
        projects.onPress = { [weak self] in self?.run("project.show-all") }
        projects.isChosen = footChosen == "projects"
        let automations = WorkTreeRows.foot(.clock, T("Automations", "Automações"), detail: automationsDetail)
        automations.onPress = { [weak self] in self?.run("orchestration.show-automations") }
        automations.isChosen = footChosen == "automations"
        for row in [projects, automations] {
            foot.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: foot.widthAnchor, constant: -UILooks.pt(S.Foot.padding.left + S.Foot.padding.right)).isActive = true
        }
    }

    private func addProject(_ project: WorkTreeProject) {
        let isFolded = folded.contains(project.id)
        let header = WorkTreeRows.project(project, folded: isFolded) { [weak self] in self?.toggle(project.id) }
        header.isChosen = chosen == .project(project.id)
        header.onPress = { [weak self] in self?.onPick?(.project(project.id)) }
        place(header)
        guard !isFolded else { return spacing(S.Project.marginBottom) }
        for task in project.tasks {
            let isChosen = chosen == .task(task.id) || task.terminals.contains { chosen == .terminal($0.id) }
            // The chosen task's terminals sit inside its box, under the meta line (the mockup).
            let row = WorkTreeRows.task(task, terminals: isChosen ? task.terminals.map(terminalRow) : [])
            row.isChosen = isChosen
            row.onPress = { [weak self] in self?.onPick?(.task(task.id)) }
            row.onMenu = { [weak self, weak row] point in
                guard let self, let row, let entries = self.menuFor?(task.id), !entries.isEmpty else { return }
                PopupMenu.show(entries, at: point, in: row)
            }
            place(row)
            spacing(S.TaskRow.marginBottom)
        }
        // The project's own terminals as the mockup's rows: a one-line chip under the project read
        // as a stray tag next to the drawing (owner, 2026-11-17).
        for terminal in project.terminals {
            var line = WorkTreeTask(id: terminal.id, name: terminal.title, state: terminal.state ?? .idle, agent: terminal.detail)
            line.waiting = terminal.waiting
            line.age = terminal.age
            let row = WorkTreeRows.task(line)
            row.isChosen = chosen == .terminal(terminal.id)
            row.onPress = { [weak self] in self?.onPick?(.terminal(terminal.id)) }
            place(row)
            spacing(S.TaskRow.marginBottom)
        }
        spacing(S.Project.marginBottom)
    }

    private func terminalRow(_ terminal: WorkTreeTerminal) -> WorkTreeRow {
        let row = WorkTreeRows.terminal(terminal)
        row.isChosen = chosen == .terminal(terminal.id)
        row.onPress = { [weak self] in self?.onPick?(.terminal(terminal.id)) }
        return row
    }

    /// A project's header folds it; its terminals and tasks stay as they were.
    private func toggle(_ id: String) {
        if folded.remove(id) == nil { folded.insert(id) }
        render()
    }

    /// A row across the list; `indent` moves it right (a task's terminals, components.sidebar.terminalRow.block).
    private func place(_ row: NSView, indent: CGFloat = 0) {
        let item: NSView
        if indent > 0 {
            let box = NSStackView(views: [row])
            box.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(indent), bottom: 0, right: 0)
            item = box
        } else {
            item = row
        }
        list.addArrangedSubview(item)
        item.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -UILooks.pt(S.listPadding.left + S.listPadding.right)).isActive = true
    }

    private func spacing(_ points: CGFloat) {
        guard let last = list.arrangedSubviews.last else { return }
        list.setCustomSpacing(UILooks.pt(points), after: last)
    }

    private func buildTop() -> NSView {
        typealias N = S.NewTask
        let title = WorkTreeRows.label(T("New task", "Nova tarefa"), size: DesignTokens.FontSize.body, weight: N.weight, color: DesignTokens.Color.textPrimary)
        var views: [NSView] = [WorkTreeRows.icon(.plus, size: N.Plus.size, color: N.Plus.color), title]
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        views.append(spacer)
        if let newTaskShortcut { views.append(WorkTreeRows.label(newTaskShortcut, size: N.Kbd.fontSize, color: N.Kbd.color)) }
        let newTask = WorkTreeRow(views: views)
        newTask.spacing = UILooks.pt(N.gap)
        newTask.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(N.padding.left), bottom: 0, right: UILooks.pt(N.padding.right))
        newTask.wantsLayer = true
        newTask.layer?.backgroundColor = N.bg.cgColor
        newTask.layer?.borderColor = N.border.cgColor
        newTask.layer?.borderWidth = DesignTokens.Stroke.hairline
        newTask.layer?.cornerRadius = UILooks.pt(N.radius)
        newTask.heightAnchor.constraint(equalToConstant: UILooks.pt(N.height)).isActive = true
        newTask.onPress = { [weak self] in self?.run("worktrees.new-task") }
        newTask.setAccessibilityRole(.button)
        newTask.setAccessibilityLabel(T("New task", "Nova tarefa"))
        let filter = WorkTreeRow(views: [WorkTreeRows.icon(.funnelSimple, size: S.Filter.icon, color: S.Filter.color)])
        filter.alignment = .centerY
        filter.distribution = .gravityAreas
        filter.radius = S.Filter.radius
        filter.widthAnchor.constraint(equalToConstant: UILooks.pt(S.Filter.size)).isActive = true
        filter.heightAnchor.constraint(equalToConstant: UILooks.pt(S.Filter.size)).isActive = true
        filter.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt((S.Filter.size - S.Filter.icon) / 2), bottom: 0, right: 0)
        filter.onPress = { [weak self] in self?.run("sidebar.find") }
        filter.toolTip = T("Find a project, task or terminal", "Achar um projeto, tarefa ou terminal")
        filter.setAccessibilityRole(.button)
        filter.setAccessibilityLabel(filter.toolTip)
        let top = NSStackView(views: [newTask, filter])
        // Top-aligned so the insets hold: centred, the button sat 2 pt high (measured 2026-11-17).
        top.alignment = .top
        top.spacing = UILooks.pt(S.Top.gap)
        top.edgeInsets = NSEdgeInsets(top: UILooks.pt(S.Top.padding.top), left: UILooks.pt(S.Top.padding.left),
                                      bottom: UILooks.pt(S.Top.padding.bottom), right: UILooks.pt(S.Top.padding.right))
        return top
    }

    /// What the tree shows, for tests.
    var rowTitles: [String] {
        list.arrangedSubviews.flatMap { item -> [String] in
            // An indented row sits in a box of its own; a chosen task holds its terminals' rows.
            guard let row = item as? WorkTreeRow ?? (item as? NSStackView)?.arrangedSubviews.first as? WorkTreeRow else { return [] }
            let inner = Self.rows(in: row).filter { $0.accessibilityRole() != .disclosureTriangle }
            return [row.accessibilityLabel() ?? ""] + inner.compactMap { $0.accessibilityLabel() }
        }
    }

    private static func rows(in view: NSView) -> [WorkTreeRow] {
        view.subviews.flatMap { sub in (sub as? WorkTreeRow).map { [$0] } ?? rows(in: sub) }
    }
}

/// Top-down coordinates for the list's document.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
