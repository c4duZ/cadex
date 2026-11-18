import AppKit
import Strings
import UILooks

/// The run's sheets (plan 24 D1): "New Run" (name and caps), "Add Task"
/// (title, specification, dependencies) and the dispatch's (account, model,
/// starting branch). The app shows each in a FrameSheet (plan 31 B; it was
/// the system alert) with what will run in its text, and reads it back.
@MainActor
enum FormKit {
    /// The label over the control, the control in the frame's box (plan 31 B).
    static func labeled(_ title: String, _ control: NSView, width: CGFloat = 0) -> NSView {
        FrameField.labeled(title, styled(control))
    }

    /// A control in the frame's face by its kind; a row of them shares the row.
    static func styled(_ control: NSView) -> NSView {
        switch control {
        case let combo as NSComboBox: return FrameField.combo(combo)
        case let popup as NSPopUpButton: return FrameField.popup(popup)
        case let button as NSButton: return FrameField.check(button)
        case let field as NSTextField where field.isEditable: return FrameField.field(field)
        case let row as NSStackView where row.orientation == .horizontal:
            let parts = row.arrangedSubviews
            parts.forEach { $0.removeFromSuperview() }
            return FrameField.row(parts.map(styled))
        default: return control
        }
    }

    /// The form's column, filling the host, its height the form's.
    static func stack(_ views: [NSView], in host: NSView) {
        let stack = FrameField.column(views.map { $0 is NSButton || $0 is NSPopUpButton ? styled($0) : $0 }, gap: DesignTokens.NewTask.Frame.labelTop)
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor), stack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            stack.topAnchor.constraint(equalTo: host.topAnchor), stack.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        for view in stack.arrangedSubviews where !(view is NSButton) { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }

    /// A plain-text editor: no smart quotes or dashes, the spec goes as typed.
    static func textArea(_ view: NSTextView, height: CGFloat) -> NSView {
        FrameField.area(view, height: height)
    }
}

/// "Add Task": the title, the specification (the agent's prompt) and one
/// checkbox per task of the run it may wait for.
@MainActor
public final class AddTaskForm: NSView {
    let titleField = NSTextField()
    let specView = NSTextView()
    /// docs/spec/orchestration.md: "e, se o dono quiser, um portão".
    let gateBox = NSButton(checkboxWithTitle: T("Gate: wait for my approval before it starts", "Portão: esperar minha aprovação antes de começar"),
                           target: nil, action: nil)
    private let others: [RunTask]
    private var boxes: [NSButton] = []

    public init(others: [RunTask]) {
        self.others = others
        super.init(frame: .zero)
        titleField.placeholderString = T("Title", "Título")
        var views: [NSView] = [FormKit.labeled(T("Title", "Título"), titleField),
                               FrameField.labeled(T("Specification (the agent's prompt)", "Especificação (o prompt do agente)"),
                                                  FormKit.textArea(specView, height: 160))]
        if !others.isEmpty { views.append(FrameField.label(T("Starts after", "Começa depois de"))) }
        for task in others {
            let box = NSButton(checkboxWithTitle: task.title, target: nil, action: nil)
            boxes.append(box)
            views.append(box)
        }
        views.append(gateBox)
        FormKit.stack(views, in: self)
    }

    required init?(coder: NSCoder) { nil }
    public var firstField: NSView { titleField }

    public func values() -> (title: String, spec: String, dependsOn: [String], gate: Bool) {
        let deps = zip(others, boxes).filter { $0.1.state == .on }.map(\.0.id)
        return (titleField.stringValue.trimmingCharacters(in: .whitespaces), specView.string, deps, gateBox.state == .on)
    }

    /// As the owner would type it (the run's test in the app, `../../app/RunPerfHooks.swift`).
    public func fill(title: String, spec: String, after: [String], gate: Bool = false) {
        titleField.stringValue = title
        specView.string = spec
        gateBox.state = gate ? .on : .off
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

    private let accounts: [AccountChoice]
    private let bases: [String]
    private let idle: [Idle]
    let account = NSPopUpButton()
    let model = NSComboBox()
    let place = NSPopUpButton()
    let base = NSPopUpButton()
    let promptView = NSTextView()

    public init(accounts: [AccountChoice], bases: [String], idle: [Idle], prompt: String, permissions: String) {
        self.accounts = accounts.isEmpty ? [AccountChoice(title: "~/.claude", dir: nil)] : accounts
        self.bases = bases
        self.idle = idle
        super.init(frame: .zero)
        for title in AccountChoice.titles(self.accounts) { account.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        model.addItems(withObjectValues: AccountChoice.models.map { $0.isEmpty ? T("default", "padrão") : $0 })
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
                       FrameField.labeled(T("Prompt (the task's specification) · permissions: ", "Prompt (a especificação da tarefa) · permissões: ") + permissions, scroll)],
                      in: self)
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
        super.init(frame: .zero)
        for task in others {
            let box = NSButton(checkboxWithTitle: task.title, target: nil, action: nil)
            box.state = checked.contains(task.id) ? .on : .off
            boxes.append(box)
        }
        FormKit.stack(boxes.isEmpty ? [FrameField.text(T("No other task in this run.", "Nenhuma outra tarefa nesta execução."))] : boxes, in: self)
    }

    required init?(coder: NSCoder) { nil }

    public func values() -> [String] { zip(others, boxes).filter { $0.1.state == .on }.map(\.0.id) }

    /// As the owner would check them (the run's test in the app), by title.
    public func fill(after titles: [String]) {
        for (task, box) in zip(others, boxes) { box.state = titles.contains(task.title) ? .on : .off }
    }
}
