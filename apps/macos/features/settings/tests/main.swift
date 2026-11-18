import Checks
import AppKit
@testable import Settings
import Themes

// Tests of the settings feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("an old file on Caffeine moves to Cadex Night once; a theme picked since stays (ADR 0035)", {
        func read(_ json: String) -> Settings { SettingsFile.read(Data(json.utf8)).0 }
        let old = read(#"{"appearance": {"theme": "caffeine", "darkTheme": "caffeine"}}"#)
        expect(old.appearance.theme == "cadex-night", old.appearance.theme)
        expect(old.appearance.darkTheme == "caffeine", "a dark theme was a choice: it stays")
        expect(read(#"{"version": 99}"#).version == 99, "a newer file keeps its version")
        expect(read(#"{"version": 4, "terminal": {"lineHeight": 1}}"#).terminal.lineHeight == 1.6, "the old default moves to the mockups' 1.6")
        expect(read(#"{"version": 4, "terminal": {"lineHeight": 1.2}}"#).terminal.lineHeight == 1.2, "a height the owner chose stays")
        expect(read(#"{"version": 5, "terminal": {"lineHeight": 1}}"#).terminal.lineHeight == 1, "after the move, 1 is a choice")
        expect(read(#"{"version": 5, "statusBar": {"left": ["project"], "right": ["memory"]}}"#).statusBar.right == ["drawer", "memory"])
        expect(read(#"{"version": 6, "statusBar": {"left": ["project"], "right": ["memory"]}}"#).statusBar.right == ["memory"], "after, its absence is a choice")
        expect(read(#"{"appearance": {"theme": "dracula"}}"#).appearance.theme == "dracula")
        expect(read(#"{"version": 2, "appearance": {"theme": "caffeine"}}"#).appearance.theme == "caffeine")
        expect(Settings().appearance.theme == "cadex-night")
        let written = try JSONSerialization.jsonObject(with: SettingsFile.write(old)) as! [String: Any]
        expect(written["version"] as? Int == Settings.currentVersion)
    }),
    ("settings saved and read back are the same", {
        var settings = Settings()
        settings.terminal.fontSize = 15
        settings.terminal.cursor = "block"
        settings.appearance.theme = "tokyo-night"
        settings.appearance.backgroundImage = "/tmp/fundo.png"
        settings.explorer.showHidden = false
        settings.explorer.followTerminal = false
        settings.markdown.openAs = "rendered"
        settings.general.openFiles = "tab"
        settings.general.language = "pt"
        settings.power.mode = "running"
        settings.power.onAtLaunch = true
        settings.power.keepDisplayOn = true
        settings.shortcuts = ["cmd+shift+t": "tab.new", "cmd+t": nil]
        settings.appearance.darkTheme = "catppuccin-macchiato"
        settings.appearance.lightTheme = "github"
        settings.appearance.accent = "#FF8800"
        settings.appearance.highContrast = true
        settings.appearance.uiZoom = 1.25
        settings.appearance.density = "compact"
        settings.appearance.uiFont = "Avenir Next"
        settings.appearance.uiFontSize = 14
        settings.terminal.minimumContrast = 4.5
        settings.terminal.lineHeight = 1.2
        settings.terminal.letterSpacing = 0.5
        settings.terminal.fontFeatures = ["calt", "liga", "ss01", "-zero"]
        settings.tabs.documentSide = "left"
        let (read, problems) = SettingsFile.read(SettingsFile.write(settings))
        expect(problems.isEmpty, "\(problems)")
        expect(read == settings, "\(read)")
    }),
    ("plan 15's values out of range are clamped; a bad accent or feature is a problem", {
        let json = #"{"terminal": {"lineHeight": 9, "letterSpacing": -5, "minimumContrast": 40, "fontFeatures": ["calt", "ligatures"]},"#
            + #" "appearance": {"accent": "orange", "uiZoom": 3, "density": "tiny"},}"#
        let (read, problems) = SettingsFile.read(Data(json.utf8))
        expect(read.terminal.lineHeight == 2 && read.terminal.letterSpacing == -1 && read.terminal.minimumContrast == 21)
        expect(read.terminal.fontFeatures == ["calt"] && read.appearance.accent.isEmpty, "\(read.terminal.fontFeatures)")
        expect(read.appearance.uiZoom == 1.5 && read.appearance.density == "normal")
        expect(problems.count == 3, "\(problems)")
    }),
    ("the active account and the projects' accounts are kept; a wrong one is a warning", {
        var settings = Settings()
        expect(settings.agents.activeAccount.isEmpty && settings.agents.projectAccounts.isEmpty)
        settings.agents.activeAccount = "~/.claude-work"
        settings.agents.projectAccounts = ["~/code/app": "~/.claude-bkdg"]
        let read = SettingsFile.read(SettingsFile.write(settings)).0
        expect(read.agents.activeAccount == "~/.claude-work" && read.agents.projectAccounts == ["~/code/app": "~/.claude-bkdg"])
        let (bad, problems) = SettingsFile.read(Data(#"{"agents": {"projectAccounts": ["x"]}}"#.utf8))
        expect(bad.agents.projectAccounts.isEmpty && problems.count == 1, "\(problems)")
    }),
    ("the old panes' settings (the shade and the headers, gone in plan 28) read with no problem", {
        let (_, problems) = SettingsFile.read(Data(#"{"tabs": {"unfocusedDim": 0.3, "paneHeaders": "never", "documentSide": "left"}}"#.utf8))
        expect(problems.isEmpty, "\(problems)")
    }),
    ("a file of the old sidebar (its icon list, gone in plan 27) reads with no problem", {
        let (read, problems) = SettingsFile.read(Data(#"{"version": 4, "sidebar": {"items": ["files", "agents"]}}"#.utf8))
        expect(problems.isEmpty && read.version == Settings.currentVersion, "\(problems)")
    }),
    ("the right panel opens on Changes; open or closed and its tab come back; a tab it lacks is a problem", {
        let fresh = SettingsFile.read(Data("{}".utf8)).0.inspector
        expect(fresh.visible && fresh.tab == "changes", "\(fresh)")
        var settings = Settings()
        settings.inspector.visible = false
        settings.inspector.tab = "history"
        expect(SettingsFile.read(SettingsFile.write(settings)).0.inspector == settings.inspector)
        let (read, problems) = SettingsFile.read(Data(#"{"inspector": {"tab": "accounts"}}"#.utf8))
        expect(read.inspector.tab == "changes" && problems.count == 1, "\(problems)")
        settings.inspector.width = 410
        expect(SettingsFile.read(SettingsFile.write(settings)).0.inspector.width == 410, "the dragged width comes back")
        expect(SettingsFile.read(Data(#"{"inspector": {"width": 5000}}"#.utf8)).0.inspector.width == Settings.inspectorWidths.upperBound, "kept in range")
    }),
    ("the interface is in English unless the file says pt; anything else is a problem", {
        expect(SettingsFile.read(Data("{}".utf8)).0.general.language == "en")
        let (read, problems) = SettingsFile.read(Data(#"{"general": {"language": "fr"}}"#.utf8))
        expect(read.general.language == "en" && problems.count == 1, "\(problems)")
    }),
    ("the coffee turns on always unless the file says running; off at launch", {
        let defaults = SettingsFile.read(Data("{}".utf8)).0.power
        expect(defaults.mode == "always" && !defaults.onAtLaunch)
        let (read, problems) = SettingsFile.read(Data(#"{"power": {"mode": "forever"}}"#.utf8))
        expect(read.power.mode == "always" && problems.count == 1, "\(problems)")
    }),
    ("a note opens as source unless the file says rendered; anything else is a problem", {
        let (read, problems) = SettingsFile.read(Data(#"{"markdown": {"openAs": "slides"}}"#.utf8))
        expect(read.markdown.openAs == "source" && problems.count == 1, "\(problems)")
    }),
    ("the tailnet's machines are read unless turned off; the users kept per machine", {
        expect(SettingsFile.read(Data("{}".utf8)).0.machines == Settings.Machines())
        var settings = Settings()
        settings.machines.tailscale = false
        settings.machines.acceptRemote = true
        settings.machines.users = ["pc.tail1234.ts.net": "dev"]
        let (read, problems) = SettingsFile.read(SettingsFile.write(settings))
        expect(problems.isEmpty && read.machines == settings.machines, "\(read.machines) \(problems)")
        let (bad, wrong) = SettingsFile.read(Data(#"{"machines": {"tailscale": 1, "users": ["dev"]}}"#.utf8))
        expect(bad.machines.tailscale && bad.machines.users.isEmpty && wrong.count == 2, "\(wrong)")
    }),
    ("orchestration: off by default, kept across a write, numbers bounded", {
        let defaults = SettingsFile.read(Data("{}".utf8)).0.orchestration
        expect(!defaults.enabled && !defaults.automations && defaults.maxAgents == 6 && defaults.maxDepth == 2)
        expect(defaults.heartbeatMinutes == 10 && defaults.keepAwakeDuringRuns && defaults.defaultBudgetUsd == 5 && defaults.defaultMaxMinutes == 60)
        var settings = Settings()
        settings.orchestration.enabled = true
        settings.orchestration.maxAgents = 3
        settings.orchestration.defaultBudgetUsd = 2.5
        let (read, problems) = SettingsFile.read(SettingsFile.write(settings))
        expect(problems.isEmpty && read.orchestration == settings.orchestration, "\(read.orchestration) \(problems)")
        let (wild, _) = SettingsFile.read(Data(#"{"orchestration": {"maxAgents": 500, "maxDepth": -3, "defaultBudgetUsd": 0}}"#.utf8))
        expect(wild.orchestration.maxAgents == 20 && wild.orchestration.maxDepth == 0 && wild.orchestration.defaultBudgetUsd == 0.1)
    }),
    ("the memory is on and shared across accounts unless the file says otherwise", {
        let defaults = SettingsFile.read(Data("{}".utf8)).0.memory
        expect(defaults.enabled && defaults.shareAcrossAccounts && defaults.consolidateInSession && defaults.consolidateAtContext == 70)
        var settings = Settings()
        settings.memory.enabled = false
        settings.memory.shareAcrossAccounts = false
        settings.memory.consolidateInSession = false
        settings.memory.consolidateAtContext = 85
        let (read, problems) = SettingsFile.read(SettingsFile.write(settings))
        expect(problems.isEmpty && read.memory == settings.memory, "\(read.memory) \(problems)")
        let (bad, wrong) = SettingsFile.read(Data(#"{"memory": {"enabled": "no", "shareAcrossAccounts": false}}"#.utf8))
        expect(bad.memory.enabled && !bad.memory.shareAcrossAccounts && wrong.count == 1, "\(wrong)")
        expect(!defaults.backgroundAgent && defaults.dailyBudgetUsd == 1.0 && defaults.requireApproval, "the memory agent starts off (ADR 0029)")
        var agent = Settings()
        agent.memory.backgroundAgent = true
        agent.memory.dailyBudgetUsd = 2.5
        agent.memory.requireApproval = false
        expect(SettingsFile.read(SettingsFile.write(agent)).0.memory == agent.memory)
        let clamped = SettingsFile.read(Data(#"{"memory": {"consolidateAtContext": 300}}"#.utf8)).0.memory
        expect(clamped.consolidateAtContext == 95, "the milestone percent stays in 10…95")
    }),
    ("files open beside unless the file says tab; anything else is a problem", {
        expect(SettingsFile.read(Data("{}".utf8)).0.general.openFiles == "beside")
        let (read, problems) = SettingsFile.read(Data(#"{"general": {"openFiles": "janela"}}"#.utf8))
        expect(read.general.openFiles == "beside" && problems.count == 1, "\(problems)")
    }),
    ("a broken file gives the defaults and says why", {
        let (read, problems) = SettingsFile.read(Data("{ quebrado".utf8))
        expect(read == Settings())
        expect(problems.count == 1)
    }),
    ("a wrong field falls back alone; the rest still counts", {
        let json = #"{"terminal": {"fontSize": "grande", "cursor": "losango", "copyOnSelect": true}}"#
        let (read, problems) = SettingsFile.read(Data(json.utf8))
        expect(read.terminal.fontSize == 13 && read.terminal.cursor == "bar")
        expect(read.terminal.copyOnSelect)
        expect(problems.count == 2, "\(problems)")
    }),
    ("sizes and history are kept within the limits", {
        let json = #"{"terminal": {"fontSize": 99, "historyLines": 5000000}}"#
        let (read, _) = SettingsFile.read(Data(json.utf8))
        expect(read.terminal.fontSize == 32)
        expect(read.terminal.historyLines == 100_000)
    }),
    ("a picked background image is kept as a copy", {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-bg-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("foto.png")
        try Data([1, 2, 3]).write(to: original)
        let copy = try BackgroundImages.keepCopy(of: original, into: root.appendingPathComponent("backgrounds"))
        try FileManager.default.removeItem(at: original)
        expect(FileManager.default.fileExists(atPath: copy) && copy.hasSuffix(".png"), copy)
    }),
    ("the store saves on change and reads a hand edit back", {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-settings-\(UUID())/settings.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        var seen: [Double] = []
        store.observe { seen.append($0.terminal.fontSize) }
        store.update { $0.terminal.fontSize = 16 }
        expect(SettingsFile.read(try Data(contentsOf: file)).0.terminal.fontSize == 16)

        var edited = store.settings
        edited.terminal.fontSize = 18
        try SettingsFile.write(edited).write(to: file)
        store.load()
        expect(store.settings.terminal.fontSize == 18)
        expect(seen == [13, 16, 18], "\(seen)")
    }),
    ("the status bar of before moves to the new frame's; an arranged one keeps its items (plan 26 B)", {
        func read(_ json: String) -> Settings.StatusBar { SettingsFile.read(Data(json.utf8)).0.statusBar }
        let old = read(#"{"version": 2, "statusBar": {"left": ["folder"], "right": ["environment"]}}"#)
        expect(old == Settings.StatusBar(), "\(old)")
        let mine = read(#"{"version": 2, "statusBar": {"left": ["folder", "ram"], "right": ["branch", "environment"]}}"#)
        // Every file before version 6 also gets the drawer's item first on the right, once (plan 30).
        expect(mine.left == ["project", "ram"] && mine.right == ["drawer", "environment", "keepAwake", "update"], "\(mine)")
        let oneSide = read(#"{"version": 2, "statusBar": {"left": ["folder", "ram"]}}"#)
        expect(oneSide.left == ["project", "ram"] || oneSide.left == ["folder", "ram"], "\(oneSide)")
        expect(oneSide.right == ["drawer", "environment", "keepAwake", "update"], "the side not written was the old default: \(oneSide)")
        let now = read(#"{"version": 3, "statusBar": {"left": ["folder"], "right": []}}"#)
        expect(now.left == ["folder"] && now.right == ["drawer"], "a version 3 file keeps its sides, with the drawer's item: \(now)")
    }),
    ("an old file is moved once and written back, so a later hand edit to Caffeine stays", {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-settings-\(UUID())/settings.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"appearance": {"theme": "caffeine"}}"#.utf8).write(to: file)
        let store = SettingsStore(file: file)
        store.load()
        let saved = try Data(contentsOf: file)
        expect(SettingsFile.version(of: saved) == Settings.currentVersion && store.settings.appearance.theme == "cadex-night")
        var back = store.settings
        back.appearance.theme = "caffeine"
        try SettingsFile.write(back).write(to: file)
        store.load()
        expect(store.settings.appearance.theme == "caffeine", "chosen after the move: stays")
    }),
    ("the themes page builds cards only for the rows on screen", {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-themes-page-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = await SettingsStore(file: folder.appendingPathComponent("settings.json"))
        await MainActor.run {
            let page = ThemesPage(store: store).makeView()
            page.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
            page.layoutSubtreeIfNeeded()
            let cards = cardViews(in: page)
            expect(cards > 0 && cards < 40, "\(cards) cards")
            snapshot(page, "themes-page")
        }
    }),
    ("each module has its section and the search finds a setting by its words (plan 32)", {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cadex-settings-\(UUID())/settings.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = SettingsStore(file: file)
        let sections: [(SettingsSection, [NSView])] = [
            (.general, SectionRows.general(store) { _ in }), (.terminal, TerminalPage.rows(store)), (.files, SectionRows.files(store)),
            (.git, SectionRows.git(store)), (.agents, SectionRows.agents(store)), (.notifications, SectionRows.notifications(store)),
            (.memory, MemoryRows.make(store)), (.orchestration, OrchestrationRows.make(store)), (.machines, SectionRows.machines(store)),
        ]
        @MainActor func found(_ words: String) -> [SettingsSection] {
            sections.filter { $0.1.contains { ($0 as? SettingsRowBox)?.matches(words) == true } }.map(\.0)
        }
        expect(found("tailnet") == [.machines], "\(found("tailnet"))")
        expect(found("hibernate") == [.agents], "\(found("hibernate"))")
        expect(found("Option as Meta") == [.terminal], "\(found("Option as Meta"))")
        expect(found("hidden files") == [.files], "\(found("hidden files"))")
        expect(found("daily cap").contains(.memory), "\(found("daily cap"))")
        expect(found("ZZZ nothing").isEmpty)
        // No section is empty, and General is no longer everything.
        for (section, rows) in sections { expect(rows.contains { $0 is SettingsRowBox }, "\(section) has rows") }
        let general = SectionRows.general(store) { _ in }.filter { $0 is SettingsRowBox }.count
        expect(general < 12, "General holds \(general) rows")
    }),

])

/// The card views in a view tree.
@MainActor func cardViews(in view: NSView) -> Int {
    (view is ThemeCard ? 1 : 0) + view.subviews.reduce(0) { $0 + cardViews(in: $1) }
}

/// With CADEX_SNAPSHOT_DIR set, saves a picture of `view` there: the way to
/// look at a page when the screen cannot be captured.
@MainActor func snapshot(_ view: NSView, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
    // In a window, for the window's background and the controls' looks.
    let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: SettingsColors.isDark ? .darkAqua : .aqua)
    let root = NSView(frame: view.bounds)
    root.wantsLayer = true
    root.layer?.backgroundColor = SettingsColors.background.cgColor
    root.addSubview(view)
    window.contentView = root
    root.layoutSubtreeIfNeeded()
    guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
    root.cacheDisplay(in: root.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
}
exit(exitCode)
