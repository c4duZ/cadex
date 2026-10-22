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
    /// Sessions or Accounts: the same view on either list.
    func makeAgentsPage(_ list: String) -> AgentsView {
        let page = AgentsView()
        page.subtab = list
        page.isInCadex = { [weak self] session in self?.terminal(of: session) != nil }
        page.onOpen = { [weak self] session in self?.openAgent(session) }
        page.onOpenSubagent = { [weak self] session, agent in self?.openSubagent(agent, of: session) }
        page.onEnable = { [weak self] in self?.settings.store.update { $0.agents.sessions = true } }
        page.onHide = { [weak self] account, hide in self?.hideAccount(account, hide) }
        page.onLaunch = { [weak self] account in self?.launchAgent(for: account) }
        page.onRename = { [weak self] account in self?.renameAccount(account) }
        ThemeStore.shared.observe { [weak page, weak self] _ in
            page?.colors = Self.agentColors()
            self?.usageStrip?.colors = Self.agentColors()
        }
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

    /// Agent usage in the status bar: per account, the session's bar and
    /// "5h · wk"; reads only while the item shows.
    func makeUsageItem() -> StatusItem {
        let strip = AgentUsageStrip()
        strip.onClick = { [weak self] in _ = self?.commands.run("agents.show-accounts") }
        let item = StatusItem(id: "usage", title: T("Agent usage", "Uso dos agentes"),
                              subtitle: T("Each account's 5 h session and week, every 5 min", "A sessão de 5 h e a semana de cada conta, a cada 5 min"),
                              icon: .sparkle, side: .left, view: strip)
        var token: UUID?
        var sessions: UUID?
        item.onVisible = { [weak strip, weak self] visible in
            if visible {
                token = AgentUsageController.shared.watch { strip?.render() }
                // Whose agent the focused terminal runs: the sessions say.
                sessions = AgentsController.shared.watch { self?.showFocusedAccount() }
            } else {
                if let id = token { AgentUsageController.shared.stop(id) }
                if let id = sessions { AgentsController.shared.stop(id) }
                token = nil
                sessions = nil
            }
        }
        strip.colors = Self.agentColors()
        usageStrip = strip
        return item
    }

    /// The usage item shows the account of the agent in the focused
    /// terminal: a Claude Code session whose process group is the
    /// terminal's, or Codex by its program's name; none keeps the last.
    func showFocusedAccount() {
        guard let strip = usageStrip, strip.window != nil else { return }
        guard let terminal = tabs?.activeTerminal, terminal.foregroundGroup > 0 else { return strip.focused = nil }
        let group = terminal.foregroundGroup
        if let session = AgentsController.shared.sessions.first(where: { getpgid($0.pid) == group }) {
            return strip.focused = session.account.dir
        }
        var name = [CChar](repeating: 0, count: 64)
        proc_name(group, &name, UInt32(name.count))
        if String(cString: name) == "codex" { return strip.focused = NSHomeDirectory() + "/.codex" }
        strip.focused = nil
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

    /// A subagent's conversation in a tab, beside or new as files open; the
    /// same subagent again selects its tab (docs/spec/agents.md).
    func openSubagent(_ agent: AgentSubagent, of session: AgentSession) {
        guard let tabs else { return }
        let identity = AgentTranscriptDocument.identity(for: AgentTranscriptDocument.path(of: agent, in: session))
        if let existing = tabs.document(identity: identity) { return tabs.open(existing) }
        let document = AgentTranscriptDocument(session: session, agent: agent, colors: Self.agentColors())
        ThemeStore.shared.observe { [weak document] _ in document?.colors = Self.agentColors() }
        tabs.open(document, beside: settings.opensBeside)
    }

    /// "Rename…" on an account: its name in Agents, the usage item and the
    /// notifications; empty goes back to the organization's.
    func renameAccount(_ account: AgentAccount) {
        let alert = NSAlert()
        alert.messageText = T("Rename the account", "Renomear a conta")
        alert.informativeText = "~/" + (account.dir as NSString).lastPathComponent + T(". Empty: the organization's name.", ". Vazio: o nome da organização.")
        let field = NSTextField(string: account.name)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: T("Rename", "Renomear"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            let key = SettingsBridge.tilde(account.dir)
            self?.settings.store.update { $0.agents.accountNames[key] = name.isEmpty ? nil : name }
        }
    }

    /// The theme's colors for the Agents page and the usage item.
    static func agentColors() -> AgentColors {
        let ui = ThemeStore.shared.current.interface
        return AgentColors(text: ui.text.nsColor, secondary: ui.secondaryText.nsColor, accent: ui.accent.nsColor,
                           waiting: .systemBlue, fill: ui.tabActive.nsColor, panel: ui.panel.nsColor, border: ui.panelBorder.nsColor)
    }

    /// agents.test-notifications: the three kinds, named after this window's project.
    func sendTestNotifications() {
        let project = (folder.root as NSString).lastPathComponent
        let account = AgentsController.shared.accounts.first?.name ?? "Claude"
        AgentNotifier.shared.sendTest(project: project, account: account)
    }

    /// A double click: the agent's terminal, its space and tab in front;
    /// outside Cadex, its folder in the tree when it is in the workspace.
    /// In any window: the one holding the agent's terminal comes to the
    /// front, on that space and tab (the owner, 2026-10-21: two windows,
    /// a click in one goes to the other).
    func openAgent(_ session: AgentSession) {
        for window in app.sessions {
            guard let found = window.terminal(of: session), let spaces = window.spaces else { continue }
            NSApp.activate(ignoringOtherApps: true)
            window.window.makeKeyAndOrderFront(nil)
            spaces.select(found.space)
            window.tabs?.focus(found.terminal)
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
            NSApp.activate(ignoringOtherApps: true)
            self?.sessions.first?.openAgent(session)
        }
        // A hidden account whose login changed (a new login, a renewal by
        // use) comes back; a window's reset does not count.
        AgentUsageController.shared.onLoginChanged = { [weak self] dir in
            let key = SettingsBridge.tilde(dir)
            self?.settings.store.update { s in
                s.agents.hiddenAccounts.removeAll { $0 == key }
                s.agents.hiddenLogins[key] = nil
            }
        }
        notifier.start()
        // A test instance shows the three kinds without a click (2026-10-21).
        if ProcessInfo.processInfo.environment["CADEX_TEST_NOTIFICATIONS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.sessions.first?.sendTestNotifications() }
        }
    }
}
