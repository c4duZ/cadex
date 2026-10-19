import AppKit
import Settings
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
    /// The background image or vibrancy changed.
    var onLooks: ((WindowBackdrop.Image?, Bool) -> Void)?
    private var lastShortcuts: [String: String?]?

    func start() {
        ThemeStore.shared.setFamilies(ThemeCatalog.builtIn)
        store.observe { [weak self] settings in self?.apply(settings) }
        store.watchForEdits()
        NotificationCenter.default.addObserver(forName: TerminalPreferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveTerminalChoices() }
        }
    }

    private func apply(_ settings: Settings) {
        TerminalPreferences.current = Self.terminalPreferences(from: settings)
        ThemeStore.shared.select(id: settings.appearance.theme, mode: ThemeMode(rawValue: settings.appearance.mode) ?? .system)
        let a = settings.appearance
        onLooks?(a.backgroundImage.map { .init(path: $0, opacity: a.backgroundOpacity, blur: a.backgroundBlur) }, a.vibrancy)
        onExplorer?(settings.explorer)
        if settings.shortcuts != lastShortcuts {
            lastShortcuts = settings.shortcuts
            onShortcuts?(settings.shortcuts)
        }
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
