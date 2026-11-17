import AppKit
import SourceControl
import Menus
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
        tree.menuFor = { [weak self] folder in self?.treeMenu(task: folder) ?? [] }
        treeObserver = NotificationCenter.default.addObserver(forName: TerminalView.agentDidChange, object: nil, queue: .main) { [weak self] note in
            let sender = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                // Only this window's terminals: every window counting every agent did the same
                // git work N times (review of 2026-11-17).
                guard let self, let sender,
                      self.projects?.projects.contains(where: { $0.tabs.allTerminals.contains { ObjectIdentifier($0) == sender } }) == true else { return }
                self.refreshTree()
                self.countTreeDiffsSoon()
            }
        }
        let clock = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshTree() } }
        RunLoop.main.add(clock, forMode: .common)
        treeClock = clock
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
        // Where each task started (New Task kept it), for its diff.
        var starts: [String: String] = [:]
        for folder in folders {
            for task in treeTasks[folder] ?? [] { starts[task.path] = WorktreesController.shared.store.task(task.path)?.base }
        }
        treeLoad += 1
        let load = treeLoad
        let known = starts
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var found: [String: [TaskWorktree]] = [:]
            var branches: [String: String] = [:]
            var tallies: [String: (added: Int, removed: Int)] = [:]
            for folder in folders {
                // The main worktree and the project's own folder are not its tasks (a project that
                // is itself a worktree listed itself: review of 2026-11-17).
                let tasks = Array(WorktreesCore.list(repo: folder).dropFirst()).filter { $0.path != folder }
                found[folder] = tasks
                branches[folder] = AgentProject.of(folder).branch ?? ""
                for task in tasks {
                    if let tally = ReviewTally.of(worktree: task.path, start: known[task.path]) { tallies[task.path] = (tally.added, tally.removed) }
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, load == self.treeLoad else { return }
                    self.treeTasks = found
                    self.treeBranches = branches
                    self.treeTallies = tallies
                    // What is gone is forgotten: a task made again at the same path starts fresh.
                    let alive = Set(found.values.flatMap { $0.map(\.path) })
                    self.treeStates = self.treeStates.filter { alive.contains($0.key) }
                    self.treeUnread.formIntersection(alive)
                    // A task new since the last list had no start yet: counted again with it.
                    if found.values.flatMap({ $0 }).contains(where: { known[$0.path] == nil && WorktreesController.shared.store.task($0.path)?.base != nil }) {
                        self.countTreeDiffsSoon()
                    }
                    self.refreshTree()
                }
            }
        }
    }

    /// The diffs again a few seconds after an agent's status changes (it edited files): one git
    /// run per task for a burst, not one per status.
    /// After the burst: each status starts the wait again, so a long burst counts once at its end.
    func countTreeDiffsSoon() {
        treeTallyTimer?.invalidate()
        let timer = Timer(timeInterval: 3, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.loadTreeTasks() } }
        RunLoop.main.add(timer, forMode: .common)
        treeTallyTimer = timer
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
                    own.append(projectRow(row, terminal: terminal, folder: folder, project: project.folder))
                }
            }
            for index in tasks.indices { fillTask(&tasks[index]) }
            return WorkTreeProject(id: project.folder, name: project.name, branch: treeBranches[project.folder] ?? "",
                                   tasks: tasks, terminals: own)
        }
        tree.show(model, chosen: active.map { .terminal(AppDelegate.key($0)) })
    }

    /// A project's own terminal in full (the mockup's two lines): its name, under it who runs in
    /// it or where it is, what it waits for, and since when its state changed.
    private func projectRow(_ row: WorkTreeTerminal, terminal: TerminalView, folder: String, project: String) -> WorkTreeTerminal {
        var row = row
        let state = row.state ?? .idle
        if treeStates[row.id]?.state != state { treeStates[row.id] = (state, Date()) }
        if terminal.agentStatus != nil {
            row.detail = Self.agent(in: folder)
        } else {
            // A shell: "Terminal", and under it the folder it is in, from the project's.
            row.title = row.title == (folder as NSString).lastPathComponent ? T("Terminal", "Terminal") : row.title
            let name = (project as NSString).lastPathComponent
            row.detail = folder == project ? name
                : folder.hasPrefix(project + "/") ? name + "/" + String(folder.dropFirst(project.count + 1))
                : (folder as NSString).abbreviatingWithTildeInPath
        }
        row.waiting = Self.waiting(terminal.agentStatus) ?? ""
        row.age = treeStates[row.id].map { Self.age(since: $0.since) } ?? ""
        return row
    }

    /// A task's line beyond its name: its state (and since when), what news it has, who works on
    /// it, its diff, what it waits for and its comment.
    private func fillTask(_ task: inout WorkTreeTask) {
        let terminals = (projects?.projects ?? []).flatMap(\.tabs.allTerminals).filter { terminal in
            let folder = terminal.currentDirectory ?? ""
            return folder == task.id || folder.hasPrefix(task.id + "/")
        }
        let info = WorktreesController.shared.store.task(task.id)
        let state = info?.status == .review ? GlyphState.review : Self.summary(task.terminals.compactMap(\.state))
        // Looking: the app in front, this window with the keyboard, the task's terminal in it.
        let looking = NSApp.isActive && window.isKeyWindow && (tabs?.activeTerminal.map { terminals.contains($0) } ?? false)
        if treeStates[task.id]?.state != state {
            // A change while the owner looks elsewhere is news (bold) until the task is looked at.
            if treeStates[task.id] != nil, !looking, [.needs, .done, .failed].contains(state) { treeUnread.insert(task.id) }
            treeStates[task.id] = (state, Date())
        }
        if looking { treeUnread.remove(task.id) }
        task.state = state
        task.unread = treeUnread.contains(task.id)
        task.agent = Self.agent(in: task.id)
        task.added = treeTallies[task.id]?.added
        task.removed = treeTallies[task.id]?.removed
        task.waiting = terminals.lazy.compactMap { Self.waiting($0.agentStatus) }.first ?? ""
        task.age = treeStates[task.id].map { Self.age(since: $0.since) } ?? ""
        task.comment = info?.comment ?? ""
    }

    /// What a blocked agent waits for, in a few words.
    static func waiting(_ status: TerminalAgentStatus?) -> String? {
        guard let status, status.state == .blocked else { return nil }
        return switch status.kind {
        case .permission: T("waits for a permission", "espera uma permissão")
        case .question: T("asks you", "pergunta a você")
        case .auth: T("needs a login", "precisa de login")
        default: T("waits for you", "espera você")
        }
    }

    /// "now", "4m", "2h", "3d": since the state last changed.
    static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return T("now", "agora") }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }

    /// A task's right click (plan 27 phase B2): what the Tasks and Agents pages did, each a command;
    /// the status runs with the task, the rest after going to it (they act on the focused terminal).
    func treeMenu(task folder: String) -> [MenuEntry] {
        let terminals = (projects?.projects ?? []).flatMap(\.tabs.allTerminals).filter { terminal in
            let place = terminal.currentDirectory ?? ""
            return place == folder || place.hasPrefix(folder + "/")
        }
        // The agent's own terminal, not the first one there (it could be `npm run dev`).
        let agent = terminals.first { $0.agentStatus != nil || $0.agentResume != nil }
        /// The command run with `terminal` focused (they act on the focused terminal).
        func at(_ terminal: TerminalView, _ id: String) -> @MainActor () -> Void {
            { [weak self] in
                self?.app.goToAgent(key: AppDelegate.key(terminal), pid: 0)
                _ = self?.commands.run(id)
            }
        }
        var entries: [MenuEntry] = [
            MenuEntry(T("Go to Tab", "Ir à aba"), icon: .terminalWindow) { [weak self] in self?.pickInTree(.task(folder)) },
        ]
        if let any = agent ?? terminals.first {
            entries.append(MenuEntry(T("Review Changes", "Revisar as mudanças"), icon: .gitDiff, action: at(any, "git.review-open")))
        }
        if let agent {
            entries.append(MenuEntry(T("Hibernate the Agent", "Hibernar o agente"), icon: .clockCounterClockwise, action: at(agent, "agents.hibernate")))
        }
        entries.append(.separator)
        for status in TaskStatus.allCases {
            entries.append(MenuEntry(T("Status: ", "Status: ") + status.title, icon: .checkCircle) { [weak self] in
                _ = self?.commands.run("worktrees.set-status", request: CommandRequest(arguments: ["status": status.rawValue], folder: folder))
                self?.refreshTree()
            })
        }
        entries += [
            .separator,
            MenuEntry(T("Comment…", "Comentar…"), icon: .pencilSimple) { [weak self] in self?.askTreeComment(task: folder) },
            MenuEntry(T("Remove Task…", "Remover a tarefa…"), icon: .trash) { [weak self] in _ = self?.commands.run("worktrees.remove") },
        ]
        return entries
    }

    /// "Comment…" on a task: the words asked here, then worktrees.set-comment with the task.
    private func askTreeComment(task folder: String) {
        let alert = NSAlert()
        alert.messageText = T("Comment on ", "Comentar ") + (folder as NSString).lastPathComponent
        let field = NSTextField(string: WorktreesController.shared.store.task(folder)?.comment ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: T("Save", "Salvar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1B}"
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                _ = self?.commands.run("worktrees.set-comment", request: CommandRequest(arguments: ["comment": field.stringValue], folder: folder))
                self?.refreshTree()
            }
        }
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
