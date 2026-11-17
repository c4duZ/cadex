import Agents
import Orchestration
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

    func worktreesActions() -> WorktreesActions {
        var actions = WorktreesActions(newTask: { [weak self] in self?.newTask() }, open: { [weak self] in self?.openTask($0) },
                                       remove: { [weak self] in self?.removeTask($0) }, comment: { [weak self] in self?.commentTask($0) },
                                       editSetupHooks: { [weak self] in self?.editSetupHooks() }, repository: { [weak self] in self?.repository })
        actions.targets = { [weak self] in self?.runTargets() ?? [] }
        actions.newTaskOn = { [weak self] in self?.showNewTask(machine: $0) }
        actions.openRemote = { [weak self] in self?.openRemoteTask($0) }
        actions.removeRemote = { [weak self] in self?.removeRemoteTask($0) }
        actions.environment = { [weak self] action, key in self?.environmentAction(action, key: key) }
        return actions
    }

    /// worktrees.new-task (⌘N): the New Task sheet (NewTaskWiring.swift).
    func newTask() { showNewTask() }

    /// worktrees.root from a folder panel (the sheet's "Choose Another Folder…"); the sheet's
    /// lines are made again under it.
    func chooseTasksRoot() {
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
            self.newTaskSheet?.refreshNotes()
        }
    }

    /// The task's worktree, then a tab with its setup hooks and the agent with the owner's words
    /// (the sheet's Start: the sheet showed what needs a yes).
    func makeTask(_ plan: TaskPlan, prompt: String, agent: AgentChoice) {
        switch WorktreesController.shared.make(plan) {
        case .failure(.git(let message)):
            say(T("The task was not made", "A tarefa não foi criada"), message)
        case .success(let made):
            AgentAttention.shared.note(.taskCreated, text: plan.branch, project: (plan.repo as NSString).lastPathComponent)
            if let recipe = recipe(of: plan.repo) {
                // With a recipe the agent runs inside the environment (ADR 0032).
                startEnvironment(recipe, repo: plan.repo, branch: plan.branch, key: made.path, worktree: made.path, remote: nil, prefix: plan.hooks)
            } else {
                // Empty words: the agent with no prompt (the spec).
                let launch: Result<String, RaceRefusal> = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? .success(plainAgentCommand(agent, cwd: made.path))
                    : RaceLaunch.localCommand(kit: SessionKit.shared, agent: agent, cwd: made.path, prompt: prompt,
                                              skipPermissions: settings.store.settings.agents.launchSkipPermissions).map(\.command)
                switch launch {
                case .success(let command):
                    tabs?.newTab(cwd: made.path)
                    tabs?.activeTerminal?.typeWhenReady((plan.hooks + [command]).joined(separator: " && ") + "\n")
                case .failure(let refusal):
                    say(T("The agent did not start", "O agente não começou"), refusal.message)
                }
            }
            if !made.unmatched.isEmpty {
                say(T("Some .worktreeinclude lines matched nothing", "Algumas linhas do .worktreeinclude não acharam nada"), made.unmatched.joined(separator: "\n"))
            }
        }
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
