import AgentTools
import Agents
import AppKit
import Orchestration
import SessionKit
import Strings
import Terminal
import Worktrees

/// What the app knows of the automations' runs (plan 24 E): the history
/// pages open, the runs whose agent was seen working, and one timer, armed
/// only while a run goes, that ends it (done, failed, past its cap, or
/// stopped waiting at the duration cap). No timer otherwise: the launchd job
/// marks the hours (docs/adr/0034-scheduled-automations.md).
@MainActor
final class AutomationWatch {
    static let shared = AutomationWatch()
    var pages: [AutomationHistoryDocument] = []
    var seenWorking: Set<String> = []
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func arm(_ tick: @escaping @MainActor () -> Void) {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: TerminalView.agentDidChange, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { tick() }
            }
        }
        guard timer == nil else { return }
        let next = Timer(timeInterval: 10, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        next.tolerance = 3
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    func disarm() {
        timer?.invalidate()
        timer = nil
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
    }
}

extension AppDelegate {
    /// Checks the agenda when the app opens, when the Mac wakes and when the
    /// job asks (`cadex automations due`); nothing with automations off.
    func startAutomations() {
        OrchestrationController.shared.onAutomationsSwitch = { [weak self] _ in self?.syncAutomationAgent() }
        AgentToolsServer.shared.onDue = { [weak self] in self?.checkAgenda() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // The network and the disks come back a moment after the wake.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { MainActor.assumeIsolated { self?.checkAgenda() } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard OrchestrationController.shared.automationsEnabled else { return }
            self?.syncAutomationAgent()
            self?.checkAgenda()
            if !((try? OrchestrationController.shared.automations()?.runningRuns()) ?? []).isEmpty { self?.armAutomationWatch() }
        }
    }

    /// Every automation turned on: what is due now runs (or is skipped, a
    /// missed one by its rule, or "still running").
    func checkAgenda(now: Date = Date()) {
        let controller = OrchestrationController.shared
        guard controller.automationsEnabled, let book = controller.automations(), let window = sessions.first else { return }
        for automation in (try? book.enabled()) ?? [] {
            let running = (try? book.running(automation.id)) != nil
            let last = try? book.lastScheduled(automation.id)
            switch AutomationSchedule.due(automation, lastScheduled: last ?? nil, running: running, now: now) {
            case .nothing: break
            case .skip(let at, let why): try? book.skip(automation.id, at: at, reason: why)
            case .run(let at): window.runAutomation(automation, scheduledAt: at, manual: false)
            }
        }
        window.refreshAutomationPages()
    }

    func armAutomationWatch() {
        AutomationWatch.shared.arm { [weak self] in self?.automationTick() }
    }

    /// Each running run: its cost; done when its agent stopped after working,
    /// failed when it left; past the cap the agent is ended ("hit the cap",
    /// or "stopped waiting" when it waited for a permission).
    private func automationTick() {
        guard let book = OrchestrationController.shared.automations() else { return AutomationWatch.shared.disarm() }
        let runs = (try? book.runningRuns()) ?? []
        for run in runs {
            guard let automation = try? book.automation(run.automation), let kit = run.session?.kit else { continue }
            let found = locate { $0.agentResume?.kitSession == kit }
            let terminal = found?.terminal
            let state = terminal?.agentStatus?.state
            if state == .working { AutomationWatch.shared.seenWorking.insert(run.id) }
            let cost = terminal?.agentResume.flatMap { SessionCost.read(session: $0.sessionID) } ?? run.costUsd
            let minutes = Date().timeIntervalSince(run.startedAt ?? Date()) / 60
            let started = Date().timeIntervalSince(run.startedAt ?? Date())
            noteSession(run, terminal: terminal, book: book)
            if (state == .done || state == .idle) && AutomationWatch.shared.seenWorking.contains(run.id) {
                endAutomationRun(run, automation, result: .done, cost: cost, reason: nil, book: book)
            } else if state == .failed || (started > 30 && terminal?.hasForegroundProcess != true) {
                endAutomationRun(run, automation, result: .failed, cost: cost, reason: T("the agent exited", "o agente saiu"), book: book)
            } else if (cost ?? 0) > automation.caps.budgetUsd || minutes > Double(automation.caps.maxMinutes) {
                if let group = terminal?.foregroundGroup, group > 0 { kill(group, SIGTERM) }
                let waiting = state == .blocked
                endAutomationRun(run, automation, result: waiting ? .stoppedWaiting : .hitTheCap, cost: cost,
                                 reason: waiting ? T("waited for a permission until the duration cap", "esperou uma permissão até o teto de duração") : nil, book: book)
            }
        }
        // The last turn's cost is written by the status line a moment after
        // the run ended (realok read US$ 0, 2026-11-16): read again for 2 min.
        let recent = ((try? book.automations()) ?? []).flatMap { (try? book.history(of: $0.id)) ?? [] }
            .filter { $0.result != .running && $0.result != .skipped && Date().timeIntervalSince($0.endedAt ?? .distantPast) < 120 }
        for var run in recent {
            guard let claude = run.session?.claude, let cost = SessionCost.read(session: claude), cost != run.costUsd else { continue }
            run.costUsd = cost
            try? book.record(run)
        }
        sessions.first?.refreshAutomationPages()
        if ((try? book.runningRuns()) ?? []).isEmpty && recent.isEmpty { AutomationWatch.shared.disarm() }
    }

    /// Claude's id and the transcript's path, once its hooks said them.
    private func noteSession(_ run: AutomationRun, terminal: TerminalView?, book: AutomationBook) {
        guard let resume = terminal?.agentResume, run.session?.claude != resume.sessionID else { return }
        var updated = run
        let root = resume.configDir ?? FileManager.default.homeDirectoryForCurrentUser.path + "/.claude"
        let slug = String(resume.folder.map { $0.isLetter || $0.isNumber ? $0 : "-" })
        updated.session = SessionLink(kit: run.session?.kit ?? "", claude: resume.sessionID, transcript: root + "/projects/" + slug + "/" + resume.sessionID + ".jsonl")
        try? book.record(updated)
    }

    func endAutomationRun(_ run: AutomationRun, _ automation: Automation, result: AutomationResult, cost: Double?, reason: String?, book: AutomationBook) {
        try? book.finish(run.id, automation: run.automation, result: result, cost: cost, reason: reason)
        power.release(job: run.id)
        AutomationWatch.shared.seenWorking.remove(run.id)
        let text = AutomationLines.label(result) + (reason.map { ": " + $0 } ?? "")
        AgentAttention.shared.note(result == .done ? .finished : .failed, text: automation.name + " — " + text, project: (AutomationLaunch.place(automation) as NSString).lastPathComponent)
        if AgentNotifier.canPost { postTerminalNotification(title: automation.name, subtitle: T("Automation", "Automação"), body: text, key: "") }
        if ProcessInfo.processInfo.environment["CADEX_PERF_SHEETS"] == "1" { NSLog("Cadex automation: %@ %@", automation.name, text) }
    }
}

extension WindowSession {
    /// orchestration.run-automation-now: off schedule, with the same caps.
    func runAutomationNow(_ id: String) {
        guard let book = OrchestrationController.shared.automations(), let automation = try? book.automation(id) else { return }
        if (try? book.running(id)) != nil { return say(T("\(automation.name) is still running", "\(automation.name) ainda está rodando"), "") }
        runAutomation(automation, scheduledAt: Date(), manual: true)
    }

    /// A run: the checks, its folder (a new worktree, or the fixed one), the
    /// prompt by file, a tab in this window without bringing it forward, the
    /// computer kept awake; a refusal is a failed run in its history.
    func runAutomation(_ automation: Automation, scheduledAt: Date, manual: Bool) {
        let controller = OrchestrationController.shared
        guard let book = controller.automations() else { return }
        let refusal = AutomationLaunch.check(automation, enabled: controller.automationsEnabled,
                                             folderExists: { FileManager.default.fileExists(atPath: $0) },
                                             trusts: { ClaudeTrust.isTrusted($0, repository: nil, configDir: $1) },
                                             hasApiKeyHelper: { AutomationLaunch.hasApiKeyHelper(configDir: $0) })
        func fail(_ why: String) {
            try? book.skip(automation.id, at: scheduledAt, result: .failed, reason: why)
            app.endAutomationNotice(automation, why)
            if manual { say(T("\(automation.name) did not run", "\(automation.name) não rodou"), why) }
            refreshAutomationPages()
        }
        if let refusal { return fail(refusal.message) }
        var cwd = AutomationLaunch.place(automation)
        var hooks: [String] = []
        if case .newWorktree(let repository) = automation.target {
            let plan = WorktreesController.shared.plan(name: AutomationLaunch.taskName(automation, at: scheduledAt), repo: repository)
            if case .failure(.git(let message)) = WorktreesController.shared.make(plan) { return fail(T("failed to start: ", "não começou: ") + message) }
            WorktreesController.shared.setComment(T("automation \(automation.name)", "automação \(automation.name)"), of: plan.path)
            cwd = plan.path
            hooks = plan.hooks
        }
        let kit = SessionKit.shared
        guard kit.toolsPath != nil else { return fail(RaceRefusal.noCadex.message) }
        guard case .success(let file) = PromptFiles.write(automation.prompt) else { return fail(RaceRefusal.emptyPrompt.message) }
        guard let opened = kit.claudeCommand(configDir: automation.agent.account, arguments: AutomationLaunch.arguments(automation), cwd: cwd, promptFile: file) else {
            return fail(RaceRefusal.noCadex.message)
        }
        guard var run = try? book.start(automation, scheduledAt: scheduledAt) else { return }
        run.session = SessionLink(kit: opened.session)
        run.folder = cwd
        try? book.record(run)
        if controller.limits.keepAwakeDuringRuns { app.power.hold(job: run.id) }
        tabs?.newTab(cwd: cwd)
        tabs?.activeTerminal?.session?.write((hooks + [opened.command]).joined(separator: " && ") + "\n")
        app.armAutomationWatch()
        refreshAutomationPages()
    }
}

extension AppDelegate {
    /// A run that did not start: the owner hears it like a failed one.
    func endAutomationNotice(_ automation: Automation, _ why: String) {
        AgentAttention.shared.note(.failed, text: automation.name + " — " + why, project: (AutomationLaunch.place(automation) as NSString).lastPathComponent)
        if AgentNotifier.canPost { postTerminalNotification(title: automation.name, subtitle: T("Automation", "Automação"), body: why, key: "") }
        if ProcessInfo.processInfo.environment["CADEX_PERF_SHEETS"] == "1" { NSLog("Cadex automation: %@ failed: %@", automation.name, why) }
    }
}
