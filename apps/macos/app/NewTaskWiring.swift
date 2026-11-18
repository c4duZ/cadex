import AppKit
import Agents
import Orchestration
import SessionKit
import Settings
import Strings
import Worktrees

/// The New Task sheet in this window (plan 29 phase B; docs/spec/worktrees.md): the one way in
/// for a task and a race (⌘N, worktrees.new-task-on with its machine, worktrees.new-race with
/// two agents, the home screen). What New Task used to ask in a row of alerts (the tasks' folder,
/// new setup hooks, the trust) are lines of the sheet; Start is the yes. One agent: in the
/// project's folder, a terminal with the agent and the words (ADR 0036); in a copy, the task's
/// worktree and a tab with the hooks and the agent. Two or more: a race, each in its own copy.
extension WindowSession {
    /// `agents`: how many rows it opens with (the Race card, worktrees.new-race: two);
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
        // Codex accounts (~/.codex, ~/.codex-*), with their usage when the usage watch has it.
        let codex = every.filter { $0.provider == .codex }.map { account -> NewTaskAgent in
            var usage = ""
            if case .ready(let numbers, _) = AgentUsageController.shared.states[account.dir] ?? .loading,
               let percent = numbers.week?.percent ?? numbers.session?.percent {
                usage = T("\(Int(percent.rounded()))% used", "\(Int(percent.rounded()))% usado")
            }
            return NewTaskAgent(name: account.name, account: account.isDefault ? nil : account.dir, usage: usage, isCodex: true)
        }
        return accounts + codex + runTargets().map { NewTaskAgent(name: $0.label, account: nil, machine: $0.label) }
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
            for agent in request.agents where agent.machine.isEmpty && !agent.isCodex && seen.insert(agent.account ?? "").inserted
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
        if request.isRace, request.agents.contains(where: { $0.isCodex }) {
            notes.append(NewTaskNote(T("Codex keeps no cost Cadex can read: its cap is the time only.",
                                       "O Codex não guarda um custo que o Cadex leia: o teto dele é só o tempo.")))
        }
        guard request.runsInCopy, request.agents.contains(where: { $0.machine.isEmpty }) else { return notes }
        let plan = WorktreesController.shared.plan(name: request.branchName.isEmpty ? "task" : request.branchName, repo: repo)
        if plan.needsAuthorization {
            let root = (plan.root as NSString).abbreviatingWithTildeInPath
            notes.append(NewTaskNote(T("Copies go in \(root)", "As cópias ficam em \(root)"),
                                     action: T("Change…", "Trocar…")) { [weak self] in self?.chooseTasksRoot() })
        }
        if plan.hooksNeedConfirmation {
            notes.append(NewTaskNote(T("Setup hooks that will run in the copy: ", "Hooks de preparo que vão rodar na cópia: ") + plan.hooks.joined(separator: " && ")))
        }
        // A race asks the trust before it starts (the line above): this one is for a single task.
        if plan.explainTrust, !request.isRace {
            let name = (repo as NSString).lastPathComponent
            notes.append(NewTaskNote(T("Claude may ask once to trust \(name): accept it in the task's tab.",
                                       "O Claude pode perguntar uma vez se confia em \(name): aceite na aba da tarefa.")))
        }
        return notes
    }

    private func startNewTask(_ request: NewTaskRequest, repo: String) {
        let choice = { (agent: NewTaskAgent) in
            AgentChoice(account: agent.account, model: agent.model, machine: agent.machine, provider: agent.isCodex ? "codex" : nil)
        }
        if request.isRace {
            if !OrchestrationController.shared.isEnabled { settings.store.update { $0.orchestration.enabled = true } }
            let caps = OrchestrationController.shared.defaultCaps
            return startRace(RaceRequest(name: request.branchName, prompt: request.prompt, repository: repo, base: "",
                                         agents: request.agents.map(choice), caps: caps), askFirst: false)
        }
        guard let agent = request.agents.first else { return }
        if !agent.machine.isEmpty, let target = runTargets().first(where: { $0.label == agent.machine }) {
            // On another machine the task's tab runs Claude there, with its own login and the words
            // by file, as a race's contender (RemoteTaskScript.agent).
            return newRemoteTask(name: request.branchName, repo: repo, target: target, prompt: request.prompt, model: agent.model)
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
        if agent.isCodex {
            return SessionKit.shared.codexCommand(home: agent.account,
                                                  arguments: RaceLaunch.arguments(agent, skipPermissions: settings.store.settings.agents.launchSkipPermissions)) ?? "codex"
        }
        return SessionKit.shared.claudeCommand(configDir: agent.account,
                                        arguments: RaceLaunch.arguments(agent, skipPermissions: settings.store.settings.agents.launchSkipPermissions), cwd: cwd)
    }
}
