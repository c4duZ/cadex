import AppKit
import Terminal

/// A terminal moved from one set of tabs to another with its shell alive (plan 30 C: ⌘↩ takes a
/// drawer's terminal to the project shown).
extension TabsController {
    /// The focused terminal out of its tab, its shell running; the tab goes with its last pane.
    public func takeFocusedTerminal() -> TerminalView? {
        guard let tab = activeTab, let terminal = tab.focused.terminal else { return nil }
        if tab.panes.count == 1 {
            tabs.removeValue(forKey: tab.id)
            tab.view.removeFromSuperview()
            list.remove(tab.id)
            terminal.removeFromSuperview()
            if list.order.isEmpty { onEmpty?() } else { showActive() }
        } else {
            _ = tab.remove(pane: tab.focusedPane)
            terminal.removeFromSuperview()
            refreshBar()
        }
        return terminal
    }

    /// A terminal from elsewhere in a new tab here, focused.
    public func adopt(_ terminal: TerminalView) {
        addTab(.terminal(terminal))
    }
}
