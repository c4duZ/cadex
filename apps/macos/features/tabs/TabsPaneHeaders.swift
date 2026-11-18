import AppKit
import Icons
import Menus
import StateGlyph
import Strings
import Terminal

/// The pane headers of every tab (PaneHeaderView.swift): what each one
/// says, and its buttons, which focus their pane and run a command by id
/// (ADR 0005): pane.close, pane.zoom; the "+" menu is the app's (paneMenu). Apart from
/// TabsController.swift, at its size limit.
/// What the app knows of the agent in a terminal, for its pane's header (plan 28 phase B): the
/// app works it out when an agent changes and keeps it; the header only reads it.
/// A race contender's second line and its cap (the Race mockup's lanes).
public struct PaneLane: Equatable, Sendable {
    /// "Working · US$ 0.42 · +88 −41 in 4 files".
    public var status: String
    /// 0…1 of the cap spent (money or minutes, whichever is further).
    public var cap: Double
    public init(status: String, cap: Double) {
        self.status = status
        self.cap = cap
    }
}

public struct PaneDetail: Equatable, Sendable {
    /// "Claude".
    public var title: String
    /// "orchestration-e · Opus · bkdg".
    public var detail: String
    /// "US$ 0.31 · 4 min".
    public var trailing: String
    /// A race's contender: the lane's second line and cap bar.
    public var lane: PaneLane?
    /// A click on the detail lists the accounts to go on in (plan 33 E; paneAccountMenu).
    public var accountSwitch: Bool

    public init(title: String, detail: String, trailing: String, lane: PaneLane? = nil, accountSwitch: Bool = false) {
        self.title = title
        self.detail = detail
        self.trailing = trailing
        self.lane = lane
        self.accountSwitch = accountSwitch
    }
}

extension TabsController {
    /// The detail of an agent's terminal, from the app (every window's); nil: a plain terminal.
    @MainActor public static var paneDetail: (TerminalView) -> PaneDetail? = { _ in nil }
    /// The accounts an agent's terminal can go on in, from the app (plan 33 E).
    @MainActor public static var paneAccountMenu: (TerminalView) -> [MenuEntry] = { _ in [] }

    /// Every pane header of these tabs says again what it shows (an agent's detail changed).
    public func refreshPaneHeaders() {
        for tab in tabs.values { tab.layout.refreshHeaders() }
    }

    func wireHeaders(_ tab: Tab) {
        tab.layout.headerStyle = bar.style
        tab.layout.describe = { [weak self, weak tab] id in
            guard let self, let pane = tab?.panes[id] else { return nil }
            return self.headerInfo(pane)
        }
        tab.layout.onHeaderAction = { [weak self, weak tab] id, action in
            guard let self, let tab else { return }
            if case .drag(let phase, let point) = action { return tab.layout.dragPane(id, phase, at: point) }
            tab.focus(id)
            self.refreshBar()
            switch action {
            case .focus: break
            case .close: self.run("pane.close") { self.closeFocusedPane() }
            case .zoom: self.run("pane.zoom") { self.toggleZoom() }
            case .menu(let anchor): PopupMenu.show(self.paneMenu?() ?? [], below: anchor)
            case .offer: tab.panes[id]?.terminal?.openServed()
            case .account(let anchor):
                if let terminal = tab.panes[id]?.terminal { PopupMenu.show(Self.paneAccountMenu(terminal), below: anchor) }
            case .drag: break
            }
        }
    }

    /// A pane's title and icon: a terminal's program, else its folder; a
    /// document's name and file icon, with a dot when unsaved.
    func headerInfo(_ pane: Pane) -> PaneHeaderView.Info {
        switch pane {
        case .terminal(let terminal):
            let program = terminal.programTitle
            var info = PaneHeaderView.Info(title: program.isEmpty ? folderTitle(terminal.currentDirectory, home: home) : program,
                                           icon: .terminalWindow, padded: true)
            info.state = TabAgentTitle.state(terminal.agentStatus, hibernated: terminal.isHibernated)
            TabCommandLooks.header(&info, terminal: terminal)
            if let agent = Self.paneDetail(terminal) {
                // An agent waiting at its prompt has no state to report: the idle ring, as the tree.
                info.state = info.state ?? .idle
                info.title = agent.title
                info.detail = agent.detail
                info.trailing = agent.trailing
                info.lane = agent.lane
                info.accountSwitch = agent.accountSwitch
            }
            return info
        case .document(let document):
            let (icon, color) = Self.tabIcon(for: document.identity)
            var info = PaneHeaderView.Info(title: document.title, icon: icon, iconColor: color, image: Self.tabImage(for: document.identity),
                                           dirty: document.hasUnsavedChanges)
            info.hidden = document.barIsHeader || document.isPage
            info.page = document.isPage
            return info
        }
    }

    func refreshHeaders() {
        for tab in tabs.values {
            tab.layout.headerStyle = bar.style
        }
    }

    /// pane.zoom: the focused pane takes the whole tab, or gives it back.
    public func toggleZoom() {
        guard let tab = activeTab, tab.tree.leaves.count > 1 || tab.layout.zoomed != nil else { return }
        tab.layout.zoomed = tab.layout.zoomed == nil ? tab.focusedPane : nil
        tab.focusContent()
        refreshBar()
    }

    public var activePaneZoomed: Bool { activeTab?.layout.zoomed != nil }

    /// The command by id, or `fallback` where no registry runs it (tests).
    private func run(_ command: String, fallback: () -> Void) {
        if runCommand?(command) != true { fallback() }
    }
}
