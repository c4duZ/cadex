import Checks
import AppKit
@testable import Settings
import Themes

// Tests of the settings feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
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
        settings.tabs.unfocusedDim = 0.4
        let (read, problems) = SettingsFile.read(SettingsFile.write(settings))
        expect(problems.isEmpty, "\(problems)")
        expect(read == settings, "\(read)")
    }),
    ("plan 15's values out of range are clamped; a bad accent or feature is a problem", {
        let json = #"{"terminal": {"lineHeight": 9, "letterSpacing": -5, "minimumContrast": 40, "fontFeatures": ["calt", "ligatures"]},"#
            + #" "appearance": {"accent": "orange", "uiZoom": 3, "density": "tiny"}, "tabs": {"unfocusedDim": 2}}"#
        let (read, problems) = SettingsFile.read(Data(json.utf8))
        expect(read.terminal.lineHeight == 2 && read.terminal.letterSpacing == -1 && read.terminal.minimumContrast == 21)
        expect(read.terminal.fontFeatures == ["calt"] && read.appearance.accent.isEmpty, "\(read.terminal.fontFeatures)")
        expect(read.appearance.uiZoom == 1.5 && read.appearance.density == "normal" && read.tabs.unfocusedDim == 0.6)
        expect(problems.count == 3, "\(problems)")
    }),
    ("the sidebar's icons default to Files, Search and Git, and keep the saved order", {
        expect(SettingsFile.read(Data("{}".utf8)).0.sidebar.items == ["files", "search", "git", "agents", "accounts"])
        var settings = Settings()
        settings.sidebar.items = ["git", "files"]
        expect(SettingsFile.read(SettingsFile.write(settings)).0.sidebar.items == ["git", "files"])
        let (read, problems) = SettingsFile.read(Data(#"{"sidebar": {"items": "git"}}"#.utf8))
        expect(read.sidebar.items == ["files", "search", "git", "agents", "accounts"] && problems.count == 1, "\(problems)")
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
