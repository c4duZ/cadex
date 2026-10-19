import AppKit
import StatusBar
import CommandPalette
import Editor
import Explorer
import Markdown
import MediaPreview
import Preview
import Search
import SourceControl
import GitHistory
import Spaces
import Settings
import Shortcuts
import Tabs
import Terminal

/// Opens the window: the spaces' tabs inside the Terax-like shell
/// (WorkspaceView), with the explorer, search, git and the viewers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    let commands = CommandRegistry()
    private var menu: CommandMenu?
    private var dispatcher: ShortcutDispatcher?
    private var palette: CommandPaletteController?
    var spaces: SpacesController?
    /// The shown space's tabs: every command acts on these.
    var tabs: TabsController? { spaces?.active }
    var workspace: WorkspaceView?
    private let settings = SettingsBridge()
    private var keymapLabels: (String) -> String? = { _ in nil }
    private var keymap: Keymap?
    private var settingsWindow: SettingsWindowController?
    let folder = WorkspaceFolder()
    private var explorer: ExplorerController?
    private var search: SearchController?
    var opener: FileOpener?
    private var markdown: MarkdownController?
    private var git: SourceControlController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpCommands()
        let window = makeWindow()
        self.window = window
        let opener = FileOpener(tabs: { [weak self] in self?.tabs },
                                every: { [weak self] in self?.spaces?.spaces.map(\.tabs) ?? [] })
        opener.onEditorOpened = { [weak self] document in self?.markdown?.attach(document) }
        opener.runCommand = { [weak self] id in self?.commands.run(id) ?? false }
        self.opener = opener
        explorer?.openFile = { [weak opener] path in opener?.open(path) }
        explorer?.onFolderChange = { [weak self, weak opener] folders in
            opener?.foldersChanged(folders)
            self?.git?.diskChanged(folders)
        }
        let explorer = self.explorer!
        let git = self.git!
        let workspace = WorkspaceView(explorer: explorer, git: git) { [weak self] id in self?.commands.run(id) }
        window.contentView = workspace
        self.workspace = workspace
        workspace.statusBar.onNavigate = { [weak self] folder in self?.tabs?.activeTerminal?.changeDirectory(to: folder) }
        explorer.revealSidebar = { [weak workspace] in workspace?.showSidebar(.files) }
        git.onOpenFile = { [weak opener] path in opener?.open(path) }
        git.onOpenDiff = { [weak opener] request in opener?.openDiff(request) }
        git.onMarks = { [weak explorer] marks in explorer?.gitMarks = marks }
        settings.onLooks = { [weak workspace] image, vibrancy in workspace?.setLooks(image: image, vibrancy: vibrancy) }
        let looks = settings.store.settings.appearance
        workspace.setLooks(image: looks.backgroundImage.map { .init(path: $0, opacity: looks.backgroundOpacity, blur: looks.backgroundBlur) },
                           vibrancy: looks.vibrancy)
        startSpaces()
        openLaunchItems(Self.launchFiles)
        CommandLine.arguments.dropFirst().filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }.forEach(openPreview)
        window.center()
        // CADEX_BACKGROUND=1 shows the window without taking the keyboard,
        // for checking the app while someone else uses the machine: opening
        // it activated the app and sent the owner's typing into a terminal
        // (2026-10-19).
        if ProcessInfo.processInfo.environment["CADEX_BACKGROUND"] == "1" {
            window.orderFrontRegardless()
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// The title area is the app's (fullSizeContentView, transparent title
    /// bar); an empty compact toolbar makes it 38 points tall with the window
    /// buttons centered in it, as in Terax.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbar = NSToolbar()
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 600, height: 360)
        window.title = "Cadex"
        window.delegate = self
        // A window made in code frees itself on close by default, leaving
        // self.window dangling; applicationShouldTerminate then crashed
        // reading it (EXC_BAD_ACCESS, crash reports of 2026-10-19).
        window.isReleasedWhenClosed = false
        return window
    }

    /// The tree of the workspace folder; its commands act on the focused
    /// terminal through the tabs, and hidden files are a saved preference.
    /// Made with the commands, before settings build the keymap.
    private func makeExplorer() {
        let explorer = ExplorerController(root: folder.root) { [weak self] id in self?.commands.run(id) ?? false }
        explorer.openInTerminal = { [weak self] path in self?.tabs?.activeTerminal?.changeDirectory(to: path) }
        explorer.onShowHiddenChange = { [weak self] show in self?.settings.store.update { $0.explorer.showHidden = show } }
        commands.register(ExplorerCommands.all(explorer))
        self.explorer = explorer
    }

    /// A preview tab for `url` (empty: a blank one); the tab already showing
    /// that address is reloaded instead (docs/spec/preview.md).
    func openPreview(_ url: String) {
        guard let tabs else { return }
        if let existing = tabs.document(identity: PreviewDocument.identity(for: url)) as? PreviewDocument {
            existing.reload()
            return tabs.open(existing)
        }
        tabs.open(PreviewDocument(url: url))
    }

    /// ⌘P and ⌘⇧F over the workspace folder; the chosen file opens in a tab.
    private func makeSearch(palette: CommandPaletteController) {
        let search = SearchController(root: folder.root, showHidden: true) { [weak self] path, line in
            self?.opener?.open(path, line: line)
        }
        commands.register(SearchCommands.all(search, palette: palette))
        self.search = search
    }

    /// The workspace folder and the hidden-files preference reach the
    /// explorer and the search together.
    private func connectFolder() {
        settings.onExplorer = { [weak self] prefs in
            guard let self else { return }
            self.explorer?.showHidden = prefs.showHidden
            self.search?.setRoot(self.folder.root, showHidden: prefs.showHidden)
        }
        folder.onChange = { [weak self] root in
            guard let self else { return }
            self.explorer?.setRoot(root)
            self.search?.setRoot(root, showHidden: self.explorer?.showHidden ?? true)
            self.markdown?.setRoot(root)
            self.git?.setFolder(root)
            self.spaces?.scheduleSave()
        }
    }

    /// The status bar follows the focused terminal's folder, and its folder
    /// menu takes that terminal there (docs/spec/status-bar.md).
    func connectStatusBar(_ bar: StatusBarView, to tabs: TabsController) {
        tabs.onActiveChange = { [weak tabs, weak bar] in
            let terminal = tabs?.activeTerminal
            bar?.path = terminal?.currentDirectory
            bar?.canNavigate = terminal?.hasForegroundProcess == false
        }
    }

    /// Every feature registers its commands; the menu and the shortcuts
    /// come from the registry (ADR 0005).
    private func setUpCommands() {
        // The palette shows each command's shortcut, which settings can
        // change; it reads the current one through keymapLabels.
        let palette = CommandPaletteController(registry: commands) { [weak self] in self?.keymapLabels($0) }
        self.palette = palette
        commands.register(palette.openCommand)
        commands.register(StandardCommands.all)
        let settingsWindow = SettingsWindowController(
            store: settings.store, registry: commands,
            keymap: { [weak self] in self?.keymap ?? Keymap(registry: CommandRegistry()) },
            suspendShortcuts: { [weak self] on in self?.dispatcher?.isSuspended = on })
        self.settingsWindow = settingsWindow
        commands.register(settingsWindow.openCommand)
        commands.register(Command(
            id: "view.toggle-sidebar", title: "Mostrar ou esconder o painel lateral",
            keywords: ["sidebar", "explorer", "painel"], category: .view, defaultShortcut: "cmd+b",
            action: .run { [weak self] in self?.workspace?.toggleSidebar() }))
        commands.register(TerminalCommands.all)
        commands.register(WorkspaceCommands.all(folder, window: { [weak self] in self?.window },
                                                terminalFolder: { [weak self] in self?.tabs?.activeTerminal?.currentDirectory }))
        commands.register(TabCommands.all { [weak self] in self?.tabs })
        makeSpaces(palette: palette)
        makeExplorer()
        makeSearch(palette: palette)
        let git = SourceControlController(folder: folder.root) { [weak self] id in self?.commands.run(id) ?? false }
        self.git = git
        commands.register(SourceControlCommands.all(git, palette: palette) { [weak self] in
            self?.tabs?.activeDocument as? DiffDocument
        })
        commands.register(Command(
            id: "git.show", title: "Mostrar o Git", keywords: ["source control", "git", "mudanças", "commit"],
            category: .view, defaultShortcut: "cmd+shift+g",
            action: .run { [weak self] in
                self?.workspace?.showSidebar(.git)
                self?.git?.refresh()
            }))
        commands.register(HistoryCommands.all(
            open: { [weak self] in if let root = self?.git?.repositoryRoot { self?.opener?.openHistory(root) } },
            repository: { [weak self] in self?.git?.repositoryRoot },
            active: { [weak self] in self?.tabs?.activeDocument as? HistoryDocument }))
        commands.register(EditorCommands.all { [weak self] in self?.tabs?.activeDocument as? EditorDocument })
        commands.register(MediaCommands.all { [weak self] in self?.tabs?.activeDocument as? MediaDocument })
        commands.register(PreviewCommands.all(open: { [weak self] url in self?.openPreview(url) },
                                              active: { [weak self] in self?.tabs?.activeDocument as? PreviewDocument }))
        let markdown = MarkdownController(root: folder.root, findFiles: { [weak self] in self?.search?.findFiles($0) ?? [] },
                                          open: { [weak self] path, line in self?.opener?.open(path, line: line) })
        self.markdown = markdown
        commands.register(MarkdownCommands.all(markdown, palette: palette) { [weak self] in
            self?.tabs?.activeDocument as? EditorDocument
        })
        connectFolder()

        settings.onShortcuts = { [weak self] shortcuts in self?.applyShortcuts(shortcuts) }
        settings.start()
    }

    /// Builds the keymap from the commands' defaults and the shortcuts in
    /// settings.json, then the menu and the dispatcher from it. Runs again
    /// when the shortcuts change.
    private func applyShortcuts(_ shortcuts: [String: String?]) {
        var keymap = Keymap(registry: commands)
        keymap.applyPreferences(shortcuts, registry: commands)
        keymap.problems.forEach { NSLog("atalhos: %@", $0) }
        let finalKeymap = keymap
        self.keymap = keymap
        keymapLabels = { finalKeymap.combo(for: $0)?.label }

        let menu = CommandMenu(registry: commands) { finalKeymap.combo(for: $0)?.menuKeyEquivalent }
        NSApp.mainMenu = menu.build()
        self.menu = menu
        if let dispatcher {
            dispatcher.update(keymap: keymap)
        } else {
            let dispatcher = ShortcutDispatcher(registry: commands, keymap: keymap)
            dispatcher.start()
            self.dispatcher = dispatcher
        }
    }

    /// A folder dropped on the Dock icon becomes the workspace
    /// (docs/spec/workspace.md). Needs the .app bundle's document types,
    /// which come with packaging (plan 7).
    func application(_ application: NSApplication, open urls: [URL]) {
        openLaunchItems(urls.map(\.path))
    }

    /// Files (not folders: WorkspaceFolder takes those) named on the
    /// command line, absolute.
    private static var launchFiles: [String] {
        let cwd = FileManager.default.currentDirectoryPath
        return CommandLine.arguments.dropFirst().compactMap { arg in
            guard !arg.hasPrefix("-") else { return nil }
            let path = (arg as NSString).isAbsolutePath ? arg : cwd + "/" + arg
            var isFolder: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder) && !isFolder.boolValue ? path : nil
        }
    }

    /// Folders and files given at launch (command line) or dropped on the
    /// Dock icon: a folder becomes the workspace; a file opens in a tab,
    /// its folder becoming the workspace when it is outside the current one.
    private func openLaunchItems(_ paths: [String]) {
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// The tabs ask before closing over a running program; close() after
    /// the confirmation does not come back here.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let spaces else { return true }
        spaces.saveNow()
        return spaces.shouldCloseAll(then: { sender.close() })
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let spaces, window?.isVisible == true else { return .terminateNow }
        let now = spaces.shouldCloseAll(
            then: { NSApp.reply(toApplicationShouldTerminate: true) },
            cancelled: { NSApp.reply(toApplicationShouldTerminate: false) })
        return now ? .terminateNow : .terminateLater
    }

    /// The spaces as they were at the end, for the next launch.
    func applicationWillTerminate(_ notification: Notification) {
        spaces?.saveNow()
    }
}

let app = NSApplication.shared
// Run as a regular app (Dock icon, menu bar) even when launched as a bare
// executable during development, before there is an .app bundle.
app.setActivationPolicy(.regular)
// The bare executable has no bundle, so no icon: the Dock showed a generic
// one in development while Cadex.app had ours (owner, 2026-10-19).
if Bundle.main.bundleIdentifier == nil {
    let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..")
    app.applicationIconImage = NSImage(contentsOf: repo.appendingPathComponent("docs/cadex-icon.png").standardized)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
