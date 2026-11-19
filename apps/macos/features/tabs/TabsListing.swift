import Terminal

extension TabsController {
    /// Each terminal pane in tab order, with its tab's title (plan 39 B:
    /// `cadex attach` lists them, by project, for the phone).
    public var listedTerminals: [(title: String, terminal: TerminalView)] {
        list.order.compactMap { tabs[$0] }.flatMap { tab in
            let title = tab.title(home: home)
            return tab.terminals.map { (title, $0) }
        }
    }
}
