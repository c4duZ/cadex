import AppKit
import Strings

/// Who coordinates a new run (docs/spec/orchestration.md "Execuções"; plan 24 D1 and D2).
public enum RunMode: Int, Equatable, Sendable {
    /// The owner dispatches each task.
    case owner
    /// The owner coordinates, and a task that becomes ready is dispatched on its own.
    case ownerAuto
    /// An agent coordinates: it gets the goal and spawns the tasks.
    case agent
}

/// What "New Run" asks.
public struct NewRunValues: Equatable {
    public var name: String
    public var caps: Caps
    public var mode: RunMode
    /// Who runs the tasks on their own, and the coordinating agent (account, model).
    public var agent: AgentChoice
    /// The coordinating agent's goal (its first prompt).
    public var goal: String
}

/// "New Run": the name, the run's cap, who coordinates, the account and
/// model that run on their own, and the coordinating agent's goal.
@MainActor
public final class NewRunForm: NSView {
    let nameField = NSTextField()
    let budgetField = NSTextField()
    let minutesField = NSTextField()
    let mode = NSPopUpButton()
    let account = NSPopUpButton()
    let model = NSComboBox()
    let goalView = NSTextView()
    private let accounts: [AccountChoice]

    public init(caps: Caps, accounts: [AccountChoice] = []) {
        self.accounts = accounts.isEmpty ? [AccountChoice(title: "~/.claude", dir: nil)] : accounts
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 330))
        nameField.placeholderString = T("Run name", "Nome da execução")
        budgetField.stringValue = String(format: "%.2f", caps.budgetUsd)
        minutesField.stringValue = "\(caps.maxMinutes)"
        for title in [T("You: you dispatch each task", "Você: você despacha cada tarefa"),
                      T("You: ready tasks start on their own", "Você: as tarefas prontas começam sozinhas"),
                      T("An agent: it plans the goal into tasks", "Um agente: ele divide o objetivo em tarefas")] {
            mode.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        mode.target = self
        mode.action = #selector(modeChanged)
        for title in AccountChoice.titles(self.accounts) { account.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        model.addItems(withObjectValues: AccountChoice.models.map { $0.isEmpty ? T("default", "padrão") : $0 })
        model.selectItem(at: 0)
        let goal = FormKit.textArea(goalView, height: 90)
        FormKit.stack([FormKit.labeled(T("Name", "Nome"), nameField), FormKit.labeled(T("Cap (US$)", "Teto (US$)"), budgetField, width: 80),
                       FormKit.labeled(T("Cap (min)", "Teto (min)"), minutesField, width: 80),
                       FormKit.labeled(T("Coordinated by", "Coordenada por"), mode),
                       FormKit.labeled(T("Agents' account", "Conta dos agentes"), account), FormKit.labeled(T("Model", "Modelo"), model, width: 140),
                       NSTextField(labelWithString: T("Goal (the coordinating agent's prompt)", "Objetivo (o prompt do agente coordenador)")), goal], in: self)
        goal.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        modeChanged()
    }

    required init?(coder: NSCoder) { nil }
    public var firstField: NSView { nameField }

    @objc private func modeChanged() {
        let chosen = RunMode(rawValue: mode.indexOfSelectedItem) ?? .owner
        account.isEnabled = chosen != .owner
        model.isEnabled = chosen != .owner
        goalView.isEditable = chosen == .agent
    }

    /// What the owner chose; a cap that does not read keeps `fallback`'s.
    public func values(fallback: Caps) -> NewRunValues {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let budget = Double(budgetField.stringValue.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } ?? fallback.budgetUsd
        let minutes = Int(minutesField.stringValue).flatMap { $0 > 0 ? $0 : nil } ?? fallback.maxMinutes
        let typed = model.stringValue.trimmingCharacters(in: .whitespaces)
        let agent = AgentChoice(account: accounts[max(0, account.indexOfSelectedItem)].dir, model: typed == T("default", "padrão") ? "" : typed)
        return NewRunValues(name: name.isEmpty ? "run" : name, caps: Caps(budgetUsd: budget, maxMinutes: minutes),
                            mode: RunMode(rawValue: mode.indexOfSelectedItem) ?? .owner, agent: agent, goal: goalView.string)
    }

    /// As the owner would fill it (the run's test in the app); an account not offered is skipped.
    public func fill(name: String, mode chosen: RunMode = .owner, account dir: String? = nil, model name2: String = "", goal: String = "",
                     budgetUsd: Double? = nil, maxMinutes: Int? = nil) {
        nameField.stringValue = name
        mode.selectItem(at: chosen.rawValue)
        if let index = accounts.firstIndex(where: { $0.dir == dir }) { account.selectItem(at: index) }
        model.stringValue = name2
        goalView.string = goal
        if let budgetUsd { budgetField.stringValue = String(budgetUsd) }
        if let maxMinutes { minutesField.stringValue = "\(maxMinutes)" }
        modeChanged()
    }
}
