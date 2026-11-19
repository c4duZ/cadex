import Agents
import AppKit
import CommandPalette
import Orchestration
import StateGlyph
import Strings

/// The Automations page (plan 34 F): orchestration.show-automations, from the sidebar's foot and
/// ⌘K. It always opens; Create automation turns automations on first when they are off (with the
/// same question as orchestration.toggle-automations), then the New Automation sheet.
extension WindowSession {
    func automationsPageCommands() -> [Command] {
        [Command(id: "orchestration.show-automations", title: T("Show Automations", "Mostrar as automações"),
                 keywords: ["automation", "automação", "schedule", "agenda", "cron", "list", "lista", "table", "tabela"],
                 category: .view, action: .run { [weak self] in self?.openAutomationsPage() })]
    }

    func openAutomationsPage() {
        if let open = tabs?.document(identity: AutomationsPageDocument.identity) { return tabs?.open(open) ?? () }
        tabs?.open(makeAutomationsPage())
    }

    func makeAutomationsPage() -> AutomationsPageDocument {
        var actions = AutomationsPageActions()
        actions.create = { [weak self] in self?.createAutomation() }
        actions.open = { [weak self] id in self?.showAutomationHistory(id) }
        actions.toggle = { [weak self] id in self?.toggleAutomation(id) }
        actions.runNow = { [weak self] id in self?.runAutomationNow(id) }
        actions.delete = { [weak self] id in self?.deleteAutomation(id) }
        actions.load = { [weak self] in self?.automationLines() ?? ([], false) }
        return AutomationsPageDocument(actions: actions)
    }

    /// Off: the question that turns them on, then the sheet; on: the sheet.
    private func createAutomation() {
        guard !OrchestrationController.shared.automationsEnabled else { return newAutomation() }
        toggleAutomations()
        // The setting reaches the controller on the store's next save: the sheet after it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard OrchestrationController.shared.automationsEnabled else { return }
            self?.newAutomation()
            self?.refreshAutomationsPage()
        }
    }

    func deleteAutomation(_ id: String) {
        guard let book = OrchestrationController.shared.automations(), let automation = try? book.automation(id) else { return }
        confirm(T("Delete \(automation.name)?", "Apagar \(automation.name)?"),
                T("The automation and the record of its runs go; the sessions it ran stay in their accounts.",
                  "A automação e o registro das rodadas dela somem; as sessões que ela rodou ficam nas contas."),
                button: T("Delete", "Apagar")) { [weak self] in
            try? book.delete(id)
            self?.app.syncAutomationAgent()
            self?.refreshAutomationsPage()
        }
    }

    func refreshAutomationsPage() {
        (tabs?.document(identity: AutomationsPageDocument.identity) as? AutomationsPageDocument)?.refresh()
    }

    private func automationLines() -> ([AutomationsLine], Bool) {
        let controller = OrchestrationController.shared
        guard controller.automationsEnabled, let book = controller.automations() else { return ([], false) }
        let accounts = AgentsController.shared.everyAccount()
        let now = Date()
        let lines = ((try? book.automations()) ?? []).sorted { $0.name < $1.name }.map { job -> AutomationsLine in
            let last = (try? book.history(of: job.id))?.first
            let project: String = switch job.target {
            case .newWorktree(let repository): (repository as NSString).lastPathComponent
            case .folder(let folder): (folder as NSString).lastPathComponent
            }
            let account = job.agent.account.flatMap { dir in accounts.first { $0.dir == dir }?.name } ?? T("default", "padrão")
            let next = job.enabled ? AutomationSchedule.next(job.recurrence, after: now).map { Self.automationWhen($0, now: now) } ?? "—" : "—"
            return AutomationsLine(id: job.id, name: job.name, when: AutomationSchedule.label(job.recurrence), project: project, account: account,
                                   last: last.map { Self.runWords($0, now: now) } ?? T("never", "nunca"), lastState: last.map { Self.runState($0.result) },
                                   next: next, on: job.enabled)
        }
        return (lines, true)
    }

    /// "today 09:00", "tomorrow 09:00", "Mon 08:00", "Nov 30 08:00".
    static func automationWhen(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return T("today ", "hoje ") + time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return T("tomorrow ", "amanhã ") + time }
        if date.timeIntervalSince(now) < 6 * 86400 { return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time }
        return date.formatted(.dateTime.day().month(.abbreviated)) + " " + time
    }

    /// "done today", "failed yesterday", "running".
    static func runWords(_ run: AutomationRun, now: Date) -> String {
        let what: String = switch run.result {
        case .running: T("running", "rodando")
        case .done: T("done", "concluída")
        case .failed: T("failed", "falhou")
        case .hitTheCap: T("hit the cap", "bateu o teto")
        case .stoppedWaiting: T("stopped waiting", "parou esperando")
        case .skipped: T("skipped", "pulada")
        }
        guard run.result != .running else { return what }
        let when = run.endedAt ?? run.scheduledAt
        let day = Calendar.current.isDate(when, inSameDayAs: now) ? T("today", "hoje")
            : Calendar.current.isDateInYesterday(when) ? T("yesterday", "ontem") : when.formatted(.dateTime.day().month(.abbreviated))
        return what + " " + day
    }

    static func runState(_ result: AutomationResult) -> GlyphState {
        switch result {
        case .running: .working
        case .done: .done
        case .failed, .hitTheCap: .failed
        case .stoppedWaiting: .needs
        case .skipped: .idle
        }
    }
}
