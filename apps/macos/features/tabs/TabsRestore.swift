import AppKit
import Terminal

/// Saving and rebuilding a window's tabs (docs/spec/spaces.md), and the
/// switches a space needs: shown or hidden, closed all at once.
extension TabsController {
    /// The tabs as they are now, in order, with the active one.
    public func snapshot() -> TabsSnapshot {
        var items: [TabsSnapshot.Item] = []
        var active: Int?
        for id in list.order {
            let item: TabsSnapshot.Item
            if let document = documents[id] {
                item = .document(identity: document.identity)
            } else if let tab = tabs[id] {
                item = tab.snapshot(home: home)
            } else {
                continue
            }
            if id == list.active { active = items.count }
            items.append(item)
        }
        return TabsSnapshot(items: items, active: active)
    }

    /// Rebuilds saved tabs after the current ones: terminals with new
    /// shells in the saved folders; documents through `reopen`, which opens
    /// them here with open(_:) or skips the ones that are gone.
    public func restore(_ snapshot: TabsSnapshot, reopen: (String) -> Void) {
        var ids: [Int?] = []
        for item in snapshot.items {
            switch item {
            case let .terminal(title, layout, focus):
                ids.append(restoreTerminal(title: title, layout: layout, focus: focus))
            case let .document(identity):
                reopen(identity)
                ids.append(documents.first { $0.value.identity == identity }?.key)
            }
        }
        if let index = snapshot.active, index < ids.count, let id = ids[index] { select(id) }
    }

    private func restoreTerminal(title: String?, layout: TabsSnapshot.Layout, focus: Int) -> Int {
        var counter = nextPane
        let tree = PaneTree.from(layout) {
            defer { counter += 1 }
            return counter
        }
        nextPane = counter
        var panes: [Int: TerminalView] = [:]
        for (pane, folder) in zip(tree.leaves, layout.folders) {
            panes[pane] = makeTerminal(cwd: folder)
        }
        let leaves = tree.leaves
        let tab = Tab(id: nextId, tree: tree, panes: panes, focused: leaves[min(max(focus, 0), leaves.count - 1)])
        nextId += 1
        tab.customTitle = title
        add(tab)
        for (pane, terminal) in panes { wire(terminal, pane: pane, in: tab) }
        list.insert(tab.id)
        showActive()
        return tab.id
    }

    /// A space comes into the window (or leaves it): only the shown tabs
    /// retitle the window and take the keyboard.
    public func setShown(_ shown: Bool) {
        isShown = shown
        if shown { showActive() }
    }

    /// Ends every tab without asking: the caller asked (shouldCloseAll).
    public func closeAll() {
        for document in documents.values {
            document.close()
            document.view.removeFromSuperview()
        }
        for tab in tabs.values {
            tab.terminals.forEach { $0.closeSession() }
            tab.view.removeFromSuperview()
        }
        documents = [:]
        tabs = [:]
        list = TabList()
    }
}
