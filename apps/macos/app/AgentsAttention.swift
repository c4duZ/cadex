import AgentTools
import Agents
import AppKit
import Projects
import SessionKit
import Sidebar
import Terminal
import Themes
import UILooks

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
                                             project: Self.projectName(event.cwd ?? session?.cwd ?? ""),
                                             session: found.map { Self.conversationName($0.terminal) } ?? session?.name ?? "",
                                             account: session?.account.name ?? "", key: found.map { Self.key($0.terminal) }, reply: reply)
            cancel.onCancel = { attention.resolve(id) }
            if cancel.isCancelled { attention.resolve(id) }
        }
        attention.onAnswer = { [weak self] request, reply in self?.answer(request, reply) ?? false }
        // The questions' exact options (plan 26 D2): AskUserQuestion's PreToolUse goes to the app,
        // only that tool, never waiting (`cadex hook` gives the app 200 ms and answers nothing).
        if let tools = SessionKit.shared.toolsPath {
            let command = "'" + tools.replacingOccurrences(of: "'", with: "'\\''") + "' hook PreToolUse"
            SessionKit.shared.contribute("questions", SessionKitPart(settings: ["hooks": ["PreToolUse": [
                ["matcher": "AskUserQuestion", "hooks": [["type": "command", "command": command, "timeout": 5]]],
            ]]]))
        }
        _ = attention.watch { [weak self] in self?.showAttentionCount() }
    }

    /// Types the owner's answer in the agent's terminal (docs/adr/0036-owner-words-reach-the-agent.md):
    /// only if, right now, that terminal's agent still asks the same question; each key a moment
    /// after the one before, as the menu takes them (AgentAnswer). False: nothing was typed.
    func answer(_ request: AgentRequest, _ reply: AgentAnswer.Reply) -> Bool {
        guard let key = request.key, let terminal = terminal(key: key)?.terminal, Self.stillAsks(terminal, request.message),
              let keys = AgentAnswer.keys(reply, options: request.options.count) else { return false }
        for (step, text) in keys.enumerated() {
            // Checked again before every key: the agent may move on, or the owner type in the
            // tab, between two of them (review of 2026-11-17); then the rest is not sent.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.keyPause * Double(step)) { [weak terminal] in
                MainActor.assumeIsolated {
                    guard let terminal, Self.stillAsks(terminal, request.message) else { return }
                    terminal.session?.write(text)
                }
            }
        }
        return true
    }

    /// The terminal's agent is blocked on this very question (same report, word for word).
    static func stillAsks(_ terminal: TerminalView, _ message: String) -> Bool {
        guard let status = terminal.agentStatus else { return false }
        return status.state == .blocked && status.kind == .question && status.message == message
    }

    /// Between two keys of an answer: the menu opens its text field before the words arrive (the
    /// test of 2026-11-17 sent them seconds apart; a third of a second is ample for the TUI).
    static let keyPause: TimeInterval = 0.3

    /// Every terminal running an agent that reported, in every window.
    func gatherAgentReports() {
        var reports: [AgentReport] = []
        for window in sessions {
            for space in window.projects?.projects ?? [] {
                for terminal in space.tabs.allTerminals {
                    guard let status = terminal.agentStatus else { continue }
                    let pid = terminal.foregroundGroup
                    let session = AgentsController.shared.sessions.first { $0.pid == pid }
                    reports.append(AgentReport(key: Self.key(terminal), pid: pid,
                                               state: AgentReport.State(rawValue: "\(status.state)") ?? .idle,
                                               kind: AgentReport.Kind(rawValue: "\(status.kind)") ?? .none,
                                               message: status.message, finishedUnseen: terminal.agentFinishedUnseen,
                                               project: Self.projectName(terminal.currentDirectory ?? ""),
                                               session: Self.conversationName(terminal), account: session?.account.name ?? ""))
                }
            }
        }
        AgentAttention.shared.update(reports)
    }

    /// The bell's number in each window and the Dock's (agents.dockBadge).
    func showAttentionCount() {
        let count = AgentAttention.shared.unseen
        for window in sessions {
            window.workspace?.titleBar.setBell(count: count)
        }
        NSApp.dockTile.badgeLabel = settings.store.settings.agents.dockBadge && count > 0 ? "\(count)" : nil
    }

    /// A card's or a feed line's terminal, brought to the front: its window,
    /// space and tab. Unknown: the beep.
    func goToAgent(key: String?, pid: Int32) {
        guard let found = key.flatMap({ terminal(key: $0) }) ?? (pid > 0 ? terminal(pid: pid) : nil) else { return NSSound.beep() }
        NSApp.activate(ignoringOtherApps: true)
        found.window.window.makeKeyAndOrderFront(nil)
        found.window.projects?.select(found.space)
        found.window.tabs?.focus(found.terminal)
    }

    private func terminal(key: String) -> (window: WindowSession, space: Int, terminal: TerminalView)? {
        locate { Self.key($0) == key }
    }

    func terminal(pid: Int32) -> (window: WindowSession, space: Int, terminal: TerminalView)? {
        pid > 0 ? locate { $0.foregroundGroup == pid } : nil
    }

    func locate(_ match: (TerminalView) -> Bool) -> (window: WindowSession, space: Int, terminal: TerminalView)? {
        for window in sessions {
            for (index, space) in (window.projects?.projects ?? []).enumerated() {
                if let terminal = space.tabs.allTerminals.first(where: match) { return (window, index, terminal) }
            }
        }
        return nil
    }

    /// The project of a folder for the bell's cards: its main repository's name, also for a
    /// task's worktree (the worktree's own name read as the project, "cache-evict-3 · cache-evict-3").
    static func projectName(_ folder: String) -> String {
        guard !folder.isEmpty else { return "" }
        return (ProjectsFile.repositoryRoot(folder) as NSString).lastPathComponent
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
        page.onGoTo = { [weak self] key, pid in self?.app.goToAgent(key: key, pid: pid) }
        page.onEnable = { [weak self] in self?.settings.store.update { $0.agents.attention = true } }
        attentionPage = page
        return page
    }

    /// agents.show-attention and agents.show-feed: the bell's popover under the title bar's bell
    /// (plan 26 phase D; the sidebar page before), on Needs you or Activity; the same command
    /// again on what shows closes it, as a second click on the bell.
    func showAttention(_ subtab: String) {
        guard let workspace else { return }
        if bellPanel.isOpen, attentionPage?.subtab == subtab { return bellPanel.close() }
        let page = attentionPage ?? makeAttentionPage()
        page.subtab = subtab
        page.onRender = { [weak self] in self?.bellPanel.refit() }
        page.render()
        bellPanel.onClose = { [weak workspace] in workspace?.titleBar.setBellOpen(false) }
        bellPanel.show(page, below: workspace.titleBar.bellAnchor, width: UILooks.pt(DesignTokens.Popover.bellWidth))
        workspace.titleBar.setBellOpen(true)
    }
}
