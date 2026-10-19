import AppKit
import StatusBar
import CommandPalette
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpCommands()
        let window = makeWindow()
        let tabs = TabsController(window: window)
        let workspace = WorkspaceView(tabs: tabs) { [weak self] id in self?.commands.run(id) }
        window.contentView = workspace
        self.window = window
        self.tabs = tabs
        self.workspace = workspace
        connectStatusBar(workspace.statusBar, to: tabs)
        tabs.newTab(cwd: NSHomeDirectory())
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
        commands.register(Command(
            id: "view.toggle-sidebar", title: "Mostrar ou esconder o painel lateral",
            keywords: ["sidebar", "explorer", "painel"], category: .view, defaultShortcut: "cmd+b",
            action: .run { [weak self] in self?.workspace?.toggleSidebar() }))
        commands.register(TerminalCommands.all)
        commands.register(TabCommands.all { [weak self] in self?.tabs })

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
