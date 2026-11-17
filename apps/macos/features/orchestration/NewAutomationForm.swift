import AppKit
import Strings

/// "New Automation" (docs/spec/orchestration.md "Automações"; plan 24 E):
/// the name, the prompt, the recurrence, where it runs (a new worktree each
/// time, or this folder), the account and model, the permission mode and
/// allowed tools, the caps, the subscription or the account's API key, and
/// what to do with a missed run. It is made off; the app shows the sheet.
@MainActor
public final class NewAutomationForm: NSView {
    let nameField = NSTextField()
    let promptView = NSTextView()
    let recurrence = NSPopUpButton()
    let timeField = NSTextField()
    let target = NSPopUpButton()
    let account = NSPopUpButton()
    let model = NSComboBox()
    let permission = NSPopUpButton()
    let toolsField = NSTextField()
    let budgetField = NSTextField()
    let minutesField = NSTextField()
    let subscription = NSButton(checkboxWithTitle: T("Use the subscription (not the account's API key)", "Usar a assinatura (não a chave de API da conta)"),
                                target: nil, action: nil)
    let missed = NSPopUpButton()
    private let accounts: [NewRaceForm.Account]
    private let repository: String?
    private let folder: String
    static let modes = ["default", "acceptEdits", "plan", "bypassPermissions"]

    /// `repository`: a git repository (a new worktree each run is offered);
    /// `folder`: the fixed folder offered (the window's).
    public init(accounts: [NewRaceForm.Account], repository: String?, folder: String, caps: Caps) {
        self.accounts = accounts.isEmpty ? [NewRaceForm.Account(title: "~/.claude", dir: nil)] : accounts
        self.repository = repository
        self.folder = folder
        super.init(frame: NSRect(x: 0, y: 0, width: 540, height: 470))
        nameField.placeholderString = T("Automation name", "Nome da automação")
        for title in [T("Weekdays at (HH:MM)", "Dias úteis às (HH:MM)"), T("Every day at (HH:MM)", "Todo dia às (HH:MM)"),
                      T("Every N hours", "A cada N horas"), T("Every N minutes", "A cada N minutos"),
                      T("Once at (yyyy-MM-dd HH:MM)", "Uma vez em (aaaa-MM-dd HH:MM)")] {
            recurrence.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        timeField.stringValue = "09:00"
        if let repository { target.menu?.addItem(NSMenuItem(title: T("A new worktree of ", "Uma worktree nova de ") + (repository as NSString).lastPathComponent, action: nil, keyEquivalent: "")) }
        target.menu?.addItem(NSMenuItem(title: T("This folder: ", "Esta pasta: ") + (folder as NSString).abbreviatingWithTildeInPath, action: nil, keyEquivalent: ""))
        for title in NewRaceForm.titles(self.accounts) { account.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: "")) }
        model.addItems(withObjectValues: NewRaceForm.models.map { $0.isEmpty ? T("default", "padrão") : $0 })
        model.selectItem(at: 0)
        Self.modes.forEach { permission.menu?.addItem(NSMenuItem(title: $0, action: nil, keyEquivalent: "")) }
        toolsField.placeholderString = T("Allowed tools, comma-separated (Read,Edit,Bash(git:*))", "Ferramentas permitidas, separadas por vírgula (Read,Edit,Bash(git:*))")
        budgetField.stringValue = String(format: "%.2f", caps.budgetUsd)
        minutesField.stringValue = "\(caps.maxMinutes)"
        for title in [T("Missed (Mac asleep or Cadex closed): run once on waking", "Perdida (Mac dormindo ou Cadex fechado): rodar uma vez ao acordar"),
                      T("Missed: skip it", "Perdida: pular")] {
            missed.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
        }
        let prompt = FormKit.textArea(promptView, height: 110)
        FormKit.stack([FormKit.labeled(T("Name", "Nome"), nameField), NSTextField(labelWithString: T("Prompt", "Prompt")), prompt,
                       FormKit.labeled(T("When", "Quando"), NSStackView(views: [recurrence, timeField])),
                       FormKit.labeled(T("Runs in", "Roda em"), target), FormKit.labeled(T("Account", "Conta"), account),
                       FormKit.labeled(T("Model", "Modelo"), model, width: 140), FormKit.labeled(T("Permissions", "Permissões"), permission),
                       FormKit.labeled(T("Tools", "Ferramentas"), toolsField),
                       FormKit.labeled(T("Cap (US$, min)", "Teto (US$, min)"), NSStackView(views: [budgetField, minutesField]), width: 160),
                       subscription, missed], in: self)
        prompt.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) { nil }
    public var firstField: NSView { nameField }

    /// The recurrence the popup and the field say; nil when the field does not read.
    static func parse(kind: Int, text: String) -> Recurrence? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        func time(_ s: String) -> (Int, Int)? {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
            return (parts[0], parts[1])
        }
        switch kind {
        case 0: return time(trimmed).map { .weekdays(hour: $0.0, minute: $0.1) }
        case 1: return time(trimmed).map { .daily(hour: $0.0, minute: $0.1) }
        case 2: return Int(trimmed).flatMap { (1...24).contains($0) ? .everyHours($0) : nil }
        case 3: return Int(trimmed).flatMap { (1...60).contains($0) ? .everyMinutes($0) : nil }
        default:
            let format = DateFormatter()
            format.dateFormat = "yyyy-MM-dd HH:mm"
            return format.date(from: trimmed).map { .once($0) }
        }
    }

    /// What to fix in the form, said to the owner.
    public struct Problem: Error, Equatable { public let message: String }

    /// The automation, off; the problem when the recurrence does not read.
    public func automation(id: String, fallback: Caps) -> Result<Automation, Problem> {
        guard let when = Self.parse(kind: recurrence.indexOfSelectedItem, text: timeField.stringValue) else {
            return .failure(Problem(message: T("The time \"\(timeField.stringValue)\" does not fit \(recurrence.titleOfSelectedItem ?? "").", "O horário \"\(timeField.stringValue)\" não serve para \(recurrence.titleOfSelectedItem ?? "").")))
        }
        let typed = model.stringValue.trimmingCharacters(in: .whitespaces)
        let agent = AgentChoice(account: accounts[max(0, account.indexOfSelectedItem)].dir, model: typed == T("default", "padrão") ? "" : typed)
        let place: AutomationTarget = repository != nil && target.indexOfSelectedItem == 0 ? .newWorktree(repository: repository!) : .folder(folder)
        let budget = Double(budgetField.stringValue.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil } ?? fallback.budgetUsd
        let minutes = Int(minutesField.stringValue).flatMap { $0 > 0 ? $0 : nil } ?? fallback.maxMinutes
        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        return .success(Automation(id: id, name: name.isEmpty ? "automation" : name, prompt: promptView.string, recurrence: when, target: place,
                                   agent: agent, permissionMode: Self.modes[max(0, permission.indexOfSelectedItem)],
                                   allowedTools: toolsField.stringValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                   caps: Caps(budgetUsd: budget, maxMinutes: minutes), useSubscription: subscription.state == .on,
                                   missed: missed.indexOfSelectedItem == 1 ? .skip : .runOnWake))
    }

    /// As the owner would fill it (the automation's test in the app).
    public func fill(name: String, prompt: String, kind: Int, time: String, newWorktree: Bool, account dir: String?, model name2: String,
                     permission mode: String, tools: String, budgetUsd: Double, maxMinutes: Int, subscription on: Bool, skipMissed: Bool) {
        nameField.stringValue = name
        promptView.string = prompt
        recurrence.selectItem(at: kind)
        timeField.stringValue = time
        target.selectItem(at: newWorktree || repository == nil ? 0 : 1)
        if let index = accounts.firstIndex(where: { $0.dir == dir }) { account.selectItem(at: index) }
        model.stringValue = name2
        permission.selectItem(at: Self.modes.firstIndex(of: mode) ?? 0)
        toolsField.stringValue = tools
        budgetField.stringValue = String(budgetUsd)
        minutesField.stringValue = "\(maxMinutes)"
        subscription.state = on ? .on : .off
        missed.selectItem(at: skipMissed ? 1 : 0)
    }
}
