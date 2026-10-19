import AppKit
import Terminal

/// One tab: its panes, how they divide the space, which one has focus, and
/// the name the user gave the tab, if any.
@MainActor
final class Tab {
    let id: Int
    /// Set by "Renomear aba"; stays when the folder changes. Nil shows the
    /// folder of the focused pane (docs/spec/tabs.md).
    var customTitle: String?
    private(set) var panes: [Int: TerminalView] = [:]
    private(set) var focusedPane: Int
    let layout = PaneLayoutView(frame: .zero)

    init(id: Int, pane: Int, terminal: TerminalView) {
        self.id = id
        focusedPane = pane
        panes[pane] = terminal
        layout.tree = .leaf(pane)
        layout.panes = [pane: terminal]
        layout.focused = pane
        layout.onTreeChange = { [weak self] tree in self?.layout.tree = tree }
        layout.syncSubviews()
    }

    var view: NSView { layout }
    var focused: TerminalView { panes[focusedPane]! }
    /// Panes in reading order.
    var terminals: [TerminalView] { layout.tree.leaves.compactMap { panes[$0] } }
    var tree: PaneTree { layout.tree }

    func title(home: String) -> String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        return folderTitle(focused.currentDirectory, home: home)
    }

    var hasForegroundProcess: Bool { terminals.contains { $0.hasForegroundProcess } }

    func canSplit(axis: PaneTree.Axis) -> Bool {
        layout.canSplit(focusedPane, axis: axis)
    }

    /// Splits the focused pane; the new one takes the focus.
    func split(axis: PaneTree.Axis, pane: Int, terminal: TerminalView) {
        layout.tree = layout.tree.splitting(focusedPane, axis: axis, newPane: pane)
        panes[pane] = terminal
        layout.panes[pane] = terminal
        layout.syncSubviews()
        focus(pane)
    }

    /// Removes a pane; the focus goes to the pane that took its space.
    /// Returns false when it was the last one (the tab is now empty).
    func remove(pane: Int) -> Bool {
        let order = layout.tree.leaves
        guard let rest = layout.tree.removing(pane) else { return false }
        let index = order.firstIndex(of: pane) ?? 0
        panes[pane] = nil
        layout.panes[pane] = nil
        layout.tree = rest
        layout.syncSubviews()
        if focusedPane == pane {
            let remaining = rest.leaves
            focus(remaining[min(max(index - 1, 0), remaining.count - 1)])
        }
        return true
    }

    func focus(_ pane: Int) {
        guard let terminal = panes[pane] else { return }
        noteFocus(pane)
        terminal.window?.makeFirstResponder(terminal)
    }

    /// Records that a pane got the focus by itself (a click).
    func noteFocus(_ pane: Int) {
        guard panes[pane] != nil else { return }
        focusedPane = pane
        layout.focused = pane
    }

    /// The pane id of a terminal, for its callbacks.
    func pane(of terminal: TerminalView) -> Int? {
        panes.first { $0.value === terminal }?.key
    }
}
