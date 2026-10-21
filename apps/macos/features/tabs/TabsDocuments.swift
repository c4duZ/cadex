import AppKit

/// Documents in panes (docs/spec/tabs.md, "Documentos em painéis"): a
/// document lives in a pane like a terminal, alone in its tab or beside
/// others.
extension TabsController {
    /// The focused pane's document in the active tab, if it is one.
    public var activeDocument: TabDocument? { activeTab?.focused.document }

    /// The open document with this identity, in any pane of any tab.
    public func document(identity: String) -> TabDocument? {
        allDocuments.first { $0.identity == identity }
    }

    /// Every open document, for passing on disk changes.
    public var allDocuments: [TabDocument] { list.order.flatMap { tabs[$0]?.documents ?? [] } }

    /// Shows `document` in a new tab to the right of the active one, or
    /// goes to the pane that already shows the same identity.
    public func open(_ document: TabDocument) {
        open(document, beside: false)
    }

    /// tabs.documentSide: a document opened beside docks at the left.
    nonisolated(unsafe) public static var documentsOnLeft = false

    /// Shows `document` beside the panes, or in a new tab when `beside` is
    /// false. Beside, in this order (docs/spec/tabs.md): the pane that
    /// already shows it; the active tab's document pane with nothing
    /// unsaved, which it replaces; docked at one side with half the tab,
    /// the other panes sharing the other half (issue #5); a split to the
    /// right of the focused pane; a new tab when there is no room. Opening
    /// file after file never stacks splits. `keeping`: the document that
    /// asked (the history opening a diff), never replaced by what it opens.
    public func open(_ document: TabDocument, beside: Bool, keeping: TabDocument? = nil) {
        if reveal(identity: document.identity) { return }
        guard beside, let tab = activeTab else { return addTab(.document(document)) }
        if let pane = reusablePane(in: tab, keeping: keeping) {
            replace(pane, in: tab, with: document)
        } else if tab.dockedPane == nil, tab.canDock {
            dock(document, in: tab)
        } else if tab.canSplit(axis: .horizontal) {
            split(tab, axis: .horizontal, with: .document(document))
        } else {
            addTab(.document(document))
        }
    }

    /// A document pane whose content can go without asking: the focused
    /// one first, then the first in reading order.
    private func reusablePane(in tab: Tab, keeping: TabDocument?) -> Int? {
        let clean = { (id: Int) in
            tab.panes[id]?.document.map { !$0.hasUnsavedChanges && $0 !== keeping } ?? false
        }
        if clean(tab.focusedPane) { return tab.focusedPane }
        return tab.tree.leaves.first(where: clean)
    }

    private func dock(_ document: TabDocument, in tab: Tab) {
        let pane = nextPane
        nextPane += 1
        tab.dock(pane: pane, content: .document(document), first: Self.documentsOnLeft)
        wire(.document(document), pane: pane, in: tab)
        refreshBar()
    }

    private func replace(_ pane: Int, in tab: Tab, with document: TabDocument) {
        guard let old = tab.panes[pane] else { return }
        tab.replace(pane: pane, with: .document(document))
        wire(.document(document), pane: pane, in: tab)
        end(old)
        tab.focus(pane)
        refreshBar()
    }

    /// Selects the tab and focuses the pane showing `identity`, if any.
    func reveal(identity: String) -> Bool {
        for id in list.order {
            guard let tab = tabs[id], let pane = tab.pane(identity: identity) else { continue }
            tab.noteFocus(pane)
            select(id)
            return true
        }
        return false
    }
}
