import AppKit
import CommandPalette
import Explorer
import Menus
import Settings
import Shortcuts
import Tabs
import Themes

/// What the windows share: settings, the settings window, the keymap and
/// the shortcut dispatcher. Each window is a WindowSession; ⌘N opens
/// another (docs/spec/workspace.md).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsBridge()
    private(set) var sessions: [WindowSession] = []
    /// The window the menu and the shortcuts act on.
    private weak var current: WindowSession?
    private var dispatcher: ShortcutDispatcher?
    private var keymap: Keymap?
    private var shortcuts: [String: String?] = [:]
    /// The commands' titles and defaults for the settings window and the
    /// keymap: the same in every window, copied from the main one.
    private let catalog = CommandRegistry()
    private lazy var settingsWindow = SettingsWindowController(
        store: settings.store, registry: catalog,
        keymap: { [weak self] in self?.keymap ?? Keymap(registry: CommandRegistry()) },
        suspendShortcuts: { [weak self] on in self?.dispatcher?.isSuspended = on })

    var settingsCommand: Command { settingsWindow.openCommand }

    func applicationDidFinishLaunching(_ notification: Notification) {
        connectSettings()
        settings.start()
        // The popup menus take the theme's colors, the same as ⌘K's.
        ThemeStore.shared.observe { theme in
            let ui = theme.interface
            MenuStyle.current = MenuStyle(
                background: ui.panel.nsColor, border: ui.panelBorder.nsColor, text: ui.text.nsColor,
                secondaryText: ui.secondaryText.nsColor, selection: ui.tabActive.nsColor, accent: ui.accent.nsColor,
                keycap: ui.field.nsColor)
        }
        let main = WindowSession(app: self, folder: WorkspaceFolder(), isMain: true)
        sessions.append(main)
        catalog.register(main.commands.commands)
        applyShortcuts()
        main.openLaunchItems(Self.launchFiles)
        CommandLine.arguments.dropFirst().filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }.forEach(main.openPreview)
        main.window.center()
        // CADEX_BACKGROUND=1 shows the window without taking the keyboard,
        // for checking the app while someone else uses the machine: opening
        // it activated the app and sent the owner's typing into a terminal
        // (2026-10-19).
        if ProcessInfo.processInfo.environment["CADEX_BACKGROUND"] == "1" {
            sessionBecameKey(main)
            main.window.orderFrontRegardless()
        } else {
            main.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// "Nova janela" (⌘N): a terminal in the workspace folder of the window
    /// it ran in, a step down and right of it. Not saved (only the main one).
    func newWindow(from source: WindowSession) {
        let folder = WorkspaceFolder(arguments: ["cadex"])
        folder.open(source.folder.root)
        let session = WindowSession(app: self, folder: folder, isMain: false)
        sessions.append(session)
        if let keymap { session.applyKeymap(keymap) }
        if source.window.styleMask.contains(.fullScreen) {
            session.window.center()
        } else {
            session.window.setFrame(source.window.frame.offsetBy(dx: 28, dy: -28), display: false)
        }
        session.window.makeKeyAndOrderFront(nil)
    }

    /// The menu and the shortcuts run the commands of the window in front.
    func sessionBecameKey(_ session: WindowSession) {
        current = session
        dispatcher?.registry = session.commands
        if let menu = session.mainMenu { NSApp.mainMenu = menu }
    }

    func sessionClosed(_ session: WindowSession) {
        sessions.removeAll { $0 === session }
    }

    func keymapLabel(_ id: String) -> String? {
        keymap?.combo(for: id)?.label
    }

    /// The settings that reach every window; a new window reads them when
    /// it is made.
    private func connectSettings() {
        settings.onExplorer = { [weak self] prefs in self?.sessions.forEach { $0.applyExplorer(prefs) } }
        settings.onMarkdown = { [weak self] prefs in self?.sessions.forEach { $0.applyMarkdown(prefs) } }
        settings.onLooks = { [weak self] image, vibrancy in self?.sessions.forEach { $0.applyLooks(image, vibrancy: vibrancy) } }
        settings.onShortcuts = { [weak self] shortcuts in
            self?.shortcuts = shortcuts
            self?.applyShortcuts()
        }
    }

    /// Builds the keymap from the commands' defaults and the shortcuts in
    /// settings.json, then each window's menu and the dispatcher from it.
    /// Runs again when the shortcuts change; waits for the first window.
    private func applyShortcuts() {
        guard let main = sessions.first else { return }
        var keymap = Keymap(registry: catalog)
        keymap.applyPreferences(shortcuts, registry: catalog)
        keymap.problems.forEach { NSLog("atalhos: %@", $0) }
        self.keymap = keymap
        sessions.forEach { $0.applyKeymap(keymap) }
        if let dispatcher {
            dispatcher.update(keymap: keymap)
        } else {
            let dispatcher = ShortcutDispatcher(registry: main.commands, keymap: keymap)
            dispatcher.start()
            self.dispatcher = dispatcher
        }
        sessionBecameKey(current ?? main)
    }

    /// A folder dropped on the Dock icon becomes the workspace of the window
    /// in front (docs/spec/workspace.md). Needs the .app bundle's document
    /// types, which come with packaging (plan 7).
    func application(_ application: NSApplication, open urls: [URL]) {
        (current ?? sessions.first)?.openLaunchItems(urls.map(\.path))
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// One question for the running programs and unsaved files of every
    /// window.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let open = sessions.filter { $0.window.isVisible }
        guard !open.isEmpty else { return .terminateNow }
        let tabs = open.flatMap { $0.spaces?.spaces.map(\.tabs) ?? [] }
        let now = TabsController.shouldClose(
            tabs, in: (current ?? open[0]).window,
            then: { NSApp.reply(toApplicationShouldTerminate: true) },
            cancelled: { NSApp.reply(toApplicationShouldTerminate: false) })
        return now ? .terminateNow : .terminateLater
    }

    /// The main window's spaces as they were at the end, for the next launch.
    func applicationWillTerminate(_ notification: Notification) {
        sessions.first { $0.isMain }?.spaces?.saveNow()
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
