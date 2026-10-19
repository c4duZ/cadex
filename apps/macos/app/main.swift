import AppKit
import CommandPalette
import Shortcuts
import Terminal

/// Opens one window with a terminal. Tabs, spaces and the rest of the
/// workspace come as their features are built (CLAUDE.md, atlas).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private let commands = CommandRegistry()
    private var menu: CommandMenu?
    private var dispatcher: ShortcutDispatcher?

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
        window.contentView = TerminalView(frame: frame, cwd: NSHomeDirectory())
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Every feature registers its commands; the menu and the shortcuts
    /// come from the registry (ADR 0005).
    private func setUpCommands() {
        commands.register(StandardCommands.all)
        commands.register(TerminalCommands.all)

        var keymap = Keymap(registry: commands)
        keymap.applyPreferences(from: Keymap.preferencesFile, registry: commands)
        keymap.problems.forEach { NSLog("atalhos: %@", $0) }

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

    /// The terminal asks before closing over a running program; close()
    /// after the confirmation does not come back here.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let terminal = sender.contentView as? TerminalView else { return true }
        return terminal.shouldClose(then: { sender.close() })
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let terminal = window?.contentView as? TerminalView, window?.isVisible == true else { return .terminateNow }
        let now = terminal.shouldClose(
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
