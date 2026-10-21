import AppKit
import Strings
import Terminal

/// Closing panes, tabs and the window (docs/spec/tabs.md, "Fechar"),
/// asking first over a running program or an unsaved file.
extension TabsController {
    /// ⌘W: closes the focused pane; the last pane closes the tab, and the
    /// last tab the window (docs/spec/tabs.md, "Fechar").
    public func closeFocusedPane() {
        guard let tab = activeTab else { return }
        let pane = tab.focusedPane
        let close = { @MainActor [weak self, weak tab] in
            guard let tab else { return }
            self?.removePane(pane, from: tab)
        }
        switch tab.focused {
        case .document(let document):
            document.confirmClose(in: window, then: close)
        case .terminal(let terminal):
            CloseConfirmation.confirm(running: terminal.hasForegroundProcess, in: window, what: T("the pane", "o painel"), then: close)
        }
    }

    func removePane(_ pane: Int, from tab: Tab) {
        guard let content = tab.panes[pane] else { return }
        if tab.panes.count == 1 {
            remove(tab.id)
            return
        }
        end(content)
        _ = tab.remove(pane: pane)
        refreshBar()
    }

    /// A pane's content is gone for good: the shell ends, the document
    /// stops watching.
    func end(_ content: Pane) {
        switch content {
        case .terminal(let terminal): terminal.closeSession()
        case .document(let document): document.close()
        }
        content.view.removeFromSuperview()
    }

    /// The tab's ×: a lone document asks itself (save, discard); otherwise
    /// one question for the unsaved files, then one for running programs.
    func closeTab(_ id: Int) {
        guard let tab = tabs[id] else { return }
        if tab.panes.count == 1, let document = tab.focused.document {
            document.confirmClose(in: window) { [weak self] in self?.remove(id) }
            return
        }
        let window = window
        let afterUnsaved = { @MainActor [weak self] in
            CloseConfirmation.confirm(running: tab.hasForegroundProcess, in: window, what: T("the tab", "a aba")) { self?.remove(id) }
        }
        let unsaved = tab.unsavedCount
        guard unsaved > 0 else { return afterUnsaved() }
        CloseConfirmation.confirmUnsaved(count: unsaved, in: window, then: afterUnsaved, cancelled: {})
    }

    /// Ends the tab's sessions and documents and drops it; the last one
    /// closes the window.
    func remove(_ id: Int) {
        guard let tab = tabs.removeValue(forKey: id) else { return }
        tab.ordered.forEach(end)
        tab.view.removeFromSuperview()
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
    public static func shouldClose(_ all: [TabsController], in window: NSWindow?, what: String = T("the window", "a janela"),
                                   then close: @escaping @MainActor () -> Void,
                                   cancelled: @escaping @MainActor () -> Void = {}) -> Bool {
        let unsaved = all.reduce(0) { $0 + $1.tabs.values.reduce(0) { $0 + $1.unsavedCount } }
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

    /// Whether a terminal in any tab runs a program (keep-awake's
    /// "com programa rodando", docs/spec/power.md).
    public var hasRunningProgram: Bool { tabs.values.contains { $0.hasForegroundProcess } }

    /// Every terminal in every tab and pane (an agent's terminal, docs/spec/agents.md).
    public var allTerminals: [TerminalView] { tabs.values.flatMap(\.terminals) }

    /// The terminals in every tab and pane (the status bar's Terminals item).
    public var terminalCount: Int { tabs.values.reduce(0) { $0 + $1.terminals.count } }
}
