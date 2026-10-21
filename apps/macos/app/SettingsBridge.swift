import Agents
import AppKit
import Settings
import Tabs
import Terminal
import Themes

/// Connects settings.json to the features that use it: the terminal
/// preferences, the theme and (through `onShortcuts`) the keymap. A choice
/// made elsewhere ("não perguntar de novo" in an alert) comes back here and
/// is saved, so the file stays the one place (docs/spec/settings.md).
@MainActor
final class SettingsBridge {
    let store = SettingsStore()
    /// The shortcuts section changed.
    var onShortcuts: (([String: String?]) -> Void)?
    /// The explorer section changed (hidden files).
    var onExplorer: ((Settings.Explorer) -> Void)?
    /// The markdown section changed (how notes open).
    var onMarkdown: ((Settings.Markdown) -> Void)?
    /// The sidebar section changed (which icons, in what order).
    var onSidebar: ((Settings.Sidebar) -> Void)?
    /// The status bar section changed (which items, on which side).
    var onStatusBar: ((Settings.StatusBar) -> Void)?
    /// The power section changed (the display; the mode counts at launch).
    var onPower: ((Settings.Power) -> Void)?
    /// The background image or vibrancy changed.
    var onLooks: ((WindowBackdrop.Image?, Bool) -> Void)?
    private var lastShortcuts: [String: String?]?

    /// general.openFiles: files open beside the focused pane unless it
    /// says "tab". Read at each opening, so a change counts at once.
    var opensBeside: Bool { store.settings.general.openFiles != "tab" }

    /// preview.pickTarget: a picked element is copied, not pasted into the
    /// agent's terminal. Read at each pick.
    var picksToClipboard: Bool { store.settings.preview.pickTarget == "clipboard" }

    /// preview.pickScreenshot: a picture of the picked element goes along.
    var picksScreenshot: Bool { store.settings.preview.pickScreenshot }

    func start() {
        store.observe { [weak self] settings in self?.apply(settings) }
        // "Increase contrast" in the system changes the theme, not the settings.
        var wasHighContrast = ThemeStore.shared.isHighContrast
        ThemeStore.shared.observe { [weak self] _ in
            guard ThemeStore.shared.isHighContrast != wasHighContrast else { return }
            wasHighContrast = ThemeStore.shared.isHighContrast
            self?.applyLooks()
        }
        store.watchForEdits()
        NotificationCenter.default.addObserver(forName: TerminalPreferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveTerminalChoices() }
        }
    }

    private func apply(_ settings: Settings) {
        EditorLooks.refresh()
        let a = settings.appearance
        ThemeStore.shared.apply(.init(
            dark: a.darkTheme.isEmpty ? a.theme : a.darkTheme, light: a.lightTheme.isEmpty ? a.theme : a.lightTheme,
            mode: ThemeMode(rawValue: a.mode) ?? .system,
            accent: a.accent.isEmpty ? nil : try? ThemeFile.parse(a.accent, field: "appearance.accent"),
            highContrast: a.highContrast))
        PaneLooks.unfocusedDim = CGFloat(settings.tabs.unfocusedDim)
        TabsController.documentsOnLeft = settings.tabs.documentSide == "left"
        applyLooks()
        onExplorer?(settings.explorer)
        onMarkdown?(settings.markdown)
        onPower?(settings.power)
        onSidebar?(settings.sidebar)
        onStatusBar?(settings.statusBar)
        AgentsController.shared.isEnabled = settings.agents.sessions
        let agents = settings.agents
        AgentNotifier.shared.kinds = .init(permission: agents.sessions && agents.notifyPermission,
                                           question: agents.sessions && agents.notifyQuestion,
                                           finished: agents.sessions && agents.notifyFinished)
        if settings.shortcuts != lastShortcuts {
            lastShortcuts = settings.shortcuts
            onShortcuts?(settings.shortcuts)
        }
    }

    /// The background image and vibrancy, both off in high contrast (no
    /// transparency, plan 15); the system's "Increase contrast" changing
    /// comes through the theme.
    private func applyLooks() {
        let a = store.settings.appearance
        let plain = ThemeStore.shared.isHighContrast
        onLooks?(plain ? nil : a.backgroundImage.map { .init(path: $0, opacity: a.backgroundOpacity, blur: a.backgroundBlur) },
                 a.vibrancy && !plain)
        var preferences = Self.terminalPreferences(from: store.settings)
        if plain { preferences.minimumContrast = max(preferences.minimumContrast, Theme.highContrastText) }
        TerminalPreferences.current = preferences
    }

    static func terminalPreferences(from settings: Settings) -> TerminalPreferences {
        var p = TerminalPreferences()
        p.shell = settings.general.shell
        p.confirmClose = settings.general.confirmClose
        p.confirmMultilinePaste = settings.general.confirmMultilinePaste
        p.fontFamily = settings.terminal.fontFamily
        p.fontSize = CGFloat(settings.terminal.fontSize)
        p.cursorShape = ["block": .block, "underline": .underline][settings.terminal.cursor] ?? .bar
        p.cursorBlink = settings.terminal.cursorBlink
        p.historyLines = settings.terminal.historyLines
        p.optionAsMeta = settings.terminal.optionAsMeta
        p.copyOnSelect = settings.terminal.copyOnSelect
        p.minimumContrast = settings.terminal.minimumContrast
        p.lineHeight = settings.terminal.lineHeight
        p.letterSpacing = settings.terminal.letterSpacing
        p.fontFeatures = settings.terminal.fontFeatures
        return p
    }

    /// The questions the terminal and the tabs can turn off by themselves.
    private func saveTerminalChoices() {
        let current = TerminalPreferences.current
        store.update {
            $0.general.confirmClose = current.confirmClose
            $0.general.confirmMultilinePaste = current.confirmMultilinePaste
        }
    }
}
