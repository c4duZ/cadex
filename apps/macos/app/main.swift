import AppKit
import StatusBar
import CommandPalette
import Editor
import Explorer
import Search
import Settings
import Shortcuts
import Tabs
import Terminal

/// Opens the window: tabs of terminals inside the Terax-like shell
/// (WorkspaceView). Spaces and the rest of the workspace come as their
/// features are built (CLAUDE.md, atlas).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let commands = CommandRegistry()
    private var menu: CommandMenu?
    private var dispatcher: ShortcutDispatcher?
    private var palette: CommandPaletteController?
    private var tabs: TabsController?
    private var workspace: WorkspaceView?
    private let settings = SettingsBridge()
    private var keymapLabels: (String) -> String? = { _ in nil }
    private var keymap: Keymap?
    private var settingsWindow: SettingsWindowController?
    private let folder = WorkspaceFolder()
    private var explorer: ExplorerController?
    private var search: SearchController?
    private var opener: FileOpener?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpCommands()
        let window = makeWindow()
        let tabs = TabsController(window: window)
        let opener = FileOpener(tabs: tabs)
        self.opener = opener
        explorer?.openFile = { [weak opener] path in opener?.open(path) }
        explorer?.onFolderChange = { [weak opener] folders in opener?.foldersChanged(folders) }
        let explorer = self.explorer!
        let workspace = WorkspaceView(tabs: tabs, explorer: explorer) { [weak self] id in self?.commands.run(id) }
        window.contentView = workspace
        self.window = window
        self.tabs = tabs
        self.workspace = workspace
        connectStatusBar(workspace.statusBar, to: tabs)
        explorer.revealSidebar = { [weak workspace] in workspace?.showSidebar() }
        settings.onLooks = { [weak workspace] image, vibrancy in workspace?.setLooks(image: image, vibrancy: vibrancy) }
        let looks = settings.store.settings.appearance
        workspace.setLooks(image: looks.backgroundImage.map { .init(path: $0, opacity: looks.backgroundOpacity, blur: looks.backgroundBlur) },
                           vibrancy: looks.vibrancy)
        tabs.newTab(cwd: folder.root)
        openLaunchItems(Self.launchFiles)
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
        }
    }

    /// The status bar follows the focused terminal's folder, and its folder
    /// menu takes that terminal there (docs/spec/status-bar.md).
    private func connectStatusBar(_ bar: StatusBarView, to tabs: TabsController) {
        tabs.onActiveChange = { [weak tabs, weak bar] in
            let terminal = tabs?.activeTerminal
            bar?.path = terminal?.currentDirectory
            bar?.canNavigate = terminal?.hasForegroundProcess == false
        }
        bar.onNavigate = { [weak tabs] folder in tabs?.activeTerminal?.changeDirectory(to: folder) }
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
        makeExplorer()
        makeSearch(palette: palette)
        commands.register(EditorCommands.all { [weak self] in self?.tabs?.activeDocument as? EditorDocument })
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
            let real = (file as NSString).resolvingSymlinksInPath
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
        guard let tabs else { return true }
        return tabs.shouldCloseAll(then: { sender.close() })
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let tabs, window?.isVisible == true else { return .terminateNow }
        let now = tabs.shouldCloseAll(
            then: { NSApp.reply(toApplicationShouldTerminate: true) },
            cancelled: { NSApp.reply(toApplicationShouldTerminate: false) })
        return now ? .terminateNow : .terminateLater
    }
}

let app = NSApplication.shared
// Run as a regular app (Dock icon, menu bar) even when launched as a bare
// executable during development, before there is an .app bundle.
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
