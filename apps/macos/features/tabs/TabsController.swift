import AppKit
import Terminal

/// The tabs of a window: opening, closing, switching, renaming and
/// reordering (docs/spec/tabs.md). Its actions are commands (TabCommands).
@MainActor
public final class TabsController {
    public let view: TabsView
    private var list = TabList()
    private var tabs: [Int: Tab] = [:]
    private var nextId = 1
    private weak var window: NSWindow?
    private let home = NSHomeDirectory()
    /// Coalesces title refreshes while output streams in.
    private var titleRefreshPending = false

    public init(window: NSWindow) {
        self.window = window
        view = TabsView(frame: window.contentView?.bounds ?? .zero)
        view.bar.onSelect = { [weak self] in self?.select($0) }
        view.bar.onClose = { [weak self] in self?.closeTab($0) }
        view.bar.onRename = { [weak self] in self?.rename($0) }
        view.bar.onMove = { [weak self] id, index in
            self?.list.move(id, to: index)
            self?.refreshBar()
        }
    }

    public var activeTerminal: TerminalView? { list.active.flatMap { tabs[$0]?.focused } }
    var activeTab: Tab? { list.active.flatMap { tabs[$0] } }
    public var count: Int { list.order.count }

    // MARK: Opening and switching

    /// ⌘T: a terminal in `cwd`, or in the active terminal's folder, or home.
    public func newTab(cwd: String? = nil) {
        let folder = cwd ?? activeTerminal?.currentDirectory ?? home
        let start = FileManager.default.fileExists(atPath: folder) ? folder : home
        let terminal = TerminalView(frame: view.bounds, cwd: start)
        let tab = Tab(id: nextId, terminal: terminal)
        nextId += 1
        tabs[tab.id] = tab
        wire(terminal, in: tab)
        list.insert(tab.id)
        showActive()
    }

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
        guard let tab = activeTab else { return }
        view.show(tab.view)
        window?.makeFirstResponder(tab.focused)
        refreshBar()
    }

    private func wire(_ terminal: TerminalView, in tab: Tab) {
        terminal.onShellExit = { [weak self] in self?.remove(tab.id) }
        terminal.onActivity = { [weak self] in self?.scheduleTitleRefresh() }
        terminal.onProgramTitle = { [weak self] _ in self?.refreshBar() }
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
        view.bar.items = list.order.compactMap { id in
            tabs[id].map { TabBarView.Item(id: id, title: $0.title(home: home), active: id == list.active) }
        }
        let program = activeTab?.focused.programTitle ?? ""
        window?.title = program.isEmpty ? (activeTab?.title(home: home) ?? "Cadex") : program
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

    /// ⌘W: closes the focused pane, which today is the whole tab.
    public func closeFocusedPane() {
        if let id = list.active { closeTab(id) }
    }

    func closeTab(_ id: Int) {
        guard let tab = tabs[id] else { return }
        CloseConfirmation.confirm(running: tab.hasForegroundProcess, in: window, what: "a aba") { [weak self] in
            self?.remove(id)
        }
    }

    /// Ends the tab's sessions and drops it; the last one closes the window.
    private func remove(_ id: Int) {
        guard let tab = tabs.removeValue(forKey: id) else { return }
        tab.terminals.forEach { $0.closeSession() }
        tab.view.removeFromSuperview()
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
        let running = tabs.values.contains { $0.hasForegroundProcess }
        let asks = UserDefaults.standard.object(forKey: CloseConfirmation.preferenceKey) as? Bool ?? true
        guard running, asks else { return true }
        CloseConfirmation.confirm(running: true, in: window, what: "a janela", then: close, cancelled: cancelled)
        return false
    }
}
