import Agents
import AppKit
import Icons
import Settings
import Sidebar
import StatusBar
import Strings
import Terminal
import Themes

/// The Agents page, its icon's dot and the status bar's Agents item in this
/// window (docs/spec/agents.md). All of them read through the one
/// AgentsController, and only while they show: the page while it is on
/// screen, the dot while the icon is in the sidebar, the item while it is
/// in the bar.
extension WindowSession {
    func makeAgentsPage() -> AgentsView {
        let page = AgentsView()
        page.isInCadex = { [weak self] session in self?.terminal(of: session) != nil }
        page.onOpen = { [weak self] session in self?.openAgent(session) }
        page.onEnable = { [weak self] in self?.settings.store.update { $0.agents.sessions = true } }
        return page
    }

    func makeAgentsItem() -> StatusItem {
        let label = StatusLabel(icon: .sparkle, tip: T("Agents working and waiting for you", "Agentes trabalhando e esperando você"))
        label.onClick = { [weak self] in _ = self?.commands.run("agents.show") }
        let item = StatusItem(id: "agents", title: T("Agents", "Agentes"),
                              subtitle: T("Working ◐ and waiting for you ●", "Trabalhando ◐ e esperando você ●"),
                              icon: .sparkle, side: .right, view: label)
        var token: UUID?
        item.onVisible = { [weak label] visible in
            if visible {
                token = AgentsController.shared.watch {
                    let counts = AgentsController.shared.counts
                    label?.text = "◐ \(counts.working)  ● \(counts.waiting)"
                    label?.tint = counts.waiting > 0 ? NSColor.systemBlue : nil
                }
            } else if let id = token {
                AgentsController.shared.stop(id)
                token = nil
            }
        }
        return item
    }

    /// The dot on the Agents icon while some agent waits for an answer;
    /// watched only while the icon is in the sidebar.
    func updateAgentsDot(shown: Bool, on sidebar: SidebarView) {
        if shown, agentsDotToken == nil {
            agentsDotToken = AgentsController.shared.watch { [weak sidebar] in
                sidebar?.setBadge(AgentsController.shared.counts.waiting > 0 ? "" : nil, for: "agents")
            }
        } else if !shown, let token = agentsDotToken {
            AgentsController.shared.stop(token)
            agentsDotToken = nil
            sidebar.setBadge(nil, for: "agents")
        }
    }

    /// The terminal an agent runs in: the one whose foreground process
    /// group is the agent's (the core's cadex_terminal_foreground_group),
    /// with the index of its space.
    func terminal(of session: AgentSession) -> (space: Int, terminal: TerminalView)? {
        let group = getpgid(session.pid)
        guard group > 0, let spaces else { return nil }
        for (index, space) in spaces.spaces.enumerated() {
            if let terminal = space.tabs.allTerminals.first(where: { $0.foregroundGroup == group }) { return (index, terminal) }
        }
        return nil
    }

    /// A double click: the agent's terminal, its space and tab in front;
    /// outside Cadex, its folder in the tree when it is in the workspace.
    func openAgent(_ session: AgentSession) {
        if let found = terminal(of: session), let spaces {
            spaces.select(found.space)
            tabs?.focus(found.terminal)
            return
        }
        if explorer?.reveal(session.cwd) == true { workspace?.showSidebar("files") } else { NSSound.beep() }
    }
}

/// The notifications when an agent stops, for the whole app: not while you
/// look at that agent's terminal in the key window; a click goes to it in
/// whichever window holds it (docs/spec/agents.md, Notificações).
extension AppDelegate {
    func startAgentNotifications() {
        let notifier = AgentNotifier.shared
        notifier.isLooking = { [weak self] session in
            guard NSApp.isActive, let key = self?.sessions.first(where: { $0.window.isKeyWindow }),
                  let found = key.terminal(of: session) else { return false }
            return key.tabs?.activeTerminal === found.terminal
        }
        notifier.onOpen = { [weak self] id in
            guard let session = AgentsController.shared.sessions.first(where: { $0.id == id }) else { return }
            let owner = self?.sessions.first { $0.terminal(of: session) != nil } ?? self?.sessions.first
            NSApp.activate(ignoringOtherApps: true)
            owner?.window.makeKeyAndOrderFront(nil)
            owner?.openAgent(session)
        }
        ThemeStore.shared.observe { theme in AgentNotifier.shared.accent = theme.interface.accent.nsColor }
        notifier.start()
    }
}
