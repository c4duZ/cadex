import AppKit
import Agents
import Orchestration
import SessionKit
import Settings
import Strings
import Worktrees

/// The New Task sheet in this window (plan 29 phase B; docs/spec/worktrees.md): the one way in
/// for a task and a race (⌘N, worktrees.new-task-on with its machine, orchestration.new-race with
/// two agents, the home screen). What New Task used to ask in a row of alerts (the tasks' folder,
/// new setup hooks, the trust) are lines of the sheet; Start is the yes. One agent: in the
/// project's folder, a terminal with the agent and the words (ADR 0036); in a copy, the task's
/// worktree and a tab with the hooks and the agent. Two or more: a race, each in its own copy.
extension WindowSession {
    /// `agents`: how many rows it opens with (the Race card, orchestration.new-race: two);
    /// `machine`: the first row on that machine (worktrees.new-task-on).
    func showNewTask(prompt: String = "", agents count: Int = 1, machine: RunTarget? = nil, keeping kept: NewTaskRequest? = nil) {
        guard let repo = mainRepository else {
            return say(T("New Task needs a git repository", "Nova tarefa precisa de um repositório git"),
                       T("Open a repository's folder first.", "Abra antes a pasta de um repositório."))
        }
        guard newTaskSheet == nil, let host = window.contentView else { return }
        let choices = newTaskChoices(repo: repo)
        var rows = Array(choices.filter { $0.machine.isEmpty }.prefix(1))
        if let machine = machine ?? recipeTarget(repo), let remote = choices.first(where: { $0.machine == machine.label }) { rows = [remote] }
        while rows.count < count, let first = rows.first { rows.append(choices.filter { $0.machine.isEmpty }.dropFirst(rows.count).first ?? first) }
        var actions = NewTaskSheetActions()
        actions.project = (repo as NSString).lastPathComponent
        actions.choices = { [weak self] in self?.newTaskChoices(repo: repo) ?? [] }
        actions.notes = { [weak self] request in self?.newTaskNotes(request, repo: repo) ?? [] }
        let caps = OrchestrationController.shared.defaultCaps
        actions.cap = (caps.budgetUsd, caps.maxMinutes)
        actions.cancel = { [weak self] in self?.closeNewTask() }
        actions.projects = { [weak self] in
            guard let projects = self?.projects else { return [] }
            var seen = Set<String>()
            return (projects.projects.map { ($0.name, $0.folder) } + projects.recent.map { ($0.name, $0.folder) })
                .filter { seen.insert($0.1).inserted && FileManager.default.fileExists(atPath: $0.1) }
                .map { (name: $0.0, folder: $0.1) }
        }
        // Another project: it shows, and the sheet opens again there with the same words and agents.
        actions.switchProject = { [weak self] folder, request in
            guard let self else { return }
            self.closeNewTask()
            self.folder.open(folder)
            self.projects?.open(folder: folder)
            self.showNewTask(keeping: request)
        }
        actions.openFolder = { [weak self] in
            self?.closeNewTask()
            self?.chooseProjectFolder()
        }
        actions.start = { [weak self] request in
            self?.closeNewTask()
            self?.startNewTask(request, repo: repo)
        }
        let sheet = NewTaskSheet(request: kept ?? NewTaskRequest(prompt: prompt, agents: rows), actions: actions)
        sheet.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(sheet, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            sheet.leadingAnchor.constraint(equalTo: host.leadingAnchor), sheet.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            sheet.topAnchor.constraint(equalTo: host.topAnchor), sheet.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        newTaskSheet = sheet
        fillPerfNewTask(sheet)
    }

    func closeNewTask() {
        newTaskSheet?.removeFromSuperview()
        newTaskSheet = nil
    }

    /// The accounts of Claude Code here (the project's or the active one first), then the machines
    /// ("Run on", plan 23), each with what the usage files say.
    private func newTaskChoices(repo: String) -> [NewTaskAgent] {
        let every = AgentsController.shared.everyAccount()
        let accounts = raceAccounts(repo: repo).map { account -> NewTaskAgent in
            let usage: String
            let found = every.first { account.dir == nil ? $0.isDefault : $0.dir == account.dir }
            if let numbers = found.flatMap(AgentUsage.current), let percent = numbers.week?.percent ?? numbers.session?.percent {
                usage = T("\(Int(percent.rounded()))% used", "\(Int(percent.rounded()))% usado")
            } else {
                usage = ""
            }
            return NewTaskAgent(name: account.title, account: account.dir, usage: usage)
        }
        return accounts + runTargets().map { NewTaskAgent(name: $0.label, account: nil, machine: $0.label) }
    }

    /// The old questions as lines: where the copies go (with another folder to choose), the setup
    /// hooks that will run, the trust Claude Code asks once, and races being off.
    private func newTaskNotes(_ request: NewTaskRequest, repo: String) -> [NewTaskNote] {
        var notes: [NewTaskNote] = []
        if request.isRace, !OrchestrationController.shared.isEnabled {
            notes.append(NewTaskNote(T("Races are off: starting this one turns them on. Each agent spends its account's usage.",
                                       "As corridas estão desligadas: começar esta as liga. Cada agente gasta o uso da conta dele.")))
        }
        // A race needs each account here to trust the folder already (nobody answers Claude's
        // dialog in N tabs at once): the line stops Start and opens Claude there to accept it.
        if request.isRace {
            var seen = Set<String>()
            for agent in request.agents where agent.machine.isEmpty && seen.insert(agent.account ?? "").inserted
                && !ClaudeTrust.isTrusted(repo, repository: nil, configDir: agent.account) {
                let project = (repo as NSString).lastPathComponent
                notes.append(NewTaskNote(T("Claude Code in \(agent.name) does not trust \(project) yet: accept it once, then start the race.",
                                           "O Claude Code em \(agent.name) ainda não confia em \(project): aceite uma vez e comece a corrida."),
                                         action: T("Open Claude to Trust", "Abrir o Claude para confiar"), blocks: true) { [weak self] in
                    self?.closeNewTask()
                    self?.tabs?.newTab(cwd: repo)
                    self?.tabs?.activeTerminal?.typeWhenReady(SessionKit.shared.claudeCommand(configDir: agent.account, cwd: repo) + "\n")
                })
            }
        }
        guard request.runsInCopy, request.agents.contains(where: { $0.machine.isEmpty }) else { return notes }
        let plan = WorktreesController.shared.plan(name: request.branchName.isEmpty ? "task" : request.branchName, repo: repo)
        if plan.needsAuthorization {
            notes.append(NewTaskNote(T("The copies go in \(plan.root).", "As cópias ficam em \(plan.root)."),
                                     action: T("Choose Another Folder…", "Escolher outra pasta…")) { [weak self] in self?.chooseTasksRoot() })
        }
        if plan.hooksNeedConfirmation {
            notes.append(NewTaskNote(T("Setup hooks that will run in the copy: ", "Hooks de preparo que vão rodar na cópia: ") + plan.hooks.joined(separator: " && ")))
        }
        if plan.explainTrust {
            let name = (repo as NSString).lastPathComponent
            notes.append(NewTaskNote(T("If Claude Code asks to trust the folder, accept it in the task's tab: it counts for \(name) and every task of it.",
                                       "Se o Claude Code perguntar se confia na pasta, aceite na aba da tarefa: vale para \(name) e todas as tarefas dele.")))
        }
        return notes
    }

    private func startNewTask(_ request: NewTaskRequest, repo: String) {
        let choice = { (agent: NewTaskAgent) in AgentChoice(account: agent.account, model: agent.model, machine: agent.machine) }
        if request.isRace {
            if !OrchestrationController.shared.isEnabled { settings.store.update { $0.orchestration.enabled = true } }
            let caps = OrchestrationController.shared.defaultCaps
            return startRace(RaceRequest(name: request.branchName, prompt: request.prompt, repository: repo, base: "",
                                         agents: request.agents.map(choice), caps: caps), askFirst: false)
        }
        guard let agent = request.agents.first else { return }
        if !agent.machine.isEmpty, let target = runTargets().first(where: { $0.label == agent.machine }) {
            // On another machine the task's tab runs Claude there, with its own login; the words
            // go into that agent as the race's do (RemoteTaskScript.agent), not yet for a task.
            return newRemoteTask(name: request.branchName, repo: repo, target: target)
        }
        if request.runsInCopy {
            return makeTask(WorktreesController.shared.plan(name: request.branchName, repo: repo), prompt: request.prompt, agent: choice(agent))
        }
        openAgent(prompt: request.prompt, agent: choice(agent), in: repo, newTab: true)
    }

    /// A terminal in `folder` with the agent and the owner's words as its prompt, by file (ADR
    /// 0033/0036); `newTab` false: the active terminal (the one a project just opened came with).
    func openAgent(prompt: String, agent: AgentChoice, in folder: String, newTab: Bool) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if newTab { tabs?.newTab(cwd: folder) }
            tabs?.activeTerminal?.typeWhenReady(plainAgentCommand(agent, cwd: folder) + "\n")
            return
        }
        switch RaceLaunch.localCommand(kit: SessionKit.shared, agent: agent, cwd: folder, prompt: prompt,
                                       skipPermissions: settings.store.settings.agents.launchSkipPermissions) {
        case .success(let launch):
            if newTab { tabs?.newTab(cwd: folder) }
            tabs?.activeTerminal?.typeWhenReady(launch.command + "\n")
        case .failure(let refusal):
            say(T("The agent did not start", "O agente não começou"), refusal.message)
        }
    }

    /// The agent with no prompt (empty words, the spec): `claude` with the kit, its model.
    func plainAgentCommand(_ agent: AgentChoice, cwd: String) -> String {
        SessionKit.shared.claudeCommand(configDir: agent.account,
                                        arguments: RaceLaunch.arguments(agent, skipPermissions: settings.store.settings.agents.launchSkipPermissions), cwd: cwd)
    }
}
