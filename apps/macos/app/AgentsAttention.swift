import AgentTools
import Agents
import AppKit
import Sidebar
import Terminal
import Themes

/// Attention for the whole app (docs/spec/agents.md, Atenção and Quadro;
/// plan 19 phase C): every terminal's agent state gathered across windows,
/// the permissions waiting on the app's socket, the bell's number in each
/// window's sidebar and the Dock's. Nothing goes to an agent without a click.
extension AppDelegate {
    func startAttention() {
        let attention = AgentAttention.shared
        NotificationCenter.default.addObserver(forName: TerminalView.agentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.gatherAgentReports() }
        }
        attention.onMarkUnread = { [weak self] key in self?.terminal(key: key)?.terminal.markAgentUnseen() }
        AgentToolsServer.shared.onPermission = { [weak self] event, reply, cancel in
            guard let self else { return reply(nil) }
            let found = self.terminal(pid: event.pid)
            let session = AgentsController.shared.sessions.first { $0.pid == event.pid }
            let id = attention.addPermission(pid: event.pid, tool: event.toolName ?? "?", subject: event.toolSubject ?? "",
                                             project: AgentProject.of(event.cwd ?? session?.cwd ?? "").name,
                                             session: found.map { Self.conversationName($0.terminal) } ?? session?.name ?? "",
                                             account: session?.account.name ?? "", key: found.map { Self.key($0.terminal) }, reply: reply)
            cancel.onCancel = { attention.resolve(id) }
            if cancel.isCancelled { attention.resolve(id) }
        }
        _ = attention.watch { [weak self] in self?.showAttentionCount() }
    }

    /// Every terminal running an agent that reported, in every window.
    func gatherAgentReports() {
        var reports: [AgentReport] = []
        for window in sessions {
            for space in window.spaces?.spaces ?? [] {
                for terminal in space.tabs.allTerminals {
                    guard let status = terminal.agentStatus else { continue }
                    let pid = terminal.foregroundGroup
                    let session = AgentsController.shared.sessions.first { $0.pid == pid }
                    reports.append(AgentReport(key: Self.key(terminal), pid: pid,
                                               state: AgentReport.State(rawValue: "\(status.state)") ?? .idle,
                                               kind: AgentReport.Kind(rawValue: "\(status.kind)") ?? .none,
                                               message: status.message, finishedUnseen: terminal.agentFinishedUnseen,
                                               project: AgentProject.of(terminal.currentDirectory ?? "").name,
                                               session: Self.conversationName(terminal), account: session?.account.name ?? ""))
                }
            }
        }
        AgentAttention.shared.update(reports)
    }

    /// The bell's number in each window and the Dock's (agents.dockBadge).
    func showAttentionCount() {
        let count = AgentAttention.shared.unseen
        for window in sessions { window.workspace?.sidebar.setBadge(count > 0 ? "\(count)" : nil, for: "attention") }
        NSApp.dockTile.badgeLabel = settings.store.settings.agents.dockBadge && count > 0 ? "\(count)" : nil
    }

    /// A card's or a feed line's terminal, brought to the front: its window,
    /// space and tab. Unknown: the beep.
    func goToAgent(key: String?, pid: Int32) {
        guard let found = key.flatMap({ terminal(key: $0) }) ?? (pid > 0 ? terminal(pid: pid) : nil) else { return NSSound.beep() }
        NSApp.activate(ignoringOtherApps: true)
        found.window.window.makeKeyAndOrderFront(nil)
        found.window.spaces?.select(found.space)
        found.window.tabs?.focus(found.terminal)
    }

    private func terminal(key: String) -> (window: WindowSession, space: Int, terminal: TerminalView)? {
        locate { Self.key($0) == key }
    }

    private func terminal(pid: Int32) -> (window: WindowSession, space: Int, terminal: TerminalView)? {
        pid > 0 ? locate { $0.foregroundGroup == pid } : nil
    }

    private func locate(_ match: (TerminalView) -> Bool) -> (window: WindowSession, space: Int, terminal: TerminalView)? {
        for window in sessions {
            for (index, space) in (window.spaces?.spaces ?? []).enumerated() {
                if let terminal = space.tabs.allTerminals.first(where: match) { return (window, index, terminal) }
            }
        }
        return nil
    }

    static func key(_ terminal: TerminalView) -> String { "\(ObjectIdentifier(terminal).hashValue)" }

    /// The conversation's name from the title the agent set, without a
    /// leading glyph; the folder when it set none.
    static func conversationName(_ terminal: TerminalView) -> String {
        let name = String(terminal.programTitle.drop { !$0.isLetter && !$0.isNumber }).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? ((terminal.currentDirectory ?? "") as NSString).lastPathComponent : name
    }
}

/// The bell's page in this window.
extension WindowSession {
    func makeAttentionPage() -> AgentAttentionView {
        let page = AgentAttentionView()
        page.colors = Self.agentColors()
        page.onGoTo = { [weak self] key, pid in self?.app.goToAgent(key: key, pid: pid) }
        page.onEnable = { [weak self] in self?.settings.store.update { $0.agents.attention = true } }
        ThemeStore.shared.observe { [weak page] _ in page?.colors = Self.agentColors() }
        attentionPage = page
        return page
    }

    /// agents.show-attention and agents.show-feed: the bell's page, on that sub-tab.
    func showAttention(_ subtab: String) {
        workspace?.showSidebar("attention")
        workspace?.sidebar.select(subtab: subtab, of: "attention")
        attentionPage?.subtab = subtab
    }
}
