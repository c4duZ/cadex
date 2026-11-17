import AppKit
import Orchestration
import SessionKit
import Strings
import Terminal
import Worktrees

/// A dispatch from the owner (docs/spec/orchestration.md "Execuções" and
/// "Antes de rodar"; plan 24 D1): the sheet with what will run, where, on
/// which account, in which permission mode and under which cap; the checks;
/// the trust ("Open Claude to Trust"); the queue at orchestration.maxAgents
/// (races count too); and the launch, in a new worktree and tab or in an
/// idle terminal the owner picked.
extension WindowSession {
    /// orchestration.dispatch: the sheet, then the checks and the launch.
    func dispatchTask(_ taskID: String) {
        let controller = OrchestrationController.shared
        guard let book = controller.runs(), let task: RunTask = try? book.store.get(.tasks, id: taskID),
              let run = try? book.run(task.run) else { return }
        let worktrees = WorktreesController.shared
        let current = worktrees.plan(name: "x", repo: run.repository).base
        let bases = RunLaunch.bases(for: task, dispatches: (try? book.dispatches(of: run.id)) ?? [], repositoryBranch: current)
        let skip = settings.store.settings.agents.launchSkipPermissions
        let form = DispatchForm(accounts: raceAccounts(repo: run.repository), bases: bases, idle: idleTerminals(repo: run.repository),
                                prompt: RunLaunch.prompt(task),
                                permissions: skip ? T("none asked (--dangerously-skip-permissions)", "nenhuma pedida (--dangerously-skip-permissions)")
                                                  : T("Claude Code asks, in the tab", "o Claude Code pergunta, na aba"))
        let alert = NSAlert()
        alert.messageText = T("Dispatch \(task.title)?", "Despachar \(task.title)?")
        alert.informativeText = T("Claude in a new worktree in \((worktrees.tasksRoot(of: run.repository) as NSString).abbreviatingWithTildeInPath) and a tab, or in the idle terminal you pick, with the prompt below. Run cap: US$ \(String(format: "%.2f", run.caps.budgetUsd)) and \(run.caps.maxMinutes) min.",
                                  "O Claude numa worktree nova em \((worktrees.tasksRoot(of: run.repository) as NSString).abbreviatingWithTildeInPath) e numa aba, ou no terminal parado que você escolher, com o prompt abaixo. Teto da execução: US$ \(String(format: "%.2f", run.caps.budgetUsd)) e \(run.caps.maxMinutes) min.")
        alert.accessoryView = form
        alert.addButton(withTitle: T("Dispatch", "Despachar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        fillPerfDispatchForm(form)
        perfAnswer(alert)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.startDispatch(form.request(task: taskID))
        }
    }

    /// Agents alive now: the runs' live dispatches and the races' local
    /// agents with a program running in their tab (orchestration.maxAgents is for all).
    func liveRaceAgents() -> Int {
        guard let book = OrchestrationController.shared.races() else { return 0 }
        return ((try? book.races()) ?? []).flatMap { (try? book.contenders(of: $0.id)) ?? [] }
            .filter { $0.agent.machine.isEmpty && $0.state != .discarded }
            .filter { contenderTerminal($0)?.terminal.hasForegroundProcess == true }.count
    }

    /// The runs' live dispatches and their coordinating agents still running.
    func liveRunAgents() -> Int {
        guard let book = OrchestrationController.shared.runs() else { return 0 }
        let coordinators = ((try? book.store.all(.runs) as [Run]) ?? []).filter { run in
            guard !run.stopped, let kit = run.coordinator else { return false }
            return app.locate { $0.agentResume?.kitSession == kit }?.terminal.hasForegroundProcess == true
        }.count
        return RunGraph.live((try? book.store.all(.dispatches)) ?? []).count + coordinators
    }

    /// `askFirst` false: from the queue or a test instance, no confirmation.
    /// `auto`: a task dispatched on its own (plan 24 D2): a refusal fails the
    /// task with the reason instead of a sheet, so it is not tried at every turn.
    func startDispatch(_ request: DispatchRequest, askFirst: Bool = true, auto: Bool = false) {
        let controller = OrchestrationController.shared
        guard let book = controller.runs(), let task: RunTask = try? book.store.get(.tasks, id: request.task),
              let run = try? book.run(task.run) else { return }
        let all: [Dispatch] = (try? book.store.all(.dispatches)) ?? []
        let refusal = RunLaunch.check(request, run: run, task: task, all: all, othersLive: liveRaceAgents(), enabled: controller.isEnabled,
                                      maxAgents: controller.limits.maxAgents) { ClaudeTrust.isTrusted(run.repository, repository: nil, configDir: $0) }
        if auto, let refusal, refusal != .noSlot(controller.limits.maxAgents) {
            try? book.failTask(task.id, reason: T("failed to start: ", "não começou: ") + refusal.message)
            return refreshRunPages()
        }
        if case .notTrusted(_, let dir)? = refusal { return askToTrust(run.repository, account: dir, message: refusal?.message ?? "") }
        if let refusal, refusal != .noSlot(controller.limits.maxAgents) {
            try? book.unqueue(task: task.id)
            return say(T("\(task.title) was not dispatched", "\(task.title) não foi despachada"), refusal.message)
        }
        let full = refusal != nil
        if let shell = request.reuseShell {
            guard full else { return launchInTerminal(request, shell: shell, task: task, book: book) }
            return queueDispatch(request, book: book, say: askFirst)
        }
        let plan = WorktreesController.shared.plan(name: RunLaunch.taskName(run: run, task: task), repo: run.repository,
                                                   base: request.base.isEmpty ? nil : request.base)
        let asks = (plan.needsAuthorization ? [T("Cadex will make tasks in \(plan.root).", "O Cadex vai criar tarefas em \(plan.root).")] : [])
            + (plan.hooksNeedConfirmation ? [T("Setup hooks that will run first: ", "Hooks de preparo que vão rodar antes: ") + plan.hooks.joined(separator: " && ")] : [])
        let go: () -> Void = { [weak self] in
            if full { self?.queueDispatch(request, book: book, say: askFirst) } else { self?.launchDispatch(request, task: task, run: run, plan: plan, book: book) }
        }
        if asks.isEmpty || !askFirst { return go() }
        confirm(T("Dispatch \(task.title)?", "Despachar \(task.title)?"), asks.joined(separator: "\n\n"), button: T("Dispatch", "Despachar"), then: go)
    }

    /// Every slot taken: the dispatch waits on its task and starts when an agent ends.
    private func queueDispatch(_ request: DispatchRequest, book: RunBook, say tell: Bool) {
        do { try book.queue(request) } catch { return say(T("Not queued", "Não entrou na fila"), "\(error)") }
        refreshRunPages()
        armRunWatch()
        let max = OrchestrationController.shared.limits.maxAgents
        if tell {
            say(T("Waiting for a free slot (\(max) of \(max))", "Esperando uma vaga (\(max) de \(max))"),
                T("It starts on its own when an agent ends. Settings › Many Agents has the cap.", "Começa sozinho quando um agente terminar. O teto fica em Configurações › Muitos agentes."))
        }
    }

    /// The waiting dispatches, oldest first, while slots are free.
    func drainRunQueue() {
        let controller = OrchestrationController.shared
        guard let book = controller.runs(), let waiting = try? book.waiting(), !waiting.isEmpty else { return }
        for request in waiting {
            guard liveRunAgents() + liveRaceAgents() < controller.limits.maxAgents else { break }
            startDispatch(request, askFirst: false)
        }
        refreshRunPages()
    }

    /// "Open Claude to Trust": a tab with that account's Claude in the
    /// repository, where the owner accepts the dialog (docs/spec/orchestration.md "Estados").
    private func askToTrust(_ repo: String, account: String?, message: String) {
        let alert = NSAlert()
        alert.messageText = T("Waiting for Claude Code's trust", "Esperando a confiança do Claude Code")
        alert.informativeText = message
        alert.addButton(withTitle: T("Open Claude to Trust", "Abrir o Claude para confiar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        // A test instance never opens Claude in the owner's default account
        // (~/.claude): only in a Cadex account folder.
        perfAnswer(alert, accept: account != nil)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.tabs?.newTab(cwd: repo)
            self.tabs?.activeTerminal?.typeWhenReady(SessionKit.shared.claudeCommand(configDir: account, cwd: repo) + "\n")
        }
    }

    /// Terminals of this window with no program running, in the repository
    /// or one of its tasks: where the owner may reuse one.
    func idleTerminals(repo: String) -> [DispatchForm.Idle] {
        let root = WorktreesController.shared.tasksRoot(of: repo)
        return (spaces?.spaces ?? []).flatMap { $0.tabs.allTerminals }.compactMap { terminal in
            guard !terminal.hasForegroundProcess, terminal.shellPid > 0, let cwd = terminal.currentDirectory,
                  cwd == repo || cwd.hasPrefix(repo + "/") || cwd.hasPrefix(root + "/") else { return nil }
            return DispatchForm.Idle(title: T("Terminal in ", "Terminal em ") + (cwd as NSString).abbreviatingWithTildeInPath, shell: terminal.shellPid)
        }
    }

    /// Recorded first (its id goes into the session's environment), then
    /// the worktree, the prompt's file and the tab; a step that fails fails
    /// the dispatch with the reason, and the task can be tried again.
    private func launchDispatch(_ request: DispatchRequest, task: RunTask, run: Run, plan: TaskPlan, book: RunBook) {
        guard let dispatch = record(request, task: task, worktree: plan.path, book: book) else { return }
        defer {
            refreshRunPages()
            armRunWatch()
        }
        if case .failure(.git(let message)) = WorktreesController.shared.make(plan) {
            return (try? book.fail(dispatch.id, reason: T("failed to start: ", "não começou: ") + message)) ?? ()
        }
        WorktreesController.shared.setComment(T("run \(run.name) · \(task.title)", "execução \(run.name) · \(task.title)"), of: plan.path)
        guard let command = command(for: dispatch, task: task, cwd: plan.path, book: book) else { return }
        tabs?.newTab(cwd: plan.path)
        tabs?.activeTerminal?.typeWhenReady((plan.hooks + [command]).joined(separator: " && ") + "\n")
    }

    /// In the idle terminal the owner picked: its folder is the dispatch's.
    private func launchInTerminal(_ request: DispatchRequest, shell: Int32, task: RunTask, book: RunBook) {
        guard let found = app.locate({ $0.shellPid == shell }), !found.terminal.hasForegroundProcess, let cwd = found.terminal.currentDirectory else {
            return say(T("\(task.title) was not dispatched", "\(task.title) não foi despachada"),
                       T("That terminal is gone or busy now.", "Esse terminal sumiu ou está ocupado agora."))
        }
        guard let dispatch = record(request, task: task, worktree: cwd, book: book) else { return }
        defer {
            refreshRunPages()
            armRunWatch()
        }
        guard let command = command(for: dispatch, task: task, cwd: cwd, book: book) else { return }
        found.terminal.session?.write(command + "\n")
        found.window.spaces?.select(found.space)
        found.window.tabs?.focus(found.terminal)
    }

    private func record(_ request: DispatchRequest, task: RunTask, worktree: String, book: RunBook) -> Dispatch? {
        do {
            return try book.dispatch(task: task.id, agent: request.agent, worktree: worktree, session: nil,
                                     maxAgents: OrchestrationController.shared.limits.maxAgents, othersLive: liveRaceAgents())
        } catch {
            say(T("\(task.title) was not dispatched", "\(task.title) não foi despachada"), Self.runMessage(error, run: task.run))
            return nil
        }
    }

    /// `cadex claude --cadex-prompt-file` with the dispatch's id in the session; nil (the dispatch failed) when it cannot be made.
    private func command(for dispatch: Dispatch, task: RunTask, cwd: String, book: RunBook) -> String? {
        switch RaceLaunch.localCommand(kit: SessionKit.shared, agent: dispatch.agent, cwd: cwd, prompt: RunLaunch.prompt(task),
                                       skipPermissions: settings.store.settings.agents.launchSkipPermissions,
                                       sessionEnvironment: OrchestrationController.sessionEnvironment(dispatch: dispatch.id)) {
        case .failure(let refusal):
            try? book.fail(dispatch.id, reason: T("failed to start: ", "não começou: ") + refusal.message)
            return nil
        case .success(let opened):
            try? book.attach(dispatch.id, session: SessionLink(kit: opened.session))
            return opened.command
        }
    }
}
