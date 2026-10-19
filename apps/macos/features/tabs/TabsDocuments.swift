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
        if reveal(identity: document.identity) { return }
        addTab(.document(document))
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
