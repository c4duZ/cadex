import AppKit
import Terminal

/// One tab: its terminal and the name the user gave it, if any.
@MainActor
final class Tab {
    let id: Int
    /// Set by "Renomear aba"; stays when the folder changes. Nil shows the
    /// folder (docs/spec/tabs.md).
    var customTitle: String?
    let terminal: TerminalView

    init(id: Int, terminal: TerminalView) {
        self.id = id
        self.terminal = terminal
    }

    /// The view the tab shows below the tab bar.
    var view: NSView { terminal }
    /// The terminal with focus inside the tab.
    var focused: TerminalView { terminal }
    var terminals: [TerminalView] { [terminal] }

    func title(home: String) -> String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        return folderTitle(focused.currentDirectory, home: home)
    }

    var hasForegroundProcess: Bool { terminals.contains { $0.hasForegroundProcess } }
}
