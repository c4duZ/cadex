import Agents
import AppKit
import StateGlyph
import Worktrees
import Menus
import StatusBar
import GitHistory
import Home
import CommandPalette
import Editor
import Explorer
import Markdown
import Memory
import Preview
import Search
import Settings
import Shortcuts
import SourceControl
import Projects
import Tabs

/// One window (docs/spec/workspace.md): its workspace folder, spaces and
/// tabs, explorer, search and git, and its own commands, which the menu and
/// the shortcuts run while it has the focus. ⌘N makes another; only the
/// main one (opened with the app) saves its spaces.
@MainActor
final class WindowSession: NSObject, NSWindowDelegate {
    let window: NSWindow
    let commands = CommandRegistry()
    var menu: CommandMenu?
    /// The app menu for this window's commands, set when it is key.
    private(set) var mainMenu: NSMenu?
    var palette: CommandPaletteController?
    var projects: ProjectsController?
    /// The shown space's tabs: every command acts on these.
    var tabs: TabsController? { projects?.active }
    var workspace: WorkspaceView?
    let folder: WorkspaceFolder
    /// The window the app opened with: its spaces are saved and restored.
    let isMain: Bool
    unowned let app: AppDelegate
    var explorer: ExplorerController?
    var search: SearchController?
    var opener: FileOpener?
    var markdown: MarkdownController?
    var git: SourceControlController?
    /// The focused terminal's folder last seen, and whether the tree follows
    /// it (FolderFollow.swift).
    var lastTerminalFolder: String?
    var followTerminal = true
    /// The sidebar's Git History page, made the first time it shows
    /// (SidebarWiring.swift); nil while nobody opened it, so it costs nothing.
    var panelHistory: HistoryDocument?
    let panelHistoryHost = NSView()
    /// The status bar's Terminals item (StatusBarWiring.swift).
    var terminalsLabel: StatusLabel?
    /// The status bar's Project, keep-awake and update items (StatusBarItems.swift).
    var projectLabel: StatusLabel?
    var lastBranch: SourceControlController.Branch?
    var keepAwakeLabel: StatusLabel?
    var updateLabel: StatusLabel?
    var terminalsItem: StatusItem?
    /// The work's tree: the tasks of each project, listed by git off the main thread, and the
    /// worktrees' watch (TreeWiring.swift).
    var treeTasks: [String: [TaskWorktree]] = [:]
    /// Each project's branch, read with its tasks (not on every redraw: review of 2026-11-17).
    var treeBranches: [String: String] = [:]
    var treeWatch: UUID?
    var treeObserver: NSObjectProtocol?
    /// The newest list asked: an older one that comes back later is dropped.
    var treeLoad = 0
    /// The project folders the tasks were last listed for: a switch alone lists nothing.
    var treeFolders: [String] = []
    /// A redraw is on its way: changes in a burst (a title, a status) make one.
    var treeRefreshPending = false
    /// Each task's lines added and removed against its start, counted off the main thread.
    var treeTallies: [String: (added: Int, removed: Int)] = [:]
    /// Each task's state and since when (the row's age), and the tasks changed while not looked at
    /// (the name in bold).
    var treeStates: [String: (state: GlyphState, since: Date)] = [:]
    var treeUnread: Set<String> = []
    /// A count of the diffs is on its way: an agent's statuses in a burst make one.
    var treeTallyTimer: Timer?
    /// The rows' age moves on by itself: a redraw a minute.
    var treeClock: Timer?
    /// The pane headers' agent details (PaneHeaderWiring.swift): the agent notice and the minute clock.
    var paneHeaderObserver: NSObjectProtocol?
    var paneHeaderClock: Timer?
    /// The New Task sheet while it shows (NewTaskWiring.swift).
    var newTaskSheet: NewTaskSheet?
    /// The home screen while shown, and its choices (HomeWiring.swift).
    var home: HomeView?
    var homeChoice = HomeChoice()
    /// The agents' permissions at the foot of their panes (PanePermissionWiring.swift).
    var panePermissionWatch: UUID?
    /// The Agents page, for its sub-tabs (AgentsWiring.swift).
    /// The status bar's Agent usage item, for the theme's colors.
    weak var usageStrip: AgentUsageStrip?
    /// The bell's popover (AgentsAttention.swift).
    let bellPanel = AnchoredPanel()
    /// The bell's page (AgentsAttention.swift), for its sub-tab.
    weak var attentionPage: AgentAttentionView?
    /// The Ports item's label and what it last read (SSHWiring.swift).
    weak var portsLabel: StatusLabel?
    var ports: [UInt16] = []
    /// The Docker context each terminal was told to use (plan 23,
    /// machines.docker-context), by terminal; the status bar shows the focused one's.
    var dockerContexts: [ObjectIdentifier: String] = [:]
    weak var dockerLabel: StatusLabel?
    weak var dockerItem: StatusItem?
    var portsCard: HoverCard?
    /// The Memory page (MemoryPageWiring.swift) and its History watch,
    /// held only while the page shows.
    weak var memoryPage: MemoryView?
    var memoryHistoryWatch: UUID?

    var settings: SettingsBridge { app.settings }

    init(app: AppDelegate, folder: WorkspaceFolder, isMain: Bool) {
        self.app = app
        self.folder = folder
        self.isMain = isMain
        window = Self.makeWindow()
        super.init()
        window.delegate = self
        setUpCommands()
        connectWindow()
        let current = settings.store.settings
        applyExplorer(current.explorer)
        applyMarkdown(current.markdown)
        let looks = current.appearance
        applyLooks(looks.backgroundImage.map { .init(path: $0, opacity: looks.backgroundOpacity, blur: looks.backgroundBlur) },
                   vibrancy: looks.vibrancy)
        startProjects()
        startPaneHeaders()
        startPanePermissions()
    }

    /// The title area is the app's (fullSizeContentView, transparent title
    /// bar); an empty compact toolbar makes it 38 points tall with the window
    /// buttons centered in it.
    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unifiedCompact
        // Room for the window buttons, the bar's group, one tab and a
        // terminal of a few columns; 600 pt felt like a wall (2026-10-19).
        window.minSize = NSSize(width: 480, height: 300)
        window.title = "Cadex"
        // A window made in code frees itself on close by default, leaving
        // self.window dangling; applicationShouldTerminate then crashed
        // reading it (EXC_BAD_ACCESS, crash reports of 2026-10-19).
        window.isReleasedWhenClosed = false
        return window
    }

    /// The opener, the shell view and the links between the features.
    private func connectWindow() {
        let opener = FileOpener(tabs: { [weak self] in self?.tabs },
                                every: { [weak self] in self?.projects?.projects.map(\.tabs) ?? [] },
                                opensBeside: { [weak self] in self?.settings.opensBeside ?? true })
        opener.onEditorOpened = { [weak self] document in self?.markdown?.attach(document) }
        opener.runCommand = { [weak self] id in self?.commands.run(id) ?? false }
        opener.onPickElement = { [weak self] delivery in
            let driving = delivery.agentTerminal.flatMap { key in self?.app.locate { AppDelegate.key($0) == key }?.terminal }
            return ElementPickDelivery.deliver(delivery, tabs: self?.tabs, toClipboard: self?.settings.picksToClipboard ?? false, driving: driving)
        }
        opener.picksScreenshot = { [weak self] in self?.settings.picksScreenshot ?? true }
        self.opener = opener
        guard let explorer, let git else { return }
        explorer.openFile = { [weak opener] path in opener?.open(path) }
        explorer.openFileAs = { [weak opener] path, beside in opener?.open(path, beside: beside) }
        explorer.onFolderChange = { [weak self, weak opener] folders in
            opener?.foldersChanged(folders)
            self?.git?.diskChanged(folders)
            self?.panelHistory?.diskChanged(folders)
            self?.reviewsDiskChanged(folders)
            AuthorshipHub.diskChanged(folders)
        }
        let workspace = WorkspaceView(explorer: explorer, tree: makeTree(), inspector: makeInspector(explorer: explorer, git: git)) { [weak self] id in self?.commands.run(id) }
        window.contentView = workspace
        self.workspace = workspace
        workspace.titleBar.newMenu = { [weak self] in self?.menu?.popup(Self.newOpeners) ?? [] }
        showLocation(folder.root)
        showPanelFolder(folder.root)
        applyInspector(settings.store.settings.inspector)
        // A window opened later shows what already needs you, not only the next change.
        workspace.titleBar.setBell(count: AgentAttention.shared.unseen)
        workspace.statusBar.onNavigate = { [weak self] folder in self?.tabs?.activeTerminal?.changeDirectory(to: folder) }
        setUpStatusBar(workspace.statusBar, git: git)
        // After the status bar's items exist: they show keep-awake and the update (review of
        // 2026-11-17: before, a new window drew them in the wrong state).
        showPower()
        showUpdate()
        explorer.revealSidebar = { [weak workspace] in workspace?.showInspector("files") }
        git.onOpenFile = { [weak opener] path, beside in opener?.open(path, beside: beside) }
        wireChanges(git)
        git.onOpenDiff = { [weak opener] request, beside in opener?.openDiff(request, beside: beside) }
        git.onMarks = { [weak explorer] marks in explorer?.gitMarks = marks }
        startPerfHooks()
    }

    /// Whether a terminal in any space of this window runs a program.
    var hasRunningProgram: Bool { projects?.projects.contains { $0.tabs.hasRunningProgram } ?? false }

    /// The menu and the shortcut labels from the keymap in effect.
    func applyKeymap(_ keymap: Keymap) {
        let menu = CommandMenu(registry: commands) { keymap.combo(for: $0)?.menuKeyEquivalent }
        mainMenu = menu.build()
        self.menu = menu
        workspace?.inspector.setShortcut(app.keymapLabel("inspector.toggle"))
    }

    // MARK: Settings, from SettingsBridge through the app

    func applyExplorer(_ prefs: Settings.Explorer) {
        explorer?.showHidden = prefs.showHidden
        followTerminal = prefs.followTerminal
        search?.setRoot(folder.root, showHidden: prefs.showHidden)
    }

    func applyMarkdown(_ prefs: Settings.Markdown) {
        markdown?.opensRendered = prefs.openAs == "rendered"
    }

    func applyLooks(_ image: WindowBackdrop.Image?, vibrancy: Bool) {
        workspace?.setLooks(image: image, vibrancy: vibrancy)
    }

    // MARK: Opening things

    /// A preview tab for `url` (empty: a blank one); the tab already showing
    /// that address is reloaded instead (docs/spec/preview.md).
    func openPreview(_ url: String, beside: Bool? = nil) {
        opener?.openPreview(url, beside: beside)
    }

    /// Folders and files given at launch (command line) or dropped on the
    /// Dock icon: a folder becomes the workspace; a file opens in a tab,
    /// its folder becoming the workspace when it is outside the current one.
    func openLaunchItems(_ paths: [String]) {
        var isFolder: ObjCBool = false
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0, isDirectory: &isFolder) }
        let folders = existing.filter { FileManager.default.fileExists(atPath: $0, isDirectory: &isFolder) && isFolder.boolValue }
        if let first = folders.first { folder.open(first) }
        for file in existing where !folders.contains(file) {
            let real = FileOpener.canonical(file)
            if !real.hasPrefix(folder.root + "/") { folder.open((real as NSString).deletingLastPathComponent) }
            opener?.open(real)
        }
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        app.sessionBecameKey(self)
    }

    /// In full screen macOS puts the toolbar in a band of its own over the
    /// content, which covered the title bar the app draws: the bar showed
    /// empty (owner, 2026-10-19). The (empty) toolbar goes while in full
    /// screen; the title bar view moves to the edge (TitleBarView).
    func windowWillEnterFullScreen(_ notification: Notification) {
        window.toolbar?.isVisible = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        window.toolbar?.isVisible = true
    }

    /// The tabs ask before closing over a running program; close() after
    /// the confirmation does not come back here.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let projects else { return true }
        projects.saveNow()
        return projects.shouldCloseAll(then: { sender.close() })
    }

    /// Its shells end with it: with another window open the app goes on.
    func windowWillClose(_ notification: Notification) {
        // What this window watched lets go: the tree's tasks, the bar's items.
        if let treeWatch { WorktreesController.shared.stop(treeWatch) }
        if let treeObserver { NotificationCenter.default.removeObserver(treeObserver) }
        treeClock?.invalidate()
        if let paneHeaderObserver { NotificationCenter.default.removeObserver(paneHeaderObserver) }
        paneHeaderClock?.invalidate()
        if let panePermissionWatch { AgentAttention.shared.stop(panePermissionWatch) }
        treeTallyTimer?.invalidate()
        workspace?.statusBar.stopReading()
        bellPanel.close()
        projects?.closeAll()
        app.sessionClosed(self)
    }
}
