import AppKit
import StateGlyph
import Agents
import CommandPalette
import Explorer
import GitHistory
import Memory
import Orchestration
import Projects
import Strings
import Tabs
import Terminal

/// The projects in the window (docs/spec/projects.md): each project's tabs are made here, wired
/// like the window's (status bar, preview offers), and the saved documents are made again by the
/// FileOpener.
extension WindowSession {
    /// Made with the commands, before the window, so the palette and the
    /// shortcuts know project.*; the tabs are made later, in startProjects.
    func makeProjects(palette: CommandPaletteController) {
        // Named from the spaces.json beside the file, as before plan 27: the daemon that keeps
        // the sessions (terminal.keepSessions) keeps its name, and reopened panes find their shells.
        if isMain {
            let legacy = ProjectsFile.defaultURL.deletingLastPathComponent().appendingPathComponent("spaces.json")
            TerminalDaemon.shared.instance = Self.instanceName(legacy.path)
        }
        let projects = ProjectsController(fileURL: isMain ? ProjectsFile.defaultURL : nil) { [unowned self] in self.makeTabs() }
        projects.onSwitch = { [weak self] tabs in
            self?.hideHome()
            self?.workspace?.show(tabs)
            self?.refreshWorkColor()
            self?.followProject()
        }
        projects.onChange = { [weak self] in
            self?.refreshWorkColor()
            // A project opened or closed: the tasks are listed again (git, off the main thread);
            // a switch only redraws.
            self?.loadTreeTasks(onlyIfProjectsChanged: true)
            // The project's .ai-memory.toml, made once if it has none (plan 35 B).
            self?.noteMemoryMarkers()
        }
        projects.onTabsChange = { [weak self] in self?.refreshTree() }
        // No project open (plan 29): the home screen in the center.
        projects.onNone = { [weak self] in
            self?.showHome()
            self?.refreshTree()
        }
        commands.register(homeCommands())
        commands.register(ProjectsCommands.all(projects, palette: palette) { [weak self] in self?.chooseProjectFolder() })
        commands.register(projectEditCommands())
        self.projects = projects
    }

    /// project.new: the folder from the system's chooser becomes the workspace's and opens its
    /// project (or shows it, when it is open already).
    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = T("Open Project", "Abrir o projeto")
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK, let path = panel.url?.path, let self else { return }
                self.folder.open(path)
                self.projects?.open(folder: path)
            }
        }
    }

    private func makeTabs() -> TabsController {
        let tabs = TabsController(window: window)
        tabs.keepsSessions = isMain
        tabs.contextMenu = { [weak self] in self.flatMap { $0.menu?.popup(Self.tabActions + $0.memoryTabPins()) } ?? [] }
        // The memory paused in the tab's session (plan 35 I).
        tabs.markOf = Self.memoryMark
        // The task's menu that the tree had (status, review, hibernate, remove…), on its item.
        tabs.groupMenu = { [weak self] task in self?.treeMenu(task: task) ?? [] }
        tabs.runCommand = { [weak self] id in self?.commands.run(id) ?? false }
        tabs.paneMenu = { [weak self] in self?.paneMenu() ?? [] }
        // The bar shows the tabs of where you are: a task's (its worktree, as the tree lists them),
        // else the project's own (the Main mockup).
        tabs.groupOf = { [weak self] folder in
            // The project's page and the app's pages: one group of their own.
            if folder == BoardDocument.identity { return "board" }
            if let folder, ["project:", "cadex:", "automation:"].contains(where: folder.hasPrefix) { return "pages" }
            return self?.taskFolder(containing: folder) ?? ""
        }
        tabs.extrasOf = { [weak self] group in
            guard let self else { return [] }
            switch group {
            // Pages never put items in the bar (plan 34 A): their sections are inside them.
            case "board", "pages": return []
            // The tasks are in the sidebar and the place's menu, and Review is the top bar's button
            // (ADR 0039, plan 38 E): the bar holds only the place's tabs. A race's lanes compare.
            case "": return []
            default:
                return self.raceName(of: group) != nil
                    ? [TabsExtra(title: T("Compare", "Comparar"), command: "git.review-compare-worktrees", identity: "review:")] : []
            }
        }
        tabs.onCommandTick = { [weak self] in self?.refreshTree() }
        // Beside the terminal that showed the address (plan 28 phase E; the PreviewOne mockup).
        tabs.onOpenPreview = { [weak self] url in self?.openPreview(url, beside: true) }
        tabs.onOpenFile = { [weak self] path, beside in
            // A pasted image lives in the temporary folder, outside the
            // workspace: the media viewer reads only authorized folders.
            WorkspaceFolder.allow((path as NSString).deletingLastPathComponent)
            self?.opener?.open(path, beside: beside)
        }
        if let bar = workspace?.statusBar { connectStatusBar(bar, to: tabs) }
        return tabs
    }

    /// The saved projects come back, or the workspace's with a terminal in it. Without a folder on
    /// the command line, the last workspace folder too.
    func startProjects() {
        guard let projects else { return }
        let saved = projects.savedFile
        if !folder.launchedWithFolder, let path = saved?.folder, FileManager.default.fileExists(atPath: path) {
            folder.open(path)
        }
        projects.workspaceFolder = { [weak self] in self?.folder.root }
        // From the Dock with nothing saved open: the home screen; with a folder, its project.
        projects.start(folder: folder.root, openFolder: folder.launchedWithFolder || !isMain) { [weak self] identity in
            // Archive & History comes back too (plan 27 C): a tab, not a file.
            if identity == AgentHistoryDocument.identity, let self { return AgentHistoryDocument(page: self.makeHistoryPage()) }
            if identity.hasPrefix("project:settings:"), let self { return self.makeProjectSettings(String(identity.dropFirst("project:settings:".count))) }
            if identity.hasPrefix("project:"), let self { return self.makeProjectPage(String(identity.dropFirst("project:".count))) }
            if identity == BoardDocument.identity, let self { return self.makeBoard() }
            if identity == ProjectsListDocument.identity, let self { return self.makeProjectsPage() }
            if identity == AutomationsPageDocument.identity, let self { return self.makeAutomationsPage() }
            if identity == MemoryPanelDocument.identity, let self { return self.makeMemoryPanel() }
            return self?.opener?.makeDocument(identity: identity)
        }
        // The memory off in projects (plan 35 I): the main window's projects keep the flag.
        if isMain { connectMemoryOff(projects) }
        // Opened on a folder: the old projects come back and the folder becomes its own project
        // (docs/spec/projects.md), shown; a project it already had gets a terminal there unless one
        // is (opening the same folder again stacked tabs). It went into whichever project was
        // active before (review of 2026-11-17).
        if folder.launchedWithFolder, saved != nil {
            let before = projects.projects.count
            projects.open(folder: folder.root)
            if projects.projects.count == before, let tabs, !hasTerminal(in: folder.root, tabs) { tabs.newTab(cwd: folder.root) }
        }
        if isMain { closeUnclaimedTerminals(projects) }
        loadTreeTasks()
    }

    /// The main window came back (plan 19 E2): the daemon's sessions of this
    /// Cadex that no restored pane took back end, as does their saved output.
    private func closeUnclaimedTerminals(_ projects: ProjectsController) {
        guard TerminalPreferences.current.keepSessions else { return }
        let claimed = projects.projects.flatMap { $0.tabs.allTerminals.compactMap(\.keptID) }
        TerminalDaemon.shared.closeUnclaimed(claimed: claimed)
        // On disk now: after a crash the next launch takes these names back.
        projects.saveNow()
    }

    /// The daemon's names of this Cadex's sessions start with this: the path
    /// of the spaces.json beside the projects file (the name from before plan
    /// 27), hashed (FNV-1a, the same in every launch), so a test instance with
    /// its own file never ends the owner's sessions.
    static func instanceName(_ path: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in path.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return "c" + String(hash, radix: 16)
    }

    private func hasTerminal(in folder: String, _ tabs: TabsController) -> Bool {
        tabs.snapshot().items.contains { item in
            if case let .terminal(_, layout, _, _) = item { return layout.folders.contains(folder) }
            return false
        }
    }

    /// The task worktree a folder is in (the tree's lists), nil for the project's own.
    func taskFolder(containing folder: String?) -> String? {
        guard let folder, !folder.isEmpty else { return nil }
        return treeTasks.values.joined().map(\.path).filter { folder == $0 || folder.hasPrefix($0 + "/") }.max { $0.count < $1.count }
    }
}
