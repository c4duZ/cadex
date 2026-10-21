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
            guard let tab = tabs[id] else { continue }
            if id == list.active { active = items.count }
            items.append(tab.snapshot(home: home))
        }
        return TabsSnapshot(items: items, active: active)
    }

    /// Rebuilds saved tabs after the current ones: terminals with new
    /// shells in the saved folders; documents made by `makeDocument` from
    /// their identity (nil when the file is gone). A lone document that is
    /// gone drops its tab; one beside others becomes a terminal in its
    /// folder, so the layout stays (docs/spec/spaces.md).
    public func restore(_ snapshot: TabsSnapshot, makeDocument: (String) -> TabDocument?) {
        var ids: [Int?] = []
        for item in snapshot.items {
            switch item {
            case let .terminal(title, layout, focus, color):
                let id = restoreTab(title: title, layout: layout, focus: focus, makeDocument: makeDocument)
                if let id { tabs[id]?.color = color }
                ids.append(id)
            case let .document(identity):
                ids.append(restoreTab(title: nil, layout: .document(identity: identity), focus: 0, makeDocument: makeDocument))
            }
        }
        if let index = snapshot.active, index < ids.count, let id = ids[index] { select(id) }
    }

    private func restoreTab(title: String?, layout: TabsSnapshot.Layout, focus: Int,
                            makeDocument: (String) -> TabDocument?) -> Int? {
        var counter = nextPane
        let tree = PaneTree.from(layout) {
            defer { counter += 1 }
            return counter
        }
        var panes: [Int: Pane] = [:]
        for (pane, leaf) in zip(tree.leaves, layout.leaves) {
            switch leaf {
            case .pane(let folder):
                panes[pane] = .terminal(makeTerminal(cwd: folder))
            case .document(let identity):
                if let document = makeDocument(identity) {
                    panes[pane] = .document(document)
                } else if tree.leaves.count > 1 {
                    let folder = identity.hasPrefix("/") ? (identity as NSString).deletingLastPathComponent : home
                    panes[pane] = .terminal(makeTerminal(cwd: folder))
                }
            case .split:
                break
            }
        }
        guard panes.count == tree.leaves.count else { return nil }
        nextPane = counter
        let leaves = tree.leaves
        let tab = Tab(id: nextId, tree: tree, panes: panes, focused: leaves[min(max(focus, 0), leaves.count - 1)])
        nextId += 1
        tab.customTitle = title
        add(tab)
        for (pane, content) in panes { wire(content, pane: pane, in: tab) }
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
        for tab in tabs.values {
            tab.ordered.forEach(end)
            tab.view.removeFromSuperview()
        }
        tabs = [:]
        list = TabList()
    }
}
