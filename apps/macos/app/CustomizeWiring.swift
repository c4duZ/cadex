import AppKit
import Worktrees
import Themes
import Customize
import Explorer
import GitHistory
import Memory
import Icons
import Settings
import Shortcuts
import Sidebar
import SourceControl
import Strings

/// The one Customize window in this window: the status bar's items and the accounts. The sidebar's
/// icons left with the sidebar, which became the work's tree (plan 27 phase B, TreeWiring.swift).
extension WindowSession {
    /// The one Customize window, on a tab (sidebar or statusBar), with this
    /// window's sidebar and status bar; over this window, in full screen too.
    func openCustomize(_ page: String) {
        guard let workspace else { return }
        Self.followThemeInCustomize()
        CustomizeWindow.shared.show(customizePages(workspace), selecting: page, colors: Self.customizeColors(), over: window)
    }

    /// The settings window's colors, from the theme itself: not the window's
    /// accent, which a space's or tab's color replaces (the owner saw blue
    /// switches under Caffeine, 2026-10-21).
    static func customizeColors() -> CustomizeColors {
        let ui = ThemeStore.shared.current.interface
        return CustomizeColors(text: ui.text.nsColor, secondary: ui.secondaryText.nsColor, accent: ui.accent.nsColor,
                               panel: ui.panel.nsColor, box: ui.chrome.color(alpha: 0.6), border: ui.panelBorder.nsColor)
    }

    private static var followsTheme = false

    /// Once for the app: a theme change repaints the open Customize window.
    private static func followThemeInCustomize() {
        guard !followsTheme else { return }
        followsTheme = true
        ThemeStore.shared.observe { _ in CustomizeWindow.shared.recolor(customizeColors()) }
    }

    /// Settings changed while it is open: it shows them.
    func refreshCustomize() {
        guard let workspace, window.isKeyWindow || CustomizeWindow.shared.isKeyWindow else { return }
        CustomizeWindow.shared.refresh(customizePages(workspace))
    }

    private func customizePages(_ workspace: WorkspaceView) -> [CustomizePage] {
        [workspace.statusBar.customizePage, accountsPage()]
    }

}
