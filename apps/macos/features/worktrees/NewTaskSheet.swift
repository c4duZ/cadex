import AppKit
import Menus
import Strings
import UILooks

/// What the sheet needs from the app: the agents it can offer, the notes for a request (the old
/// questions as lines), the race's cap, and what Start and Cancel do.
@MainActor
public struct NewTaskSheetActions {
    public var project = ""
    /// The title's "in <project> ▾": the projects it can switch to (open ones, recent ones) and the
    /// switch, which the app does by opening the sheet again there with the same request.
    public var projects: () -> [(name: String, folder: String)] = { [] }
    public var switchProject: (String, NewTaskRequest) -> Void = { _, _ in }
    public var openFolder: () -> Void = {}
    /// Every agent the "+" and a row's menu offer (accounts here, then the machines).
    public var choices: () -> [NewTaskAgent] = { [] }
    public var notes: (NewTaskRequest) -> [NewTaskNote] = { _ in [] }
    public var cap: (budget: Double, minutes: Int) = (1, 20)
    public var start: (NewTaskRequest) -> Void = { _ in }
    public var cancel: () -> Void = {}

    public init() {}
}

/// The New Task sheet, ⌘N (plan 29 phase B; the NewTask mockup): over the window with the
/// scrim, a 640 pt panel: the request, WHERE, WHO DOES IT, the notes, and Start task or Start
/// race. One agent is a task, two or more a race in copies. ⌘↩ starts, Esc cancels.
@MainActor
public final class NewTaskSheet: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    public private(set) var request: NewTaskRequest
    private let actions: NewTaskSheetActions
    private let panel = NewTaskClickable()
    let prompt = NSTextView()
    private let folderOption = NewTaskOption(title: T("In the project's folder", "Na pasta do projeto"),
                                             note: T("Works on your files, on main. One at a time.", "Mexe nos seus arquivos, no main. Um de cada vez."),
                                             withBranch: false)
    private let copyOption = NewTaskOption(title: T("Separate copy · branch ", "Cópia separada · branch "),
                                           note: T("Runs in parallel; you review and merge after.", "Roda em paralelo; você revisa e junta depois."),
                                           withBranch: true)
    private let agentsBox = NSStackView()
    private let notesBox = NSStackView()
    private var start: NSButton?
    private var keys: Any?
    /// A note that stops Start (its words, for the button's tip).
    private var blocked: String?

    public init(request: NewTaskRequest, actions: NewTaskSheetActions) {
        self.request = request
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = DesignTokens.Sheet.scrim.cgColor
        build()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("NewTaskSheet is created in code") }

    public override var isFlipped: Bool { true }
    /// The scrim takes the clicks: nothing behind the sheet is reachable while it shows.
    public override func mouseDown(with event: NSEvent) {}

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keys { NSEvent.removeMonitor(keys); self.keys = nil }
        guard window != nil else { return }
        window?.makeFirstResponder(prompt)
        // ⌘↩ and Esc wherever the focus is in the sheet (the request, the branch).
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.keyCode == 53 { self.actions.cancel(); return nil }
            if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.command) { self.tryStart(); return nil }
            return event
        }
    }

    public override func removeFromSuperview() {
        if let keys { NSEvent.removeMonitor(keys); self.keys = nil }
        super.removeFromSuperview()
    }

    // MARK: Building

    private func build() {
        panel.box(bg: DesignTokens.Sheet.bg, border: DesignTokens.Sheet.border, radius: DesignTokens.Sheet.radius)
        if let shadow = DesignTokens.Sheet.shadow.first {
            panel.layer?.masksToBounds = false
            panel.layer?.shadowColor = shadow.color.cgColor
            panel.layer?.shadowOpacity = 1
            panel.layer?.shadowRadius = UILooks.pt(shadow.layerRadius)
            panel.layer?.shadowOffset = shadow.offset
        }
        typealias F = NT.Frame
        let title = newTaskLabel(T("New task", "Nova tarefa"), size: DesignTokens.Sheet.Title.fontSize, color: DesignTokens.Color.textPrimary,
                                 weight: DesignTokens.Sheet.Title.weight)
        let projectLabel = newTaskLabel(T("in \(actions.project) ▾", "em \(actions.project) ▾"), size: DesignTokens.FontSize.body, color: NT.Subtitle.color)
        let project = NewTaskClickable()
        project.hold(projectLabel, padding: NSEdgeInsetsZero)
        project.onPress = { [weak self, weak project] in if let project { self?.pickProject(below: project) } }
        let head = NSStackView(views: [title, project])
        head.spacing = UILooks.pt(F.headerGap)
        let options = NSStackView(views: [folderOption, copyOption])
        options.spacing = UILooks.pt(NT.Option.gap)
        options.distribution = .fillEqually
        folderOption.onPress = { [weak self] in self?.choose(copy: false) }
        copyOption.onPress = { [weak self] in self?.choose(copy: true) }
        copyOption.branch.delegate = self
        copyOption.branch.stringValue = request.branch
        agentsBox.orientation = .vertical
        agentsBox.alignment = .leading
        agentsBox.spacing = UILooks.pt(NT.AgentRow.listGap)
        notesBox.orientation = .vertical
        notesBox.alignment = .leading
        notesBox.spacing = UILooks.pt(NT.AgentRow.listGap)
        let column = NSStackView(views: [head, promptBox(), sectionLabel(T("WHERE", "ONDE")), options,
                                         sectionLabel(T("WHO DOES IT", "QUEM FAZ")), agentsBox, notesBox, footer()])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.setCustomSpacing(UILooks.pt(F.headerBottom), after: head)
        column.setCustomSpacing(UILooks.pt(NT.Footer.marginTop), after: notesBox)
        column.edgeInsets = NSEdgeInsets(top: UILooks.pt(F.headerTop), left: 0, bottom: 0, right: 0)
        panel.hold(column, padding: NSEdgeInsetsZero)
        let inset = UILooks.pt(F.inset)
        for view in [head, column.arrangedSubviews[1], options, agentsBox, notesBox] {
            view.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: inset).isActive = true
            view.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -inset).isActive = true
        }
        for label in column.arrangedSubviews where label.identifier?.rawValue == "label" {
            label.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: inset).isActive = true
        }
        column.arrangedSubviews.last?.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Sheet.newTaskWidth)),
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(F.top)),
        ])
    }

    /// "WHERE": the section's small title, with its room above and below.
    private func sectionLabel(_ text: String) -> NSView {
        typealias L = NT.Label
        let label = newTaskLabel(text, size: L.fontSize, color: L.color, weight: L.weight, tracking: L.tracking)
        let box = NSView()
        box.identifier = NSUserInterfaceItemIdentifier("label")
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor), label.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: UILooks.pt(NT.Frame.labelTop)),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -UILooks.pt(NT.Frame.labelBottom)),
        ])
        return box
    }

    /// The request: several lines, at least the mockup's height.
    private func promptBox() -> NSView {
        typealias Fd = NT.Field
        let box = NewTaskClickable()
        box.box(bg: Fd.bg, border: Fd.border, radius: Fd.radius)
        box.onPress = { [weak self] in self.map { $0.window?.makeFirstResponder($0.prompt) } }
        prompt.isRichText = false
        prompt.drawsBackground = false
        prompt.font = UILooks.font(DesignTokens.FontSize.body)
        prompt.textColor = DesignTokens.Color.textPrimary
        prompt.insertionPointColor = DesignTokens.Color.textPrimary
        prompt.textContainerInset = .zero
        prompt.textContainer?.lineFragmentPadding = 0
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = Fd.lineHeight
        prompt.defaultParagraphStyle = style
        prompt.typingAttributes[.paragraphStyle] = style
        prompt.string = request.prompt
        prompt.delegate = self
        prompt.isVerticallyResizable = true
        prompt.setAccessibilityLabel(T("What the agent should do", "O que o agente deve fazer"))
        box.hold(prompt, padding: Fd.padding)
        box.heightAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(Fd.minHeight)).isActive = true
        return box
    }

    private func footer() -> NSView {
        typealias Ft = NT.Footer
        let note = newTaskLabel(T("Opens as terminals in the sidebar under \(actions.project)", "Abre como terminais na barra lateral em \(actions.project)"),
                                size: Ft.fontSize, color: Ft.color)
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let cancel = DesignButton.make(T("Cancel", "Cancelar"), .secondary, height: Ft.buttonHeight) { [weak self] in self?.actions.cancel() }
        let start = DesignButton.make(NewTaskWords.startTitle(request), .primary, height: Ft.buttonHeight) { [weak self] in self?.tryStart() }
        self.start = start
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [note, spacer, cancel, start])
        row.spacing = UILooks.pt(Ft.gap)
        let pad = Ft.padding
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(pad.top), left: UILooks.pt(pad.left), bottom: UILooks.pt(pad.bottom), right: UILooks.pt(pad.right))
        // The line on top, a view of its own (a layer put at y 0 of the stack went to its bottom).
        let box = NewTaskClickable()
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Ft.borderTop.cgColor
        for view in [line, row] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: box.topAnchor), line.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: box.trailingAnchor), line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            row.topAnchor.constraint(equalTo: line.bottomAnchor), row.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: box.trailingAnchor), row.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    // MARK: Showing the request

    private func refresh() {
        let race = request.isRace
        folderOption.show(chosen: !request.runsInCopy, enabled: !race)
        copyOption.show(chosen: request.runsInCopy, enabled: true)
        copyOption.branch.placeholderString = NewTaskWords.branch(from: request.prompt).isEmpty ? T("branch-name", "nome-do-branch") : NewTaskWords.branch(from: request.prompt)
        agentsBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, agent) in request.agents.enumerated() {
            let row = NewTaskAgentRow(index: index + 1, agent: agent)
            row.onPress = { [weak self, weak row] in if let row { self?.pickAgent(at: index, below: row) } }
            row.remove.target = self
            row.remove.action = #selector(removeAgent(_:))
            row.remove.tag = index
            agentsBox.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: agentsBox.widthAnchor).isActive = true
        }
        let add = NewTaskClickable()
        add.onPress = { [weak self, weak add] in if let add { self?.pickAgent(at: nil, below: add) } }
        add.hold(newTaskLabel(T("+ Add another agent", "+ Adicionar outro agente"), size: DesignTokens.FontSize.body, color: NT.AddAgent.color),
                 padding: NT.AddAgent.padding)
        agentsBox.addArrangedSubview(add)
        notesBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let given = actions.notes(request)
        blocked = given.first { $0.blocks }?.text
        var notes = given.map(noteLine)
        if race { notes.insert(raceNote(), at: 0) }
        notes.forEach { notesBox.addArrangedSubview($0); $0.widthAnchor.constraint(equalTo: notesBox.widthAnchor).isActive = true }
        notesBox.isHidden = notes.isEmpty
        if let start {
            // The styled title kept, only its words: `title` dropped the style and left white on white.
            let styled = NSMutableAttributedString(attributedString: start.attributedTitle)
            styled.mutableString.setString(NewTaskWords.startTitle(request))
            start.attributedTitle = styled
        }
        start?.isEnabled = request.missing == nil && blocked == nil
        start?.toolTip = request.missing ?? blocked
    }

    private func raceNote() -> NSView {
        typealias R = NT.RaceNote
        let box = NewTaskClickable()
        box.box(bg: R.bg, border: R.border, radius: R.radius)
        let text = NSTextField(wrappingLabelWithString: NewTaskWords.raceNote(agents: request.agents.count, budget: actions.cap.budget, minutes: actions.cap.minutes))
        text.font = UILooks.font(R.fontSize)
        text.textColor = R.color
        text.preferredMaxLayoutWidth = UILooks.pt(DesignTokens.Sheet.newTaskWidth - 2 * NT.Frame.inset - R.padding.left - R.padding.right)
        box.hold(text, padding: R.padding)
        return box
    }

    private func noteLine(_ note: NewTaskNote) -> NSView {
        let text = NSTextField(wrappingLabelWithString: note.text)
        text.font = UILooks.font(NT.Option.Note.fontSize)
        text.textColor = NT.Option.Note.color
        text.preferredMaxLayoutWidth = UILooks.pt(DesignTokens.Sheet.newTaskWidth - 2 * NT.Frame.inset)
        guard let title = note.action, let run = note.run else { return text }
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: UILooks.font(NT.Option.Note.fontSize), .foregroundColor: DesignTokens.Color.accentLink])
        let link = NewTaskClickable()
        link.onPress = run
        link.hold(button, padding: NSEdgeInsetsZero)
        let column = NSStackView(views: [text, link])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = UILooks.pt(NT.Option.textGap)
        return column
    }

    // MARK: Changes

    private func choose(copy: Bool) {
        guard !(request.isRace && !copy) else { return }
        request.separateCopy = copy
        refresh()
    }

    public func textDidChange(_ notification: Notification) {
        request.prompt = prompt.string
        refresh()
    }

    public func controlTextDidChange(_ obj: Notification) {
        request.branch = copyOption.branch.stringValue
        refresh()
    }

    @objc private func removeAgent(_ sender: NSButton) {
        guard request.agents.indices.contains(sender.tag) else { return }
        request.agents.remove(at: sender.tag)
        refresh()
    }

    /// A row's menu (another account or machine, the model) or the "+": add one.
    private func pickAgent(at index: Int?, below anchor: NSView) {
        let current = index.map { request.agents[$0] }
        var entries = actions.choices().map { choice in
            MenuEntry(choice.title, icon: current.map { $0.account == choice.account && $0.machine == choice.machine && $0.isCodex == choice.isCodex } == true ? .check : nil) { [weak self] in
                guard let self else { return }
                var picked = choice
                // The model goes with the agent's kind: Claude's names mean nothing to Codex.
                picked.model = current?.isCodex == choice.isCodex ? current?.model ?? "" : ""
                if let index { self.request.agents[index] = picked } else { self.request.agents.append(picked) }
                self.refresh()
            }
        }
        if let index, let current, !current.isCodex {
            entries.append(.separator)
            for model in NewTaskAgent.models {
                entries.append(MenuEntry(model.isEmpty ? T("Account's default model", "Modelo padrão da conta") : model.prefix(1).uppercased() + model.dropFirst(),
                                         icon: current.model == model ? .check : nil) { [weak self] in
                    self?.request.agents[index].model = model
                    self?.refresh()
                })
            }
        }
        PopupMenu.show(MenuEntry.tidy(entries), below: anchor)
    }

    /// The request given whole (the test instance's CADEX_PERF_NEW_TASK).
    public func fill(_ request: NewTaskRequest) {
        self.request = request
        prompt.string = request.prompt
        copyOption.branch.stringValue = request.branch
        refresh()
    }

    /// What the "+" offers (the test instance's fill picks from it).
    public var choices: [NewTaskAgent] { actions.choices() }

    /// The notes again (the tasks' folder changed).
    public func refreshNotes() { refresh() }

    /// Start, as the button.
    public func pressStart() { tryStart() }

    private func pickProject(below anchor: NSView) {
        request.prompt = prompt.string
        request.branch = copyOption.branch.stringValue
        let current = request
        var entries = actions.projects().map { project in
            MenuEntry(project.name, icon: project.name == actions.project ? .check : nil) { [weak self] in
                self?.actions.switchProject(project.folder, current)
            }
        }
        entries += [.separator, MenuEntry(T("Open Folder…", "Abrir pasta…")) { [weak self] in self?.actions.openFolder() }]
        PopupMenu.show(MenuEntry.tidy(entries), below: anchor)
    }

    private func tryStart() {
        request.prompt = prompt.string
        request.branch = copyOption.branch.stringValue
        guard request.missing == nil, blocked == nil else { return refresh() }
        actions.start(request)
    }
}
