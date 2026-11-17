import AppKit
import CommandPalette
import Agents
import Sidebar
import StateGlyph
import Strings
import Terminal
import Worktrees

/// The work's tree in this window (plan 27 phase B; docs/spec/sidebar.md): the projects with their
/// terminals and their tasks, gathered here from the features that own them (projects, worktrees,
/// terminals, agents) and drawn by the sidebar feature. Rebuilt when a tab, a project, a task or
/// an agent's state changes; the tasks' worktrees are listed off the main thread (git), once per
/// project and again when the tasks change.
extension WindowSession {
    func makeTree() -> WorkTreeView {
        let tree = WorkTreeView(newTaskShortcut: app.keymapLabel("worktrees.new-task")) { [weak self] id in _ = self?.commands.run(id) }
        tree.onPick = { [weak self] pick in self?.pickInTree(pick) }
        treeObserver = NotificationCenter.default.addObserver(forName: TerminalView.agentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTree() }
        }
        treeWatch = WorktreesController.shared.watch { [weak self] in self?.loadTreeTasks() }
        return tree
    }

    /// sidebar.find, the tree's filter button: a project, task or terminal of the tree by name.
    func treeCommands(palette: CommandPaletteController) -> [Command] {
        [Command(id: "sidebar.find", title: T("Find in the Work Tree…", "Achar na árvore do trabalho…"),
                 keywords: ["find", "filter", "tree", "project", "task", "terminal", "achar", "filtrar", "árvore", "tarefa"], category: .view,
                 action: .run { [weak self] in
                     guard let tree = self?.workspace?.tree else { return }
                     palette.open(tree.findSource())
                 })]
    }

    /// The tasks of each project, listed by git off the main thread, then the tree again; with the
    /// branch of each (the HEAD file). `onlyIfProjectsChanged`: a project switch lists nothing.
    func loadTreeTasks(onlyIfProjectsChanged: Bool = false) {
        guard let projects else { return }
        let folders = projects.projects.map(\.folder)
        if onlyIfProjectsChanged, folders == treeFolders { return refreshTree() }
        treeFolders = folders
        treeLoad += 1
        let load = treeLoad
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var found: [String: [TaskWorktree]] = [:]
            var branches: [String: String] = [:]
            for folder in folders {
                // The main worktree and the project's own folder are not its tasks (a project that
                // is itself a worktree listed itself: review of 2026-11-17).
                found[folder] = Array(WorktreesCore.list(repo: folder).dropFirst()).filter { $0.path != folder }
                branches[folder] = AgentProject.of(folder).branch ?? ""
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, load == self.treeLoad else { return }
                    self.treeTasks = found
                    self.treeBranches = branches
                    self.refreshTree()
                }
            }
        }
    }

    /// One redraw for a burst of changes (a title animating, statuses coming in): the tree was
    /// rebuilt several times a second (review of 2026-11-17).
    func refreshTree() {
        guard !treeRefreshPending else { return }
        treeRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            self.treeRefreshPending = false
            self.drawTree()
        }
    }

    /// The tree from what is open now (no git, no disk).
    private func drawTree() {
        guard let tree = workspace?.tree, let projects else { return }
        let active = tabs?.activeTerminal
        let model = projects.projects.map { project -> WorkTreeProject in
            let worktrees = treeTasks[project.folder] ?? []
            var tasks = worktrees.map { worktree in
                WorkTreeTask(id: worktree.path, name: (worktree.path as NSString).lastPathComponent, state: .idle)
            }
            var own: [WorkTreeTerminal] = []
            for terminal in project.tabs.allTerminals {
                let row = Self.treeRow(terminal)
                let folder = terminal.currentDirectory ?? project.folder
                if let index = tasks.firstIndex(where: { folder == $0.id || folder.hasPrefix($0.id + "/") }) {
                    tasks[index].terminals.append(row)
                } else {
                    own.append(row)
                }
            }
            for index in tasks.indices {
                let states = tasks[index].terminals.compactMap(\.state)
                let review = WorktreesController.shared.store.task(tasks[index].id)?.status == .review
                tasks[index].state = review ? .review : Self.summary(states)
                tasks[index].agent = Self.agent(in: tasks[index].id)
            }
            return WorkTreeProject(id: project.folder, name: project.name, branch: treeBranches[project.folder] ?? "",
                                   tasks: tasks, terminals: own)
        }
        tree.show(model, chosen: active.map { .terminal(AppDelegate.key($0)) })
    }

    /// A terminal as a row: the agent's conversation or the program, its state, and where it is.
    static func treeRow(_ terminal: TerminalView) -> WorkTreeTerminal {
        let state: GlyphState? = switch terminal.agentStatus?.state {
        case .working: .working
        case .blocked: .needs
        case .done: .done
        case .failed: .failed
        case .idle: .idle
        default: nil
        }
        let agent = terminal.agentStatus != nil ? AppDelegate.conversationName(terminal) : ""
        // A program's title without the spinner in front (Claude Code outside the launcher animates
        // it, and the row changed every 0.3 s).
        let program = String(terminal.programTitle.drop { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
        let title = !agent.isEmpty ? agent : !program.isEmpty ? program
            : ((terminal.currentDirectory ?? "") as NSString).lastPathComponent
        return WorkTreeTerminal(id: AppDelegate.key(terminal), title: title, state: state)
    }

    /// A task's state from its terminals' (the anatomy's six): what needs you first, then what
    /// works, what failed, what is done; nothing running is idle.
    static func summary(_ states: [GlyphState]) -> GlyphState {
        for state in [GlyphState.needs, .working, .failed, .done] where states.contains(state) { return state }
        return .idle
    }

    /// "Claude · bkdg": the account of an agent session running in the task's folder.
    static func agent(in folder: String) -> String {
        guard let session = AgentsController.shared.sessions.first(where: { $0.cwd == folder || $0.cwd.hasPrefix(folder + "/") }) else { return "" }
        return "Claude · " + session.account.name
    }

    /// A row of the tree picked: a terminal's tab, a task's first terminal (or a new one in its
    /// folder), a project's tabs.
    func pickInTree(_ pick: WorkTreePick) {
        switch pick {
        case .terminal(let key):
            app.goToAgent(key: key, pid: 0)
        case .project(let folder):
            if let index = projects?.projects.firstIndex(where: { $0.folder == folder }) { projects?.select(index) }
        case .task(let folder):
            // Only in the project that has the task (another project's terminal there is not it).
            let owner = projects?.projects.first { project in (treeTasks[project.folder] ?? []).contains { $0.path == folder } }
            let terminal = owner?.tabs.allTerminals
                .first { ($0.currentDirectory ?? "") == folder || ($0.currentDirectory ?? "").hasPrefix(folder + "/") }
            if let owner, let index = projects?.projects.firstIndex(where: { $0 === owner }) { projects?.select(index) }
            if let terminal { app.goToAgent(key: AppDelegate.key(terminal), pid: 0) } else { tabs?.newTab(cwd: folder) }
        }
        refreshTree()
    }
}
