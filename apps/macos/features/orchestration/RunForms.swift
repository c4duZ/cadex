import AppKit
import Strings

/// The run's sheets (plan 24 D1): "New Run" (name and caps), "Add Task"
/// (title, specification, dependencies) and the dispatch's (account, model,
/// starting branch). The app shows each in an NSAlert with what will run
/// in its text, and reads it back.
@MainActor
enum FormKit {
    static func labeled(_ title: String, _ control: NSView, width: CGFloat = 260) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
        return NSStackView(views: [label, control])
    }

    static func stack(_ views: [NSView], in host: NSView) {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor), stack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            stack.topAnchor.constraint(equalTo: host.topAnchor),
        ])
    }

    /// A plain-text editor: no smart quotes or dashes, the spec goes as typed.
    static func textArea(_ view: NSTextView, height: CGFloat) -> NSScrollView {
        view.isRichText = false
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.autoresizingMask = [.width]
        view.minSize = NSSize(width: 0, height: height)
        view.isVerticallyResizable = true
        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }
}

/// "New Run": the name and the run's cap; the repository and the
/// coordinator (the owner, in D1) are the app's.
@MainActor
public final class NewRunForm: NSView {
    let nameField = NSTextField()
    let budgetField = NSTextField()
    let minutesField = NSTextField()

    public init(caps: Caps) {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 100))
        nameField.placeholderString = T("Run name", "Nome da execução")
        budgetField.stringValue = String(format: "%.2f", caps.budgetUsd)
        minutesField.stringValue = "\(caps.maxMinutes)"
        FormKit.stack([FormKit.labeled(T("Name", "Nome"), nameField), FormKit.labeled(T("Cap (US$)", "Teto (US$)"), budgetField, width: 80),
                       FormKit.labeled(T("Cap (min)", "Teto (min)"), minutesField, width: 80)], in: self)
    }

    required init?(coder: NSCoder) { nil }
    public var firstField: NSView { nameField }

    /// The name (empty: "run") and the caps (a field that does not read keeps `fallback`'s).
    public func values(fallback: Caps) -> (name: String, caps: Caps) {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let budget = Double(budgetField.stringValue.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } ?? fallback.budgetUsd
        let minutes = Int(minutesField.stringValue).flatMap { $0 > 0 ? $0 : nil } ?? fallback.maxMinutes
        return (name.isEmpty ? "run" : name, Caps(budgetUsd: budget, maxMinutes: minutes))
    }

    public func fill(name: String) { nameField.stringValue = name }
}

/// "Add Task": the title, the specification (the agent's prompt) and one
/// checkbox per task of the run it may wait for.
@MainActor
public final class AddTaskForm: NSView {
    let titleField = NSTextField()
    let specView = NSTextView()
    private let others: [RunTask]
    private var boxes: [NSButton] = []

    public init(others: [RunTask]) {
        self.others = others
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 260 + CGFloat(min(others.count, 8)) * 22))
        titleField.placeholderString = T("Title", "Título")
        var views: [NSView] = [FormKit.labeled(T("Title", "Título"), titleField),
                               NSTextField(labelWithString: T("Specification (the agent's prompt)", "Especificação (o prompt do agente)")),
                               FormKit.textArea(specView, height: 160)]
        if !others.isEmpty { views.append(NSTextField(labelWithString: T("Starts after", "Começa depois de"))) }
        for task in others {
            let box = NSButton(checkboxWithTitle: task.title, target: nil, action: nil)
            boxes.append(box)
            views.append(box)
        }
        FormKit.stack(views, in: self)
        if let scroll = specView.enclosingScrollView { scroll.widthAnchor.constraint(equalTo: widthAnchor).isActive = true }
    }

    required init?(coder: NSCoder) { nil }
    public var firstField: NSView { titleField }

    public func values() -> (title: String, spec: String, dependsOn: [String]) {
        let deps = zip(others, boxes).filter { $0.1.state == .on }.map(\.0.id)
        return (titleField.stringValue.trimmingCharacters(in: .whitespaces), specView.string, deps)
    }

    /// As the owner would type it (the run's test in the app, `../../app/RunPerfHooks.swift`).
    public func fill(title: String, spec: String, after: [String]) {
        titleField.stringValue = title
        specView.string = spec
        for (task, box) in zip(others, boxes) { box.state = after.contains(task.title) ? .on : .off }
    }
}

/// The dispatch's sheet: who runs the task (account, model), where (a new
/// worktree from a branch, or an idle terminal the owner picks), and the
/// whole prompt, scrollable, with the permission mode it runs in.
@MainActor
public final class DispatchForm: NSView {
    /// An idle terminal to offer: what the menu says and its shell's pid.
    public struct Idle: Equatable {
        public let title: String
        public let shell: Int32
        public init(title: String, shell: Int32) {
            self.title = title
            self.shell = shell
        }
    }

    private let accounts: [NewRaceForm.Account]
    private let bases: [String]
    private let idle: [Idle]
    let account = NSPopUpButton()
    let model = NSComboBox()
    let place = NSPopUpButton()
    let base = NSPopUpButton()
    let promptView = NSTextView()

    public init(accounts: [NewRaceForm.Account], bases: [String], idle: [Idle], prompt: String, permissions: String) {
        self.accounts = accounts.isEmpty ? [NewRaceForm.Account(title: "~/.claude", dir: nil)] : accounts
        self.bases = bases
        self.idle = idle
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 300))
        for title in NewRaceForm.titles(self.accounts) { account.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        model.addItems(withObjectValues: NewRaceForm.models.map { $0.isEmpty ? T("default", "padrão") : $0 })
        model.selectItem(at: 0)
        place.menu?.addItem(NSMenuItem(title: T("A new worktree and tab", "Uma worktree e aba novas"), action: nil, keyEquivalent: ""))
        for terminal in idle { place.menu?.addItem(NSMenuItem(title: terminal.title, action: nil, keyEquivalent: "")) }
        place.target = self
        place.action = #selector(placeChanged)
        for name in bases { base.menu?.addItem(NSMenuItem(title: name, action: nil, keyEquivalent: "")) }
        promptView.string = prompt
        let scroll = FormKit.textArea(promptView, height: 110)
        promptView.isEditable = false
        FormKit.stack([FormKit.labeled(T("Account", "Conta"), account), FormKit.labeled(T("Model", "Modelo"), model, width: 140),
                       FormKit.labeled(T("Runs in", "Roda em"), place), FormKit.labeled(T("From branch", "Da branch"), base),
                       NSTextField(labelWithString: T("Prompt (the task's specification) · permissions: ", "Prompt (a especificação da tarefa) · permissões: ") + permissions),
                       scroll], in: self)
        scroll.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    @objc private func placeChanged() { base.isEnabled = place.indexOfSelectedItem <= 0 }

    public func request(task: String) -> DispatchRequest {
        let chosen = accounts[max(0, account.indexOfSelectedItem)]
        let typed = model.stringValue.trimmingCharacters(in: .whitespaces)
        let name = typed == T("default", "padrão") ? "" : typed
        let branch = bases.indices.contains(base.indexOfSelectedItem) ? bases[base.indexOfSelectedItem] : ""
        let reuse = place.indexOfSelectedItem > 0 ? idle[place.indexOfSelectedItem - 1].shell : nil
        return DispatchRequest(task: task, agent: AgentChoice(account: chosen.dir, model: name), base: branch, reuseShell: reuse)
    }

    /// As the owner would choose (the run's test in the app); an account not
    /// offered is skipped; `reuse`, the first idle terminal.
    public func fill(account dir: String?, model name: String, reuse: Bool = false) {
        if let index = accounts.firstIndex(where: { $0.dir == dir }) { account.selectItem(at: index) }
        model.stringValue = name
        if reuse && !idle.isEmpty {
            place.selectItem(at: 1)
            placeChanged()
        }
    }
}

/// orchestration.set-dependencies: one checkbox per other task of the run,
/// the current ones checked.
@MainActor
public final class DependenciesForm: NSView {
    private let others: [RunTask]
    private var boxes: [NSButton] = []

    public init(others: [RunTask], checked: [String]) {
        self.others = others
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: CGFloat(max(1, min(others.count, 12))) * 24))
        for task in others {
            let box = NSButton(checkboxWithTitle: task.title, target: nil, action: nil)
            box.state = checked.contains(task.id) ? .on : .off
            boxes.append(box)
        }
        FormKit.stack(boxes.isEmpty ? [NSTextField(labelWithString: T("No other task in this run.", "Nenhuma outra tarefa nesta execução."))] : boxes, in: self)
    }

    required init?(coder: NSCoder) { nil }

    public func values() -> [String] { zip(others, boxes).filter { $0.1.state == .on }.map(\.0.id) }

    /// As the owner would check them (the run's test in the app), by title.
    public func fill(after titles: [String]) {
        for (task, box) in zip(others, boxes) { box.state = titles.contains(task.title) ? .on : .off }
    }
}
