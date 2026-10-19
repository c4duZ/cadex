import AppKit
import Themes

/// The settings window's colors, from the theme in use, so the window looks
/// like the rest of the app. Pages read these when they are built and are
/// rebuilt when the theme changes (SettingsWindowController).
@MainActor
enum SettingsColors {
    private static var ui: Theme.Interface { ThemeStore.shared.current.interface }

    static var background: NSColor { ui.panel.nsColor }
    static var box: NSColor { ui.chrome.color(alpha: 0.6) }
    static var border: NSColor { ui.panelBorder.nsColor }
    static var text: NSColor { ui.text.nsColor }
    static var secondaryText: NSColor { ui.secondaryText.nsColor }
    static var accent: NSColor { ui.accent.nsColor }
    static var isDark: Bool { ThemeStore.shared.current.dark }
}
