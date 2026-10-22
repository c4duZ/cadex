import Agents
import AppKit
import Menus
import StatusBar
import GitHistory
import CommandPalette
import Editor
import Explorer
import Markdown
import Preview
import Search
import Settings
import Shortcuts
import SourceControl
import Spaces
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
    var spaces: SpacesController?
    /// The shown space's tabs: every command acts on these.
    var tabs: TabsController? { spaces?.active }
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
    var sidebarHistory: HistoryDocument?
    let sidebarHistoryHost = NSView()
    /// The status bar's Terminals item (StatusBarWiring.swift).
    var terminalsLabel: StatusLabel?
    var terminalsItem: StatusItem?
    /// The Agents icon's dot, watched while the icon is in the sidebar (AgentsWiring.swift).
    var agentsDotToken: UUID?
    /// The Agents page, for its sub-tabs (AgentsWiring.swift).
    /// The status bar's Agent usage item, for the theme's colors.
    weak var usageStrip: AgentUsageStrip?
    /// The Ports item's label and what it last read (SSHWiring.swift).
    weak var portsLabel: StatusLabel?
    var ports: [UInt16] = []
    var portsCard: HoverCard?

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
        startSpaces()
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
                                every: { [weak self] in self?.spaces?.spaces.map(\.tabs) ?? [] },
                                opensBeside: { [weak self] in self?.settings.opensBeside ?? true })
        opener.onEditorOpened = { [weak self] document in self?.markdown?.attach(document) }
        opener.runCommand = { [weak self] id in self?.commands.run(id) ?? false }
        opener.onPickElement = { [weak self] delivery in
            ElementPickDelivery.deliver(delivery, tabs: self?.tabs, toClipboard: self?.settings.picksToClipboard ?? false)
        }
        opener.picksScreenshot = { [weak self] in self?.settings.picksScreenshot ?? true }
        self.opener = opener
        guard let explorer, let git else { return }
        explorer.openFile = { [weak opener] path in opener?.open(path) }
        explorer.openFileAs = { [weak opener] path, beside in opener?.open(path, beside: beside) }
        explorer.onFolderChange = { [weak self, weak opener] folders in
            opener?.foldersChanged(folders)
            self?.git?.diskChanged(folders)
            self?.sidebarHistory?.diskChanged(folders)
        }
        let workspace = WorkspaceView(explorer: explorer, sidebar: makeSidebar(explorer: explorer, git: git)) { [weak self] id in self?.commands.run(id) }
        window.contentView = workspace
        self.workspace = workspace
        workspace.titleBar.newMenu = { [weak self] in self?.menu?.popup(Self.newOpeners) ?? [] }
        workspace.titleBar.spaceMenu = { [weak self] in self?.menu?.popup(Self.spaceActions) ?? [] }
        showPower()
        showUpdate()
        workspace.statusBar.onNavigate = { [weak self] folder in self?.tabs?.activeTerminal?.changeDirectory(to: folder) }
        setUpStatusBar(workspace.statusBar, git: git)
        explorer.revealSidebar = { [weak workspace] in workspace?.showSidebar("files") }
        git.onOpenFile = { [weak opener] path, beside in opener?.open(path, beside: beside) }
        git.onOpenDiff = { [weak opener] request, beside in opener?.openDiff(request, beside: beside) }
        git.onMarks = { [weak self, weak explorer] marks in
            explorer?.gitMarks = marks
            self?.showGitBadge(marks)
        }
        startPerfHooks()
    }

    /// Whether a terminal in any space of this window runs a program.
    var hasRunningProgram: Bool { spaces?.spaces.contains { $0.tabs.hasRunningProgram } ?? false }

    /// Keep-awake's icon in the title bar: filled while on, its tip the state.
    func showPower() {
        workspace?.titleBar.setPower(on: app.power.mode != .off, tip: app.powerTip)
    }

    /// The update button, only while there is one to install or finish.
    func showUpdate() {
        workspace?.titleBar.setUpdate(visible: app.updates.showsButton, tip: app.updates.buttonTip)
    }

    /// The menu and the shortcut labels from the keymap in effect.
    func applyKeymap(_ keymap: Keymap) {
        let menu = CommandMenu(registry: commands) { keymap.combo(for: $0)?.menuKeyEquivalent }
        mainMenu = menu.build()
        self.menu = menu
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
        guard let spaces else { return true }
        spaces.saveNow()
        return spaces.shouldCloseAll(then: { sender.close() })
    }

    /// Its shells end with it: with another window open the app goes on.
    func windowWillClose(_ notification: Notification) {
        // What this window watched lets go: the agents' dot, the bar's items.
        if let workspace { updateAgentsDot(shown: false, on: workspace.sidebar) }
        workspace?.statusBar.stopReading()
        spaces?.closeAll()
        app.sessionClosed(self)
    }
}
