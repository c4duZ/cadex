import AppKit
import Themes
import UILooks

/// The settings window's colors: the new frame's tokens (plan 31 D; they follow the theme through
/// DesignTokens.applyTheme), so the window looks like the rest of the app. Pages read these when
/// they are built and are rebuilt when the theme changes (SettingsWindowController).
@MainActor
enum SettingsColors {
    /// Solid even under glass: the window lays it in its GlassPane at the glass's opacity, and the
    /// see-through grounds of its views go over that.
    static var background: NSColor { DesignTokens.solid(DesignTokens.Color.bgWindow) }
    static var box: NSColor { DesignTokens.Project.Row.bg }
    static var border: NSColor { DesignTokens.Project.Row.border }
    static var text: NSColor { DesignTokens.Color.textPrimary }
    static var secondaryText: NSColor { DesignTokens.Color.textMuted }
    /// A switch on: the project page's toggle.
    static var accent: NSColor { DesignTokens.Project.Toggle.on }
    static var isDark: Bool { ThemeStore.shared.current.dark }
}
