import AppKit
import CommandPalette
import Orchestration
import SessionKit
import Settings
import Strings
import Worktrees

/// Runs in this window, with the owner coordinating (docs/spec/orchestration.md
/// "Execuções"; plan 24 D1): the commands, the sheets, and the dispatch: a
/// worktree from the chosen branch through New Task's own plan, and a tab
/// with `claude`, the task's spec as the prompt (never through the shell,
/// docs/adr/0033-cadex-launches-agents.md) and CADEX_DISPATCH_ID in the
/// session's environment. The page and its timer are `RunPageWiring.swift`.
extension WindowSession {
    func registerRuns(palette: CommandPaletteController) {
        var actions = RunCommandActions()
        actions.newRun = { [weak self] in self?.newRun() }
        actions.show = { [weak self] in self?.showRun($0.id) }
        actions.addTask = { [weak self] in self?.addRunTask($0.id) }
        actions.dispatch = { [weak self] in self?.dispatchTask($0.id) }
        actions.retry = { [weak self] in self?.retryTask($0.id) }
        actions.stopDispatch = { [weak self] in self?.stopDispatch($0.id) }
        actions.markDone = { [weak self] in self?.markDispatchDone($0.id) }
        actions.stopRun = { [weak self] in self?.stopRun($0.id) }
        actions.setDependencies = { [weak self] in self?.setTaskDependencies($0.id) }
        actions.stopWaiting = { [weak self] in self?.stopTask($0.id) }
        actions.addGate = { [weak self] in self?.addTaskGate($0.id) }
        actions.approveGate = { [weak self] in self?.approveTaskGate($0.id) }
        actions.rejectGate = { [weak self] in self?.rejectTaskGate($0.id) }
        actions.answer = { [weak self] in self?.answerQuestion($0) }
        actions.agent = { [weak self] id, request in self?.answerRunAgent(id, request) ?? .failed("the window is gone") }
        commands.register(RunCommands.all(palette: palette, actions: actions))
        // Dispatches left working by the last launch: the watch reaps the
        // ones whose agent is gone. Nothing with the feature off.
        DispatchQueue.main.async { [weak self] in
            guard OrchestrationController.shared.isEnabled, let book = OrchestrationController.shared.runs(),
                  !RunGraph.live((try? book.store.all(.dispatches)) ?? []).isEmpty else { return }
            self?.armRunWatch()
        }
    }

    /// orchestration.new-run: the name, the cap and who coordinates, in this
    /// repository; then its page (and, with an agent coordinating, its tab).
    func newRun() {
        let controller = OrchestrationController.shared
        guard let repo = mainRepository else {
            return say(T("A run needs a git repository", "Uma execução precisa de um repositório git"), T("Open a repository's folder first.", "Abra antes a pasta de um repositório."))
        }
        let form = NewRunForm(caps: controller.defaultCaps, accounts: raceAccounts(repo: repo))
        let alert = NSAlert()
        alert.messageText = T("New Run", "Nova execução")
        alert.informativeText = T("Tasks in \((repo as NSString).abbreviatingWithTildeInPath), each in its own worktree and agent. You coordinate (each dispatch yours, or ready tasks starting on their own as the account below), or an agent does: Claude opens in a tab here with your goal and spawns the tasks. The cap is for the whole run.",
                                  "Tarefas em \((repo as NSString).abbreviatingWithTildeInPath), cada uma na sua worktree e agente. Você coordena (cada despacho seu, ou as prontas começando sozinhas na conta abaixo), ou um agente coordena: o Claude abre numa aba aqui com o seu objetivo e cria as tarefas. O teto vale para a execução inteira.")
        alert.accessoryView = form
        alert.addButton(withTitle: T("Create Run", "Criar a execução"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.window.initialFirstResponder = form.firstField
        fillPerfRunForm(form)
        perfAnswer(alert)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.createRun(form.values(fallback: controller.defaultCaps), repo: repo)
        }
    }

    func createRun(_ values: NewRunValues, repo: String) {
        guard let book = OrchestrationController.shared.runs() else { return }
        if values.mode == .agent {
            guard !values.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return say(T("The run was not created", "A execução não foi criada"), T("An agent coordinating needs a goal.", "Um agente coordenando precisa de um objetivo."))
            }
            guard ClaudeTrust.isTrusted(repo, repository: nil, configDir: values.agent.account) else {
                return say(T("The run was not created", "A execução não foi criada"),
                           DispatchRefusal.notTrusted(values.agent.account.map { ($0 as NSString).lastPathComponent } ?? "~/.claude", dir: values.agent.account).message)
            }
        }
        guard let run = try? book.newRun(name: values.name, repository: repo, caps: values.caps) else { return }
        if values.mode != .owner { try? book.configure(run: run.id, autoAgent: values.agent, goal: values.mode == .agent ? values.goal : nil) }
        showRun(run.id)
        if values.mode == .agent, let made = try? book.run(run.id) { launchCoordinator(made, book: book) }
    }

    /// orchestration.add-task: title, spec and what it waits for.
    func addRunTask(_ runID: String) {
        guard let book = OrchestrationController.shared.runs(), let run = try? book.run(runID) else { return }
        let form = AddTaskForm(others: (try? book.tasks(of: runID)) ?? [])
        let alert = NSAlert()
        alert.messageText = T("Add a Task to \(run.name)", "Adicionar uma tarefa a \(run.name)")
        alert.informativeText = T("It is ready when every task it starts after is done.", "Ela fica pronta quando todas as tarefas de que depende estão concluídas.")
        alert.accessoryView = form
        alert.addButton(withTitle: T("Add Task", "Adicionar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.window.initialFirstResponder = form.firstField
        fillPerfTaskForm(form)
        perfAnswer(alert)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let values = form.values()
            guard !values.title.isEmpty else { return self.say(T("The task did not go in", "A tarefa não entrou"), T("It needs a title.", "Ela precisa de um título.")) }
            do {
                try book.addTask(run: runID, title: values.title, spec: values.spec, dependsOn: values.dependsOn, gate: values.gate)
            } catch {
                self.say(T("The task did not go in", "A tarefa não entrou"), Self.runMessage(error, run: runID))
            }
            self.refreshRunPages()
            self.dispatchOnTheirOwn()
        }
    }

    /// orchestration.retry: the failed try stays in the task's history; the
    /// new one goes through the same sheet.
    func retryTask(_ taskID: String) {
        guard let book = OrchestrationController.shared.runs() else { return }
        guard let task: RunTask = try? book.store.get(.tasks, id: taskID) else { return }
        do { try book.retry(task: taskID) } catch { return say(T("No new try", "Sem nova tentativa"), Self.runMessage(error, run: task.run)) }
        refreshRunPages()
        dispatchTask(taskID)
    }

    /// orchestration.mark-done: the owner's word that the work is done.
    func markDispatchDone(_ id: String) {
        guard let book = OrchestrationController.shared.runs() else { return }
        let run = (try? book.store.get(.dispatches, id: id) as Dispatch?)??.run ?? ""
        do { try book.markDone(id, summary: T("marked done by you", "marcada como concluída por você")) } catch {
            say(T("Not marked done", "Não foi marcada"), Self.runMessage(error, run: run))
        }
        refreshRunPages()
        drainRunQueue()
        dispatchOnTheirOwn()
    }

    /// orchestration.stop-dispatch: it and the dispatches below it stop, their agents ended.
    func stopDispatch(_ id: String) {
        guard let book = OrchestrationController.shared.runs(), let dispatch: Dispatch = try? book.store.get(.dispatches, id: id),
              let task: RunTask = try? book.store.get(.tasks, id: dispatch.task) else { return }
        confirm(T("Stop \(task.title)?", "Parar \(task.title)?"),
                T("Its agent is ended (it keeps its conversation), and so are the agents of the tasks it spawned. The task goes back to ready.",
                  "O agente dele é encerrado (a conversa fica), e também os das tarefas que ele criou. A tarefa volta a pronta."),
                button: T("Stop", "Parar")) { [weak self] in
            self?.endAgents((try? book.stop(id)) ?? [])
        }
    }

    /// orchestration.stop-run, with confirmation: every live dispatch stops,
    /// and the run takes no new ones.
    func stopRun(_ id: String) {
        guard let book = OrchestrationController.shared.runs(), let run = try? book.run(id) else { return }
        let live = RunGraph.live((try? book.dispatches(of: id)) ?? []).count
        let coordinator = run.coordinator == nil ? "" : T(" and the coordinating agent", " e o agente coordenador")
        let more = run.coordinator == nil ? "" : T(" (and the coordinator)", " (e o coordenador)")
        confirm(T("Stop the run \(run.name)?", "Parar a execução \(run.name)?"),
                T("\(live) agent(s) working\(coordinator) are ended, and the run takes no new dispatches. The agents of done tasks stay open. Worktrees and branches stay.",
                  "\(live) agente(s) trabalhando\(more) são encerrados, e a execução não aceita novos despachos. Os agentes das tarefas concluídas ficam abertos. Worktrees e branches ficam."),
                button: T("Stop Run", "Parar a execução")) { [weak self] in
            self?.endAgents((try? book.stopRun(id)) ?? [])
            self?.endCoordinator(of: id)
        }
    }

    /// SIGTERM to each stopped dispatch's agent, as a hibernation does; the
    /// freed slots go to the dispatches waiting for one.
    func endAgents(_ stopped: [Dispatch]) {
        for dispatch in stopped {
            if let found = dispatchTerminal(dispatch), found.terminal.foregroundGroup > 0 { kill(found.terminal.foregroundGroup, SIGTERM) }
        }
        refreshRunPages()
        if !stopped.isEmpty { drainRunQueue() }
    }

    /// A stopped run's coordinating agent ends too (SIGTERM, as a hibernation).
    func endCoordinator(of runID: String) {
        guard let kit = (try? OrchestrationController.shared.runs()?.run(runID))??.coordinator,
              let found = app.locate({ $0.agentResume?.kitSession == kit }), found.terminal.foregroundGroup > 0 else { return }
        kill(found.terminal.foregroundGroup, SIGTERM)
    }

    /// The page's "Stop" on a task: out of the queue when it waits for a
    /// slot, else its live try stopped (orchestration.stop-dispatch).
    func stopTask(_ taskID: String) {
        guard let book = OrchestrationController.shared.runs(), let task: RunTask = try? book.store.get(.tasks, id: taskID) else { return }
        if task.queued != nil {
            try? book.unqueue(task: taskID)
            return refreshRunPages()
        }
        guard let live = RunGraph.live((try? book.dispatches(of: task.run)) ?? []).first(where: { $0.task == taskID }) else { return }
        stopDispatch(live.id)
    }

    /// orchestration.set-dependencies: the other tasks as checkboxes; a cycle
    /// is refused at once, saying it by the tasks' titles.
    func setTaskDependencies(_ taskID: String) {
        guard let book = OrchestrationController.shared.runs(), let task: RunTask = try? book.store.get(.tasks, id: taskID) else { return }
        let others = ((try? book.tasks(of: task.run)) ?? []).filter { $0.id != taskID }
        let form = DependenciesForm(others: others, checked: task.dependsOn)
        let alert = NSAlert()
        alert.messageText = T("\(task.title) starts after…", "\(task.title) começa depois de…")
        alert.informativeText = T("It is ready when every task checked here is done.", "Ela fica pronta quando todas as tarefas marcadas aqui estão concluídas.")
        alert.accessoryView = form
        alert.addButton(withTitle: T("Save", "Salvar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        fillPerfDependenciesForm(form)
        perfAnswer(alert)
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do { try book.setDependencies(task: taskID, form.values()) } catch {
                self.say(T("The dependencies did not change", "As dependências não mudaram"), Self.runMessage(error, run: task.run))
            }
            self.refreshRunPages()
        }
    }

    /// An error of the run's book as the owner reads it (a cycle by titles).
    static func runMessage(_ error: Error, run: String) -> String {
        guard let error = error as? RunError else { return "\(error)" }
        let tasks = (try? OrchestrationController.shared.runs()?.tasks(of: run)) ?? []
        return error.message(titles: Dictionary(tasks.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first }))
    }
}
