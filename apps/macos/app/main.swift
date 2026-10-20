import AppKit
import CommandPalette
import Explorer
import Menus
import Power
import Settings
import Shortcuts
import Strings
import Tabs
import Themes
import Updates

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
        suspendShortcuts: { [weak self] on in self?.dispatcher?.isSuspended = on },
        relaunch: { [weak self] in self?.relaunch() })
    /// Quitting to open again (the language changed): applicationWillTerminate
    /// starts the new Cadex.
    private var relaunching = false

    var settingsCommand: Command { settingsWindow.openCommand }
    /// The Cadex symbol by the clock: filled while keep-awake is on.
    private var menuBarItem: MenuBarItem?
    /// Keep-awake, for the whole app: a program running in any window counts.
    private(set) lazy var power = PowerController { [weak self] in self?.sessions.contains(where: \.hasRunningProgram) ?? false }
    /// The in-app updater: one state for every window's title bar.
    let updates = UpdateController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before any text is made: every view reads its texts once (ADR 0015).
        Strings.language = Language(rawValue: settings.store.settings.general.language) ?? .en
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
        startPower()
        startUpdates()
        let main = WindowSession(app: self, folder: WorkspaceFolder(), isMain: true)
        sessions.append(main)
        catalog.register(main.commands.commands)
        applyShortcuts()
        main.openLaunchItems(Self.launchFiles)
        CommandLine.arguments.dropFirst().filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }.forEach { main.openPreview($0) }
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

    /// On at launch in the settings' mode, if they say so; the display
    /// setting counts live.
    private func startPower() {
        let prefs = settings.store.settings.power
        power.keepDisplayOn = prefs.keepDisplayOn
        power.defaultMode = PowerController.Mode(rawValue: prefs.mode) ?? .always
        power.onChange = { [weak self] in self?.showPower() }
        menuBarItem = MenuBarItem { [weak self] in self?.runPowerButton() }
        if prefs.onAtLaunch { power.set(PowerController.Mode(rawValue: prefs.mode) ?? .always) }
        showPower()
    }

    /// The coffee and the menu bar symbol show the state, the tip what a
    /// click does.
    func showPower() {
        sessions.forEach { $0.showPower() }
        menuBarItem?.show(on: power.mode != .off, tip: powerTip)
    }

    var powerTip: String {
        switch power.mode {
        case .off:
            settings.store.settings.power.mode == "running"
                ? T("Keep awake while a program runs", "Manter acordado com programa rodando")
                : T("Keep awake", "Manter acordado")
        case .always: T("Keeping the computer awake (click to turn off)", "Mantendo o computador acordado (clique para desligar)")
        case .running: power.isHolding
            ? T("Awake: a program is running (click to turn off)", "Acordado: um programa está rodando (clique para desligar)")
            : T("Awake when a program runs (click to turn off)", "Acordado quando um programa rodar (clique para desligar)")
        }
    }

    /// The menu bar symbol runs the coffee's command, in the window in
    /// front or any other.
    private func runPowerButton() {
        _ = (current ?? sessions.first)?.commands.run("power.toggle")
    }


    /// The panel's buttons run commands in the window in front; installing
    /// reopens as "Reopen now" does (docs/adr/0016-in-app-updates.md).
    private func startUpdates() {
        updates.onChange = { [weak self] in self?.sessions.forEach { $0.showUpdate() } }
        updates.runCommand = { [weak self] id in _ = (self?.current ?? self?.sessions.first)?.commands.run(id) }
        updates.relaunch = { [weak self] in self?.relaunch() }
        updates.start()
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
        settings.onPower = { [weak self] prefs in
            self?.power.keepDisplayOn = prefs.keepDisplayOn
            self?.power.defaultMode = PowerController.Mode(rawValue: prefs.mode) ?? .always
            self?.showPower()
        }
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
            cancelled: { [weak self] in
                self?.relaunching = false
                NSApp.reply(toApplicationShouldTerminate: false)
            })
        return now ? .terminateNow : .terminateLater
    }

    /// The main window's spaces as they were at the end, for the next launch.
    func applicationWillTerminate(_ notification: Notification) {
        sessions.first { $0.isMain }?.spaces?.saveNow()
        if relaunching { openAgain() }
    }

    /// "Reopen now" after the language changed: quits as usual (asking over
    /// running programs, saving the spaces), then a new Cadex opens.
    private func relaunch() {
        relaunching = true
        NSApp.terminate(nil)
    }

    /// A shell waits for this process to end and opens Cadex again: the
    /// bundle through `open`, or the bare executable during development.
    private func openAgain() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        if Bundle.main.bundleIdentifier != nil {
            // The CADEX_ variables go along: a test instance reopened by an
            // update would otherwise take the keyboard and the owner's spaces.
            let env = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("CADEX_") }
                .flatMap { ["--env", "\($0.key)=\($0.value)"] }
            process.arguments = ["-c", "pid=$1; shift; while kill -0 \"$pid\" 2>/dev/null; do sleep 0.2; done; open -n \"$@\"",
                                 "sh", String(getpid())] + env + [Bundle.main.bundlePath]
        } else if let executable = Bundle.main.executablePath {
            process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; \"$0\" >/dev/null 2>&1 &",
                                 executable, String(getpid())]
        }
        try? process.run()
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
