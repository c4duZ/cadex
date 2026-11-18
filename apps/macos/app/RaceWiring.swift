import Agents
import AppKit
import CommandPalette
import Orchestration
import SessionKit
import Settings
import Strings
import Terminal
import Themes
import Worktrees

/// A race in this window (docs/spec/orchestration.md, "Corrida"; plan 24
/// phase C): the commands, the form, and the launch: one worktree per
/// contender from the same branch, through New Task's own plan, and one tab
/// each with `claude` and the prompt, which never goes through the shell
/// (docs/adr/0033-cadex-launches-agents.md). Another machine goes through
/// the minimal "Run on" (plan 23). The board is `RaceBoardWiring.swift`.
extension WindowSession {
    func registerRaces(palette: CommandPaletteController) {
        var actions = RaceCommandActions()
        actions.toggle = { [weak self] in self?.toggleOrchestration() }
        actions.newRace = { [weak self] in self?.newRace() }
        actions.show = { [weak self] in self?.showRace($0.id) }
        actions.pickWinner = { [weak self] race, contender in self?.pickWinner(race, contender) }
        actions.discard = { [weak self] in self?.discardRace($0) }
        actions.deleteBranches = { [weak self] in self?.deleteRaceBranches($0) }
        commands.register(RaceCommands.all(palette: palette, actions: actions))
    }

    /// orchestration.toggle: turning on shows first what changes (ADR 0033).
    func toggleOrchestration() {
        if settings.store.settings.orchestration.enabled { return settings.store.update { $0.orchestration.enabled = false } }
        confirm(T("Turn on races and runs?", "Ligar corridas e execuções?"),
                T("Cadex will open Claude with a prompt in a tab when you start a race or a run, always showing first what runs, where, on which account and with which cap. Each agent spends that account's usage.",
                  "O Cadex vai abrir o Claude com um prompt numa aba quando você começar uma corrida ou execução, sempre mostrando antes o que roda, onde, em qual conta e com qual teto. Cada agente gasta o uso daquela conta."),
                button: T("Turn On", "Ligar")) { [weak self] in self?.settings.store.update { $0.orchestration.enabled = true } }
    }

    /// The accounts to offer: the project's (or the active one) first; nil is the default one's.
    func raceAccounts(repo: String) -> [AccountChoice] {
        let agents = settings.store.settings.agents
        let projects = agents.projectAccounts.reduce(into: [String: String]()) { $0[SettingsBridge.expand($1.key)] = SettingsBridge.expand($1.value) }
        let first = AgentNewSession.account(cwd: repo, accounts: AgentsController.shared.everyAccount(),
                                            active: agents.activeAccount.isEmpty ? nil : SettingsBridge.expand(agents.activeAccount), projects: projects)
        let all = AgentsController.shared.everyAccount().filter { $0.provider == .claude }
        // One per folder: the same account listed twice came out twice in the form (2026-11-16).
        var seen: Set<String> = []
        let ordered = ((first.map { [$0] } ?? []) + all).filter { seen.insert($0.dir).inserted }
        return ordered.map { AccountChoice(title: $0.name, dir: $0.isDefault ? nil : $0.dir) }
    }

    /// orchestration.new-race: the New Task sheet with two agents (plan 29: one sheet for a task
    /// and a race; the old form left).
    func newRace() { showNewTask(agents: 2) }

    /// `askFirst` false: a test instance's own race (`RacePerfHooks.swift`), no sheet.
    func startRace(_ request: RaceRequest, askFirst: Bool = true) {
        let controller = OrchestrationController.shared
        // orchestration.maxAgents is for every agent alive: the runs' and other races' take slots too (plan 24 D1).
        let free = controller.limits.maxAgents - liveRunAgents() - liveRaceAgents()
        let refusal = RaceLaunch.check(request, enabled: controller.isEnabled, maxAgents: free) { account in
            ClaudeTrust.isTrusted(request.repository, repository: nil, configDir: account)
        }
        if let refusal { return say(T("The race did not start", "A corrida não começou"), refusal.message) }
        guard let book = controller.races() else { return }
        let worktrees = WorktreesController.shared
        let plans = request.agents.indices.map { worktrees.plan(name: RaceLaunch.taskName(request.name, index: $0 + 1), repo: request.repository,
                                                                base: request.base.isEmpty ? nil : request.base) }
        // What New Task would ask (the folder, new setup hooks) is asked once for all.
        let asks = (plans[0].needsAuthorization ? [T("Cadex will make tasks in \(plans[0].root).", "O Cadex vai criar tarefas em \(plans[0].root).")] : [])
            + (plans[0].hooksNeedConfirmation ? [T("Setup hooks that will run in each: ", "Hooks de preparo que vão rodar em cada uma: ") + plans[0].hooks.joined(separator: " && ")] : [])
        // The race is recorded only once it starts: a cancel leaves nothing
        // behind (found 2026-11-16, a race waiting on this question was
        // already in the state).
        let go = { [weak self] in
            guard let self, let (race, contenders) = try? book.newRace(name: request.name, prompt: request.prompt, repository: request.repository,
                                                                       base: plans[0].base, caps: request.caps, agents: request.agents,
                                                                       worktree: { plans[$0 - 1].path }, maxAgents: controller.limits.maxAgents) else { return }
            var lanes: [TerminalView] = []
            for (contender, plan) in zip(contenders, plans) {
                if let lane = self.launch(contender, plan: plan, race: race, book: book, beside: lanes.last) { lanes.append(lane) }
            }
            // The local contenders side by side in one tab (the Race mockup); none: the board.
            if lanes.isEmpty { self.showRace(race.id) } else { self.dressLanes(race, lanes) }
        }
        if asks.isEmpty || !askFirst { return go() }
        confirm(T("Start the race \(request.name)?", "Começar a corrida \(request.name)?"), asks.joined(separator: "\n\n"), button: T("Start", "Começar"), then: go)
    }

    /// One contender: its worktree, then a terminal with the setup hooks and the agent, in a new
    /// tab or split to the right of `beside` (the race's lanes); the local one's terminal.
    private func launch(_ contender: Contender, plan: TaskPlan, race: Race, book: RaceBook, beside: TerminalView?) -> TerminalView? {
        if !contender.agent.machine.isEmpty { launchRemote(contender, race: race, book: book); return nil }
        if case .failure(.git(let message)) = WorktreesController.shared.make(plan) {
            try? book.update(contender.id, state: .failed, reason: message)
            return nil
        }
        WorktreesController.shared.setComment(T("race \(race.name) #\(contender.index)", "corrida \(race.name) #\(contender.index)"), of: plan.path)
        switch RaceLaunch.localCommand(kit: SessionKit.shared, agent: contender.agent, cwd: plan.path, prompt: race.prompt,
                                       skipPermissions: settings.store.settings.agents.launchSkipPermissions) {
        case .failure(let refusal):
            try? book.update(contender.id, state: .failed, reason: refusal.message)
            return nil
        case .success(let opened):
            try? book.update(contender.id, state: .working, session: SessionLink(kit: opened.session))
            // Beside the last lane when it is still in front; else a tab of its own.
            let split = beside.flatMap { lane in tabs?.activeTerminal === lane ? tabs?.splitRight(cwd: plan.path) : nil }
            if split == nil { tabs?.newTab(cwd: plan.path) }
            tabs?.activeTerminal?.typeWhenReady((plan.hooks + [opened.command]).joined(separator: " && ") + "\n")
            return tabs?.activeTerminal
        }
    }

    /// On another machine: its worktree there (the folder remembered from a
    /// task there before), the prompt sent by ssh's stdin, then the tab.
    private func launchRemote(_ contender: Contender, race: Race, book: RaceBook) {
        guard let target = runTargets().first(where: { $0.label == contender.agent.machine }) else {
            try? book.update(contender.id, state: .failed, reason: T("\(contender.agent.machine) is not reachable", "\(contender.agent.machine) não está ao alcance"))
            return
        }
        let worktrees = WorktreesController.shared
        guard let folder = worktrees.store.remoteFolder(race.repository, on: target.destination) else {
            try? book.update(contender.id, state: .failed, reason: T("Make one task on \(target.label) first (New Task › Run on), so Cadex knows the repository's folder there.",
                                                                     "Crie antes uma tarefa em \(target.label) (Nova tarefa › Rodar em), para o Cadex saber a pasta do repositório lá."))
            return
        }
        Task { [weak self] in
            let made = await worktrees.makeRemote(name: RaceLaunch.taskName(race.name, index: contender.index), repo: race.repository,
                                                  target: target, folder: folder, clone: false)
            guard let self else { return }
            guard case .made(let path, _) = made else {
                try? book.update(contender.id, state: .failed, reason: "\(made)")
                return self.refreshRaceBoards()
            }
            try? book.update(contender.id, state: .starting, worktree: path)
            switch await worktrees.remoteRunner.uploadPrompt(target, race.prompt) {
            case .failure(let error):
                try? book.update(contender.id, state: .failed, reason: error.message)
            case .success(let file):
                let hooks = self.settings.store.settings.worktrees.setupHooks[SettingsBridge.tilde(race.repository)] ?? []
                guard let script = RemoteTaskScript.agent(path: path, hooks: hooks, promptFile: file, model: contender.agent.model) else {
                    try? book.update(contender.id, state: .failed, reason: T("The model's name is not one Cadex can pass.", "O nome do modelo não é um que o Cadex consiga passar."))
                    return self.refreshRaceBoards()
                }
                try? book.update(contender.id, state: .working)
                self.tabs?.newTab()
                self.tabs?.activeTerminal?.typeWhenReady(RemoteTaskScript.sshLine(target, script) + "\n")
            }
            self.refreshRaceBoards()
        }
    }
}
