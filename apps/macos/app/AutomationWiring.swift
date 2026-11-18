import AgentTools
import Agents
import AppKit
import CommandPalette
import Orchestration
import SessionKit
import Settings
import Strings

/// Automations in this window (docs/spec/orchestration.md "Automações",
/// docs/adr/0034-scheduled-automations.md; plan 24 E): the commands, turning
/// them on (what changes shown first), "New Automation", turning one on or
/// off (the LaunchAgent follows: installed with the first, removed with the
/// last), "Run Now" and the history. The agenda, the launch and the watch
/// are `AutomationRunWiring.swift`.
extension WindowSession {
    func registerAutomations(palette: CommandPaletteController) {
        var actions = AutomationCommandActions()
        actions.toggleAll = { [weak self] in self?.toggleAutomations() }
        actions.new = { [weak self] in self?.newAutomation() }
        actions.toggle = { [weak self] in self?.toggleAutomation($0.id) }
        actions.runNow = { [weak self] in self?.runAutomationNow($0.id) }
        actions.showHistory = { [weak self] in self?.showAutomationHistory($0.id) }
        commands.register(AutomationCommands.all(palette: palette, actions: actions))
    }

    /// orchestration.toggle-automations: turning on says first what changes,
    /// with the terms' position (ADR 0029, 0033).
    func toggleAutomations() {
        if settings.store.settings.orchestration.automations { return settings.store.update { $0.orchestration.automations = false } }
        confirm(T("Turn on automations?", "Ligar as automações?"),
                T("An automation runs Claude with its prompt on a schedule, with nobody looking, even with Cadex closed: macOS will show a background item notice when the first one is turned on. Automated use of a subscription is a grey area in the Consumer Terms; each new automation suggests the account's API key (apiKeyHelper), and using the subscription is your choice per automation. Every run has a cap.",
                  "Uma automação roda o Claude com o prompt dela num horário, sem ninguém olhando, mesmo com o Cadex fechado: o macOS mostra um aviso de item em segundo plano quando a primeira é ligada. Uso automatizado da assinatura é zona cinzenta nos Termos de Consumidor; cada automação nova sugere a chave de API da conta (apiKeyHelper), e usar a assinatura é escolha sua, por automação. Toda execução tem teto."),
                button: T("Turn On", "Ligar")) { [weak self] in self?.settings.store.update { $0.orchestration.automations = true } }
    }

    /// orchestration.new-automation: the sheet; it is made off, and its history opens.
    func newAutomation() {
        let controller = OrchestrationController.shared
        guard let book = controller.automations() else { return }
        let here = folder.root
        let repo = mainRepository
        let form = NewAutomationForm(accounts: raceAccounts(repo: repo ?? here), repository: repo, folder: here, caps: controller.defaultCaps)
        fillPerfAutomationForm(form)
        showForm(T("New Automation", "Nova automação"), text: T("It is made off: turn it on from its history. Each run shows in a tab, within its cap.",
                                  "Ela nasce desligada: ligue pelo histórico dela. Cada execução aparece numa aba, dentro do teto."), form: form, primary: T("Create", "Criar"), first: form.firstField) { [weak self] in
            guard let self else { return }
            switch form.automation(id: book.newId(), fallback: controller.defaultCaps) {
            case .failure(let problem): self.say(T("The automation was not made", "A automação não foi criada"), problem.message)
            case .success(let automation):
                do { try book.save(automation) } catch { return self.say(T("The automation was not made", "A automação não foi criada"), "\(error)") }
                self.showAutomationHistory(automation.id)
            }
        }
    }

    /// orchestration.toggle-automation: on shows first what runs, where, on
    /// which account, how paid and under which cap; off removes the
    /// LaunchAgent with the last one.
    func toggleAutomation(_ id: String) {
        guard let book = OrchestrationController.shared.automations(), let automation = try? book.automation(id) else { return }
        if automation.enabled {
            try? book.turn(id, on: false)
            app.syncAutomationAgent()
            return refreshAutomationPages()
        }
        let paid = automation.useSubscription ? T("on the subscription", "na assinatura") : T("with the account's API key (apiKeyHelper)", "com a chave de API da conta (apiKeyHelper)")
        let first = ((try? book.enabled()) ?? []).isEmpty
        confirm(T("Turn on \(automation.name)?", "Ligar \(automation.name)?"),
                AutomationSchedule.label(automation.recurrence) + ", " + AutomationLaunch.place(automation) + ", " + RaceColumns.agentLabel(automation.agent)
                + ", " + paid + T(", permissions \(automation.permissionMode), cap US$ \(String(format: "%.2f", automation.caps.budgetUsd)) and \(automation.caps.maxMinutes) min.",
                                  ", permissões \(automation.permissionMode), teto US$ \(String(format: "%.2f", automation.caps.budgetUsd)) e \(automation.caps.maxMinutes) min.")
                + (first ? T("\n\nmacOS will show that Cadex added a background item.", "\n\nO macOS vai avisar que o Cadex adicionou um item em segundo plano.") : ""),
                button: T("Turn On", "Ligar")) { [weak self] in
            try? book.turn(id, on: true)
            self?.app.syncAutomationAgent()
            self?.refreshAutomationPages()
        }
    }

    /// orchestration.show-automation-history: its page in a tab.
    func showAutomationHistory(_ id: String) {
        guard let book = OrchestrationController.shared.automations() else { return }
        if let open = AutomationWatch.shared.pages.first(where: { $0.automationID == id }), tabs?.open(open) != nil { return }
        var actions = AutomationHistoryActions()
        actions.runNow = { [weak self] in self?.runAutomationNow(id) }
        actions.toggle = { [weak self] in self?.toggleAutomation(id) }
        actions.goToSession = { [weak self] in self?.goToAutomationSession(run: $0, automation: id) }
        actions.openTranscript = { [weak self] in self?.openAutomationTranscript(run: $0, automation: id) }
        let page = AutomationHistoryDocument(automationID: id, book: book, actions: actions)
        page.onClose = { [weak page] in AutomationWatch.shared.pages.removeAll { $0 === page } }
        AutomationWatch.shared.pages.append(page)
        tabs?.open(page)
    }

    func refreshAutomationPages() { AutomationWatch.shared.pages.forEach { $0.refresh() } }

    /// "Session": its tab when still open, else a tab resuming it on its account.
    private func goToAutomationSession(run id: String, automation: String) {
        guard let run = (try? OrchestrationController.shared.automations()?.history(of: automation))??.first(where: { $0.id == id }),
              let session = run.session else { return }
        if let found = app.locate({ $0.agentResume?.kitSession == session.kit }) {
            found.window.projects?.select(found.space)
            return found.window.tabs?.focus(found.terminal) ?? ()
        }
        guard let claude = session.claude, let automation = try? OrchestrationController.shared.automations()?.automation(automation) else { return NSSound.beep() }
        let cwd = run.folder ?? AutomationLaunch.place(automation)
        tabs?.newTab(cwd: cwd)
        tabs?.activeTerminal?.typeWhenReady(SessionKit.shared.claudeCommand(configDir: automation.agent.account, arguments: ["--resume", claude], cwd: cwd) + "\n")
    }

    private func openAutomationTranscript(run id: String, automation: String) {
        guard let run = (try? OrchestrationController.shared.automations()?.history(of: automation))??.first(where: { $0.id == id }),
              let path = run.session?.transcript, FileManager.default.fileExists(atPath: path) else { return NSSound.beep() }
        tabs?.open(AgentTranscriptDocument(path: path, title: AutomationLines.label(run.result), detail: path, colors: Self.agentColors()))
    }
}

extension AppDelegate {
    /// The LaunchAgent as the automations turned on say: their dates, or
    /// none (removed). A test instance passes its folders and executable to
    /// the job, so the app it opens is the test one.
    func syncAutomationAgent() {
        let controller = OrchestrationController.shared
        let on = controller.automationsEnabled ? ((try? controller.automations()?.enabled()) ?? []) : []
        let dates = on.flatMap { AutomationSchedule.launchdDates($0.recurrence) }
        // A test scenario's own hooks (CADEX_PERF_*) stay out: the app the job
        // opens must not start the scenario again.
        var environment = ProcessInfo.processInfo.environment.filter {
            $0.key.hasPrefix("CADEX_") && $0.key != "CADEX_BACKGROUND" && !$0.key.hasPrefix("CADEX_PERF_")
        }
        if Bundle.main.bundlePath.hasSuffix(".app") && environment["CADEX_ORCHESTRATION_DIR"] == nil {
            environment = ["CADEX_APP_BUNDLE": Bundle.main.bundlePath]
        } else {
            environment["CADEX_APP_BIN"] = Bundle.main.executablePath
            // The job asks this instance's socket, never the default one.
            environment["CADEX_APP_SOCKET"] = AgentToolsServer.shared.path
        }
        if let problem = AutomationAgent().sync(cadex: SessionKit.shared.toolsPath, dates: dates, environment: environment) {
            NSLog("Cadex automations: the LaunchAgent did not change (%@)", problem)
        }
    }
}
