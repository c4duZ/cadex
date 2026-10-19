import AppKit
import Terminal

/// Closing panes, tabs and the window (docs/spec/tabs.md, "Fechar"),
/// asking first over a running program or an unsaved file.
extension TabsController {
    /// ⌘W: closes the focused pane; the last pane closes the tab, and the
    /// last tab the window (docs/spec/tabs.md, "Fechar").
    public func closeFocusedPane() {
        if let id = list.active, documents[id] != nil {
            closeTab(id)
            return
        }
        guard let tab = activeTab else { return }
        let pane = tab.focusedPane
        let running = tab.focused.hasForegroundProcess
        CloseConfirmation.confirm(running: running, in: window, what: "o painel") { [weak self, weak tab] in
            guard let tab else { return }
            self?.removePane(pane, from: tab)
        }
    }

    func removePane(_ pane: Int, from tab: Tab) {
        guard let terminal = tab.panes[pane] else { return }
        if tab.terminals.count == 1 {
            remove(tab.id)
            return
        }
        terminal.closeSession()
        _ = tab.remove(pane: pane)
        refreshBar()
    }

    func closeTab(_ id: Int) {
        if let document = documents[id] {
            document.confirmClose(in: window) { [weak self] in self?.remove(id) }
            return
        }
        guard let tab = tabs[id] else { return }
        CloseConfirmation.confirm(running: tab.hasForegroundProcess, in: window, what: "a aba") { [weak self] in
            self?.remove(id)
        }
    }

    /// Ends the tab's sessions and drops it; the last one closes the window.
    func remove(_ id: Int) {
        if let document = documents.removeValue(forKey: id) {
            document.close()
            document.view.removeFromSuperview()
        } else if let tab = tabs.removeValue(forKey: id) {
            tab.terminals.forEach { $0.closeSession() }
            tab.view.removeFromSuperview()
        } else {
            return
        }
        list.remove(id)
        if list.order.isEmpty {
            if let onEmpty { onEmpty() } else { window?.close() }
        } else {
            showActive()
        }
    }

    /// Closing the window or quitting: asks once if any pane runs a program.
    /// True when it can close now; otherwise `close` runs after confirming.
    public func shouldCloseAll(then close: @escaping @MainActor () -> Void,
                               cancelled: @escaping @MainActor () -> Void = {}) -> Bool {
        Self.shouldClose([self], in: window, then: close, cancelled: cancelled)
    }

    /// The same for several sets of tabs (every space), with one question:
    /// a program running in a hidden space counts too.
    public static func shouldClose(_ all: [TabsController], in window: NSWindow?, what: String = "a janela",
                                   then close: @escaping @MainActor () -> Void,
                                   cancelled: @escaping @MainActor () -> Void = {}) -> Bool {
        let unsaved = all.reduce(0) { $0 + $1.documents.values.filter(\.hasUnsavedChanges).count }
        if unsaved > 0 {
            CloseConfirmation.confirmUnsaved(count: unsaved, in: window, then: close, cancelled: cancelled)
            return false
        }
        let running = all.contains { $0.tabs.values.contains { $0.hasForegroundProcess } }
        let asks = TerminalPreferences.current.confirmClose
        guard running, asks else { return true }
        CloseConfirmation.confirm(running: true, in: window, what: what, then: close, cancelled: cancelled)
        return false
    }

    /// The window these tabs live in, for a space's questions.
    public var hostWindow: NSWindow? { window }
}
