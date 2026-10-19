import AppKit
import CommandPalette
import Shortcuts
import Tabs
import Terminal

/// Opens one window with tabs of terminals. Spaces and the rest of the
/// workspace come as their features are built (CLAUDE.md, atlas).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let commands = CommandRegistry()
    private var menu: CommandMenu?
    private var dispatcher: ShortcutDispatcher?
    private var palette: CommandPaletteController?
    private var tabs: TabsController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpCommands()
        let frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Cadex"
        window.delegate = self
        // A window made in code frees itself on close by default, leaving
        // self.window dangling; applicationShouldTerminate then crashed
        // reading it (EXC_BAD_ACCESS, crash reports of 2026-10-19).
        window.isReleasedWhenClosed = false
        let tabs = TabsController(window: window)
        window.contentView = tabs.view
        self.tabs = tabs
        tabs.newTab(cwd: NSHomeDirectory())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Every feature registers its commands; the menu and the shortcuts
    /// come from the registry (ADR 0005).
    private func setUpCommands() {
        // The palette shows each command's shortcut, known only once the
        // keymap is built; it reads it through this box.
        var labels: (String) -> String? = { _ in nil }
        let palette = CommandPaletteController(registry: commands) { labels($0) }
        self.palette = palette
        commands.register(palette.openCommand)
        commands.register(StandardCommands.all)
        commands.register(TerminalCommands.all)
        commands.register(TabCommands.all { [weak self] in self?.tabs })

        var keymap = Keymap(registry: commands)
        keymap.applyPreferences(from: Keymap.preferencesFile, registry: commands)
        keymap.problems.forEach { NSLog("atalhos: %@", $0) }
        let finalKeymap = keymap
        labels = { finalKeymap.combo(for: $0)?.label }

        let menu = CommandMenu(registry: commands) { keymap.combo(for: $0)?.menuKeyEquivalent }
        NSApp.mainMenu = menu.build()
        self.menu = menu
        let dispatcher = ShortcutDispatcher(registry: commands, keymap: keymap)
        dispatcher.start()
        self.dispatcher = dispatcher
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
