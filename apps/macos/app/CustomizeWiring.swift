import AppKit
import UILooks
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

/// The lists to arrange (the status bar's items, the accounts): sections of the settings window
/// since plan 32 B (it was the Customize window, refused by the owner on 2026-11-18: "as
/// configurações que estão em outra coisa hoje" come into settings).
extension WindowSession {
    /// The settings window on the section of `page` ("statusBar", "accounts"), with this window's
    /// status bar and accounts.
    func openCustomize(_ page: String) {
        app.showSettings(page == "accounts" ? "agents" : page)
    }

    /// Settings changed while it is open: it shows them.
    func refreshCustomize() { app.refreshSettingsLists() }

    func customizePages(_ workspace: WorkspaceView) -> [CustomizePage] {
        [workspace.statusBar.customizePage, accountsPage()]
    }
}
