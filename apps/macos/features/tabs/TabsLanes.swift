import AppKit
import Terminal

/// What a race's tab needs (plan 30 B, the Race mockup): its contenders side by side in one tab,
/// named, with a strip over them. Apart from TabsController.swift, at its size limit.
extension TabsController {
    /// A terminal in `cwd` split to the right of the active tab's focused pane, focused; nil when
    /// the tab has no room for one more.
    @discardableResult
    public func splitRight(cwd: String) -> TerminalView? {
        // A tab just made has no size yet: its room is checked once it has one.
        guard let tab = activeTab, tab.layout.bounds.width == 0 || tab.canSplit(axis: .horizontal) else { return nil }
        let terminal = makeTerminal(cwd: cwd)
        split(tab, axis: .horizontal, with: .terminal(terminal))
        return terminal
    }

    /// The name of the tab `terminal` is in ("Contenders · 3"); nil gives the usual one back.
    public func setTitle(_ title: String?, ofTabWith terminal: TerminalView) {
        guard let tab = tabs.values.first(where: { $0.terminals.contains { $0 === terminal } }) else { return }
        tab.customTitle = title
        refreshBar()
    }

    /// The strip over the panes of the tab `terminal` is in; nil takes it away.
    public func setBanner(_ banner: NSView?, ofTabWith terminal: TerminalView) {
        guard let tab = tabs.values.first(where: { $0.terminals.contains { $0 === terminal } }) else { return }
        tab.banner = banner
        if tab === activeTab { showActive() }
    }
}
