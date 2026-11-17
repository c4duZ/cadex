import Agents
import AppKit
import SessionKit
import Settings
import Strings
import Themes
import Worktrees

/// Tasks in this window (docs/spec/worktrees.md, plan 19 phase D): New Task
/// asks the name, shows what needs a yes (the folder, the setup hooks),
/// makes the worktree through the core and opens a tab running the setup
/// hooks and then the agent, with no prompt, in the project's account or
/// the active one (docs/adr/0021-cadex-managed-accounts.md).
extension WindowSession {
    var repository: String? { WorktreesCore.repository(of: folder.root) }

    /// The main checkout of this folder's repository, also when the folder
    /// is one of its tasks: a race or a run made from inside a task's
    /// worktree took that worktree as the repository (found 2026-11-16, plan 24 D2).
    var mainRepository: String? {
        guard let root = repository else { return nil }
        return WorktreesCore.list(repo: root).first?.path ?? root
    }

    func makeTasksPage() -> WorktreesView {
        let page = WorktreesView()
        let paint = { [weak page] in
            let ui = ThemeStore.shared.current.interface
            page?.text = ui.text.nsColor
            page?.secondary = ui.secondaryText.nsColor
        }
        paint()
        ThemeStore.shared.observe { _ in paint() }
        page.repository = { [weak self] in self?.repository }
        let actions = worktreesActions()
        page.onOpen = actions.open
        page.onReview = { [weak self] task in self?.openReview(repo: task.path) }
        page.onNewTask = actions.newTask
        page.onComment = actions.comment
        page.onRemove = actions.remove
        page.onOpenRemote = actions.openRemote
        page.onRemoveRemote = actions.removeRemote
        return page
    }

    func worktreesActions() -> WorktreesActions {
        var actions = WorktreesActions(newTask: { [weak self] in self?.newTask() }, open: { [weak self] in self?.openTask($0) },
                                       remove: { [weak self] in self?.removeTask($0) }, comment: { [weak self] in self?.commentTask($0) },
                                       editSetupHooks: { [weak self] in self?.editSetupHooks() }, repository: { [weak self] in self?.repository })
        actions.targets = { [weak self] in self?.runTargets() ?? [] }
        actions.newTaskOn = { [weak self] in self?.newTask(on: $0) }
        actions.openRemote = { [weak self] in self?.openRemoteTask($0) }
        actions.removeRemote = { [weak self] in self?.removeRemoteTask($0) }
        actions.environment = { [weak self] action, key in self?.environmentAction(action, key: key) }
        return actions
    }

    /// worktrees.new-task, and worktrees.new-task-on with `on` already
    /// chosen: the name, and where it runs ("Run on", plan 23).
    func newTask(on preset: RunTarget? = nil) {
        guard let repo = repository else {
            return say(T("New Task needs a git repository", "Nova tarefa precisa de um repositório git"),
                       T("Open a repository's folder first.", "Abra antes a pasta de um repositório."))
        }
        askTaskName(preset: preset ?? recipeTarget(repo)) { [weak self] name, target in
            guard let self, !name.isEmpty else { return }
            if let target { return self.newRemoteTask(name: name, repo: repo, target: target) }
            self.confirmTask(WorktreesController.shared.plan(name: name, repo: repo))
        }
    }

    /// Shows what needs a yes (the folder, new setup hooks) before making the
    /// task. Saying no to the folder lets the owner choose another root.
    private func confirmTask(_ plan: TaskPlan) {
        var asks: [String] = []
        if plan.needsAuthorization { asks.append(T("Cadex will make tasks in \(plan.root).", "O Cadex vai criar tarefas em \(plan.root).")) }
        if plan.hooksNeedConfirmation { asks.append(T("Setup hooks that will run: ", "Hooks de preparo que vão rodar: ") + plan.hooks.joined(separator: " && ")) }
        guard !asks.isEmpty else { return makeTask(plan) }
        let alert = NSAlert()
        alert.messageText = T("Make the task \(plan.branch)?", "Criar a tarefa \(plan.branch)?")
        alert.informativeText = asks.joined(separator: "\n\n")
        alert.addButton(withTitle: T("Make Task", "Criar tarefa"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        if plan.needsAuthorization { alert.addButton(withTitle: T("Choose Another Folder…", "Escolher outra pasta…")) }
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn: self?.makeTask(plan)
            case .alertThirdButtonReturn: self?.chooseTasksRoot(then: plan)
            default: break
            }
        }
    }

    /// worktrees.root from a folder panel; the plan is made again under it.
    private func chooseTasksRoot(then plan: TaskPlan) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = T("Use for Tasks", "Usar para as tarefas")
        panel.message = T("Every repository's tasks go in a folder with its name inside this one (worktrees.root).",
                          "As tarefas de cada repositório vão numa pasta com o nome dele dentro desta (worktrees.root).")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.settings.store.update { $0.worktrees.root = SettingsBridge.tilde(url.path) }
            WorktreesController.shared.rootSetting = url.path
            DispatchQueue.main.async { self.confirmTask(WorktreesController.shared.plan(name: plan.name, repo: plan.repo)) }
        }
    }

    private func makeTask(_ plan: TaskPlan) {
        switch WorktreesController.shared.make(plan) {
        case .failure(.git(let message)):
            say(T("The task was not made", "A tarefa não foi criada"), message)
        case .success(let made):
            AgentAttention.shared.note(.taskCreated, text: plan.branch, project: (plan.repo as NSString).lastPathComponent)
            if let recipe = recipe(of: plan.repo) {
                // With a recipe the agent runs inside the environment (ADR 0032).
                startEnvironment(recipe, repo: plan.repo, branch: plan.branch, key: made.path, worktree: made.path, remote: nil, prefix: plan.hooks)
            } else {
                let agent = agentCommand(cwd: made.path)
                tabs?.newTab(cwd: made.path)
                tabs?.activeTerminal?.session?.write((plan.hooks + [agent]).joined(separator: " && ") + "\n")
            }
            if plan.explainTrust { explainTrust(plan) }
            if !made.unmatched.isEmpty {
                say(T("Some .worktreeinclude lines matched nothing", "Algumas linhas do .worktreeinclude não acharam nada"), made.unmatched.joined(separator: "\n"))
            }
        }
    }

    /// The first task of a repository: Claude Code asks to trust a folder it
    /// never saw, and for a worktree the trust is the main repository's:
    /// accepting in the task's tab covers the repository and every task, made
    /// before or after (tested 2026-11-15; the tasks' folder alone did not).
    /// No extra tab: a repository already trusted asks nothing.
    private func explainTrust(_ plan: TaskPlan) {
        let name = (plan.repo as NSString).lastPathComponent
        say(T("If Claude Code asks to trust the folder", "Se o Claude Code perguntar se confia na pasta"),
            T("Accept it in the task's tab: it counts for \(name) and every task of it, so it asks only once.",
              "Aceite na aba da tarefa: vale para \(name) e todas as tarefas dele, então só pergunta uma vez."))
    }

    /// `claude` with the kit, in the project's account or the active one.
    private func agentCommand(cwd: String) -> String {
        let agents = settings.store.settings.agents
        let projects = agents.projectAccounts.reduce(into: [String: String]()) { $0[SettingsBridge.expand($1.key)] = SettingsBridge.expand($1.value) }
        let account = AgentNewSession.account(cwd: cwd, accounts: AgentsController.shared.everyAccount(),
                                              active: agents.activeAccount.isEmpty ? nil : SettingsBridge.expand(agents.activeAccount), projects: projects)
        return SessionKit.shared.claudeCommand(configDir: account.flatMap { $0.isDefault ? nil : $0.dir },
                                               arguments: agents.launchSkipPermissions ? ["--dangerously-skip-permissions"] : [], cwd: cwd)
    }

    /// worktrees.open: the task becomes the window's workspace, with its terminal.
    func openTask(_ task: TaskWorktree) {
        followEnvironment(of: task.path, to: .resume)
        folder.open(task.path)
        if let terminal = tabs?.allTerminals.first(where: { $0.currentDirectory == task.path }) { return tabs?.focus(terminal) ?? () }
        tabs?.newTab(cwd: task.path)
    }

    /// worktrees.remove: refused while something would be lost, said what;
    /// else confirmed, with the branch going too when merged.
    func removeTask(_ task: TaskWorktree) {
        guard let repo = repository else { return }
        guard let lost = WorktreesController.shared.whatWouldBeLost(task) else {
            return say(T("The task's state could not be read", "Não deu para ler o estado da tarefa"), task.path)
        }
        guard lost.isEmpty else {
            return say(T("\(task.branch) has work that would be lost", "\(task.branch) tem trabalho que se perderia"),
                       T("Commit, push or merge it first:\n", "Faça commit, push ou merge antes:\n") + lost.prefix(12).joined(separator: "\n"))
        }
        confirm(T("Remove the task \(task.branch)?", "Remover a tarefa \(task.branch)?"),
                T("Its worktree goes, and its branch too (it is merged).", "A worktree sai, e o branch também (ele já foi juntado)."),
                button: T("Remove", "Remover")) { [weak self] in
            self?.askDestroyWithTask(task.path) { destroy in
                let env = WorktreesController.shared.store.environment(task.path)
                if let message = WorktreesController.shared.remove(task, repo: repo, deleteBranch: true) {
                    self?.say(T("The task was not removed", "A tarefa não foi removida"), message)
                } else {
                    // Its authorship and the versions kept for it go with it (ADR 0027).
                    AuthorshipHub.tracker(for: task.path).forget()
                    if destroy, let env { self?.runEnvironment(.destroy, env, key: task.path) }
                }
            }
        }
    }

    /// worktrees.set-comment.
    func commentTask(_ task: TaskWorktree) {
        ask(T("What \(task.branch) does now", "O que \(task.branch) faz agora"), "",
            placeholder: WorktreesController.shared.store.task(task.path)?.comment ?? "") { comment in
            WorktreesController.shared.setComment(comment, of: task.path)
        }
    }

    /// worktrees.edit-setup-hooks: the repository's commands, one per line.
    func editSetupHooks() {
        guard let repo = repository else { return }
        let key = SettingsBridge.tilde(repo)
        let current = settings.store.settings.worktrees.setupHooks[key] ?? []
        let alert = NSAlert()
        alert.messageText = T("Setup hooks of \((repo as NSString).lastPathComponent)", "Hooks de preparo de \((repo as NSString).lastPathComponent)")
        alert.informativeText = T("One command per line; they run in a new task's terminal before the agent, and are shown before their first run.",
                                  "Um comando por linha; rodam no terminal de uma tarefa nova antes do agente, e aparecem antes da primeira vez.")
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 90))
        text.string = current.joined(separator: "\n")
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        alert.accessoryView = text
        alert.addButton(withTitle: T("Save", "Salvar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let commands = text.string.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            self?.settings.store.update { $0.worktrees.setupHooks[key] = commands.isEmpty ? nil : commands }
        }
    }

    // MARK: Sheets

    func ask(_ title: String, _ text: String, placeholder: String, then: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: T("OK", "OK"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.window.initialFirstResponder = field
        if let typed = perfTypedText() { field.stringValue = typed }
        perfAnswer(alert)
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { then(field.stringValue.trimmingCharacters(in: .whitespaces)) }
        }
    }

    func confirm(_ title: String, _ text: String, button: String, then: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        perfAnswer(alert)
        alert.beginSheetModal(for: window) { response in if response == .alertFirstButtonReturn { then() } }
    }

    func say(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        perfAnswer(alert)
        alert.beginSheetModal(for: window)
    }
}
