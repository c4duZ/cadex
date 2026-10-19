import AppKit
import Terminal

/// The tabs of a window: opening, closing, switching, renaming and
/// reordering (docs/spec/tabs.md). Its actions are commands (TabCommands).
@MainActor
public final class TabsController {
    public let view: TabsView
    /// The tab strip, for the window's title bar.
    public let bar = TabBarView()
    /// The active tab, its focused pane or that pane's folder changed: the
    /// status bar follows.
    public var onActiveChange: (() -> Void)?
    private var list = TabList()
    private var tabs: [Int: Tab] = [:]
    /// Tabs that show a document instead of terminals (TabDocument).
    private var documents: [Int: TabDocument] = [:]
    private var nextId = 1
    private var nextPane = 1
    private weak var window: NSWindow?
    private let home = NSHomeDirectory()
    /// Coalesces title refreshes while output streams in.
    private var titleRefreshPending = false

    public init(window: NSWindow) {
        self.window = window
        view = TabsView(frame: window.contentView?.bounds ?? .zero)
        bar.onSelect = { [weak self] in self?.select($0) }
        bar.onClose = { [weak self] in self?.closeTab($0) }
        bar.onRename = { [weak self] in self?.rename($0) }
        bar.onMove = { [weak self] id, index in
            self?.list.move(id, to: index)
            self?.refreshBar()
        }
    }

    public var activeTerminal: TerminalView? { list.active.flatMap { tabs[$0]?.focused } }
    var activeTab: Tab? { list.active.flatMap { tabs[$0] } }
    public var count: Int { list.order.count }
    /// The document of the active tab, when it is not a terminal tab.
    public var activeDocument: TabDocument? { list.active.flatMap { documents[$0] } }

    /// The open document with this identity, if any.
    public func document(identity: String) -> TabDocument? {
        documents.values.first { $0.identity == identity }
    }

    /// Every open document, for passing on disk changes.
    public var allDocuments: [TabDocument] { list.order.compactMap { documents[$0] } }

    // MARK: Opening and switching

    /// ⌘T: a terminal in `cwd`, or in the active terminal's folder, or home.
    public func newTab(cwd: String? = nil) {
        let terminal = makeTerminal(cwd: cwd)
        let pane = nextPane
        nextPane += 1
        let tab = Tab(id: nextId, pane: pane, terminal: terminal)
        nextId += 1
        tabs[tab.id] = tab
        wire(terminal, pane: pane, in: tab)
        list.insert(tab.id)
        showActive()
    }

    /// Shows `document` in a new tab to the right of the active one, or
    /// selects the tab that already shows the same identity.
    public func open(_ document: TabDocument) {
        if let id = documents.first(where: { $0.value.identity == document.identity })?.key {
            select(id)
            return
        }
        let id = nextId
        nextId += 1
        documents[id] = document
        document.onChange = { [weak self] in self?.refreshBar() }
        list.insert(id)
        showActive()
    }

    /// The folder new terminals start in: the active terminal's, or the
    /// active document's.
    private var activeFolder: String? {
        if let terminal = activeTerminal { return terminal.currentDirectory }
        guard let path = activeDocument?.identity, path.hasPrefix("/") else { return nil }
        return (path as NSString).deletingLastPathComponent
    }

    /// A terminal in `cwd`, or in the active terminal's folder, or home
    /// when that folder is gone (docs/spec/tabs.md, casos de borda).
    private func makeTerminal(cwd: String?) -> TerminalView {
        let folder = cwd ?? activeFolder ?? home
        let start = FileManager.default.fileExists(atPath: folder) ? folder : home
        return TerminalView(frame: view.bounds, cwd: start)
    }

    // MARK: Panes

    /// ⌘D (right) and ⌘⇧D (down): a new pane in the same folder, focused.
    func split(_ axis: PaneTree.Axis) {
        guard let tab = activeTab, tab.canSplit(axis: axis) else {
            NSSound.beep()
            return
        }
        let terminal = makeTerminal(cwd: tab.focused.currentDirectory)
        let pane = nextPane
        nextPane += 1
        tab.split(axis: axis, pane: pane, terminal: terminal)
        wire(terminal, pane: pane, in: tab)
        refreshBar()
    }

    /// ⌘] and ⌘[.
    public func focusPane(step: Int) {
        guard let tab = activeTab, let next = tab.tree.cycling(from: tab.focusedPane, by: step) else { return }
        tab.focus(next)
        refreshBar()
    }

    /// ⌘⌥ + arrow.
    func focusPane(_ direction: PaneTree.Direction) {
        guard let tab = activeTab,
              let next = tab.tree.neighbor(of: tab.focusedPane, direction, in: tab.layout.bounds)
        else { return }
        tab.focus(next)
        refreshBar()
    }

    public var activePaneCount: Int { activeTab?.tree.leaves.count ?? 0 }

    func select(_ id: Int) {
        list.select(id)
        showActive()
    }

    /// ⌘1 to ⌘9.
    public func select(position: Int) {
        guard let id = list.id(atPosition: position) else { return }
        select(id)
    }

    /// Ctrl+Tab.
    public func selectPreviouslyUsed() {
        if let id = list.previouslyUsed { select(id) }
    }

    /// Ctrl+Shift+Tab.
    public func selectLeastRecentlyUsed() {
        if let id = list.leastRecentlyUsed { select(id) }
    }

    private func showActive() {
        if let document = activeDocument {
            view.show(document.view)
            document.focus()
            refreshBar()
            return
        }
        guard let tab = activeTab else { return }
        view.show(tab.view)
        window?.makeFirstResponder(tab.focused)
        refreshBar()
    }

    private func wire(_ terminal: TerminalView, pane: Int, in tab: Tab) {
        // The shell exited by itself: nothing to ask, the pane just goes.
        terminal.onShellExit = { [weak self, weak tab] in
            guard let tab else { return }
            self?.removePane(pane, from: tab)
        }
        terminal.onActivity = { [weak self] in self?.scheduleTitleRefresh() }
        terminal.onProgramTitle = { [weak self] _ in self?.refreshBar() }
        terminal.onFocus = { [weak self, weak tab] in
            tab?.noteFocus(pane)
            self?.refreshBar()
        }
    }

    // MARK: Titles

    private func scheduleTitleRefresh() {
        guard !titleRefreshPending else { return }
        titleRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.titleRefreshPending = false
            self?.refreshBar()
        }
    }

    private func refreshBar() {
        bar.items = list.order.compactMap { id in
            if let document = documents[id] {
                let title = document.hasUnsavedChanges ? "● " + document.title : document.title
                return TabBarView.Item(id: id, title: title, active: id == list.active)
            }
            return tabs[id].map { TabBarView.Item(id: id, title: $0.title(home: home), active: id == list.active) }
        }
        if let document = activeDocument {
            window?.title = document.title
            onActiveChange?()
            return
        }
        let program = activeTab?.focused.programTitle ?? ""
        window?.title = program.isEmpty ? (activeTab?.title(home: home) ?? "Cadex") : program
        onActiveChange?()
    }

    /// "Renomear aba": empty goes back to the folder name.
    public func renameActive() {
        if let id = list.active { rename(id) }
    }

    func rename(_ id: Int) {
        guard let tab = tabs[id], let window else { return }
        let alert = NSAlert()
        alert.messageText = "Renomear aba"
        alert.informativeText = "Deixe vazio para voltar ao nome da pasta."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = tab.customTitle ?? ""
        field.placeholderString = tab.title(home: home)
        alert.accessoryView = field
        alert.addButton(withTitle: "Renomear")
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1B}"
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                let name = field.stringValue.trimmingCharacters(in: .whitespaces)
                tab.customTitle = name.isEmpty ? nil : name
                self?.refreshBar()
            }
        }
    }

    // MARK: Closing

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

    private func removePane(_ pane: Int, from tab: Tab) {
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
    private func remove(_ id: Int) {
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
            window?.close()
        } else {
            showActive()
        }
    }

    /// Closing the window or quitting: asks once if any pane runs a program.
    /// True when it can close now; otherwise `close` runs after confirming.
    public func shouldCloseAll(then close: @escaping @MainActor () -> Void,
                               cancelled: @escaping @MainActor () -> Void = {}) -> Bool {
        let unsaved = documents.values.filter(\.hasUnsavedChanges).count
        if unsaved > 0 {
            CloseConfirmation.confirmUnsaved(count: unsaved, in: window, then: close, cancelled: cancelled)
            return false
        }
        let running = tabs.values.contains { $0.hasForegroundProcess }
        let asks = TerminalPreferences.current.confirmClose
        guard running, asks else { return true }
        CloseConfirmation.confirm(running: true, in: window, what: "a janela", then: close, cancelled: cancelled)
        return false
    }
}
