import AppKit
import Icons
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
    /// "Abrir no preview" was clicked in a terminal, for a local address.
    public var onOpenPreview: ((String) -> Void)?
    /// Anything the snapshot holds changed (tabs, panes, folders, titles):
    /// the spaces save it.
    public var onStateChange: (() -> Void)?
    /// The last tab closed. Without it, the window closes (one space).
    public var onEmpty: (() -> Void)?
    /// Whether these tabs are the ones in the window. Spaces keep the
    /// others alive but hidden: they must not retitle the window or take
    /// the keyboard.
    public var isShown = true
    var list = TabList()
    var tabs: [Int: Tab] = [:]
    var nextId = 1
    var nextPane = 1
    weak var window: NSWindow?
    let home = NSHomeDirectory()
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

    /// The focused pane's terminal in the active tab, if it is one.
    public var activeTerminal: TerminalView? { activeTab?.focused.terminal }
    var activeTab: Tab? { list.active.flatMap { tabs[$0] } }
    public var count: Int { list.order.count }

    // MARK: Opening and switching

    /// ⌘T: a terminal in `cwd`, or in the active terminal's folder, or home.
    public func newTab(cwd: String? = nil) {
        let terminal = makeTerminal(cwd: cwd)
        addTab(.terminal(terminal))
    }

    /// A new tab with one pane, right of the active one, and selects it.
    func addTab(_ content: Pane) {
        let pane = nextPane
        nextPane += 1
        let tab = Tab(id: nextId, pane: pane, content: content)
        nextId += 1
        add(tab)
        wire(content, pane: pane, in: tab)
        list.insert(tab.id)
        showActive()
    }

    func add(_ tab: Tab) {
        tabs[tab.id] = tab
        tab.onLayoutChange = { [weak self] in self?.onStateChange?() }
    }

    /// The folder new terminals start in: the focused pane's (a terminal's
    /// folder, or a document's file's).
    private var activeFolder: String? { activeTab?.focused.folder }

    /// A terminal in `cwd`, or in the active terminal's folder, or home
    /// when that folder is gone (docs/spec/tabs.md, casos de borda).
    func makeTerminal(cwd: String?) -> TerminalView {
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
        split(tab, axis: axis, with: .terminal(makeTerminal(cwd: tab.focused.folder)))
    }

    /// Splits `tab`'s focused pane; `content` goes into the new one, focused.
    func split(_ tab: Tab, axis: PaneTree.Axis, with content: Pane) {
        let pane = nextPane
        nextPane += 1
        tab.split(axis: axis, pane: pane, content: content)
        wire(content, pane: pane, in: tab)
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

    func showActive() {
        guard let tab = activeTab else { return }
        view.show(tab.view)
        if isShown { tab.focusContent() }
        refreshBar()
    }

    func wire(_ content: Pane, pane: Int, in tab: Tab) {
        switch content {
        case .terminal(let terminal): wire(terminal, pane: pane, in: tab)
        case .document(let document): document.onChange = { [weak self] in self?.refreshBar() }
        }
    }

    private func wire(_ terminal: TerminalView, pane: Int, in tab: Tab) {
        // The shell exited by itself: nothing to ask, the pane just goes.
        terminal.onShellExit = { [weak self, weak tab] in
            guard let tab else { return }
            self?.removePane(pane, from: tab)
        }
        terminal.onActivity = { [weak self] in self?.scheduleTitleRefresh() }
        terminal.onOpenPreview = { [weak self] url in self?.onOpenPreview?(url) }
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

    func refreshBar() {
        bar.items = list.order.compactMap { id in tabs[id].map(barItem) }
        onStateChange?()
        guard isShown else { return }
        if let document = activeDocument {
            window?.title = document.title
            onActiveChange?()
            return
        }
        let program = activeTerminal?.programTitle ?? ""
        window?.title = program.isEmpty ? (activeTab?.title(home: home) ?? "Cadex") : program
        onActiveChange?()
    }

    /// A tab in the strip, titled and iconed by its focused pane.
    private func barItem(_ tab: Tab) -> TabBarView.Item {
        let title = tab.title(home: home)
        guard let document = tab.focused.document else {
            return TabBarView.Item(id: tab.id, title: title, active: tab.id == list.active)
        }
        let (icon, color) = Self.tabIcon(for: document.identity)
        return TabBarView.Item(id: tab.id, title: title, active: tab.id == list.active, icon: icon, iconColor: color,
                               image: Self.tabImage(for: document.identity))
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

    /// A document tab's icon from its identity: a file by its type and
    /// color, as in the explorer (owner, 2026-10-19: the tabs had one icon
    /// for every document); the git history and web pages by their kind.
    /// The file's Material drawing, when it has one (docs/adr/0011).
    static func tabImage(for identity: String) -> NSImage? {
        guard !identity.hasPrefix("history:"), !identity.hasPrefix("preview:") else { return nil }
        return FileIcons.image(forFileNamed: (identity as NSString).lastPathComponent)
    }

    static func tabIcon(for identity: String) -> (Icon, NSColor?) {
        if identity.hasPrefix("history:") { return (.gitCommit, nil) }
        if identity.hasPrefix("preview:") { return (.globe, nil) }
        // A path, or a diff ("diff:work:/repo/file"): the file's own name.
        let name = (identity as NSString).lastPathComponent
        return (FileIcons.icon(forFileNamed: name), FileIcons.color(forFileNamed: name))
    }
}
