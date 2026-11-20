import AppKit
import Agents
import Darwin
import Menus
import SessionKit
import Strings
import Tabs
import Terminal

/// Switching an agent's account in one click (plan 33 E; docs/spec/agents.md, Trocar de conta):
/// the Claude in the pane ends (SIGTERM, as hibernating) and, once the shell is back, the same pane
/// goes on in the other account: by default with the same conversation (its file resumed there and
/// forked, the owner, 2026-11-20); or, chosen in ⌘K, "Continue in…", a new conversation with the
/// memory's briefing. Without the conversation's file or the memory, the other account's agent
/// opens plainly. Four
/// ways in: the account in the pane's header, the notice when the account hits its limit, a click
/// on an account in the usage card with a Claude focused, and agents.switch-account in ⌘K.
extension WindowSession {
    func startAccountSwitch() {
        TabsController.paneAccountMenu = { [weak self] terminal in self?.accountMenu(for: terminal) ?? [] }
    }

    /// The Claude in `terminal` goes on in `account`; a terminal with no program types it at once.
    func switchAccount(_ terminal: TerminalView, to account: AgentAccount, carry: AgentSwitch.Carry = .conversation) {
        let command: String
        if carry == .conversation, let carried = carryConversation(terminal, to: account) {
            command = carried
        } else if settings.store.settings.memory.enabled, let tools = SessionKit.shared.toolsPath {
            command = AgentLaunch.continueCommand(for: account, tools: tools)
        } else {
            command = AgentLaunch.command(for: account, skipPermissions: settings.store.settings.agents.launchSkipPermissions,
                                          cwd: terminal.currentDirectory)
        }
        terminal.footCard = nil
        let group = terminal.foregroundGroup
        if group > 0 { kill(group, SIGTERM) }
        whenShellIsBack(terminal, tries: 50) { [weak self] in
            terminal.session?.write(command + "\n")
            self?.tabs?.focus(terminal)
        }
    }

    /// The usage card's click and agents.switch-account: with a Claude focused in another account,
    /// it goes on there; else the account's agent opens as before (launchAgent).
    func switchOrLaunch(_ account: AgentAccount, carry: AgentSwitch.Carry = .conversation) {
        if let terminal = tabs?.activeTerminal, let current = claudeAccount(in: terminal), current.dir != account.dir {
            return switchAccount(terminal, to: account, carry: carry)
        }
        launchAgent(for: account)
    }

    /// The command that resumes the pane's conversation in `account`: its file in the account it
    /// runs in now (the conversation the hooks reported, agentResume), by path with --fork-session.
    /// Nil with no conversation known or no file yet (a session with no message).
    private func carryConversation(_ terminal: TerminalView, to account: AgentAccount) -> String? {
        guard let resume = terminal.agentResume, let from = claudeAccount(in: terminal) else { return nil }
        let transcript = AgentProjectFolder.path(for: resume.folder, in: from) + "/" + resume.sessionID + ".jsonl"
        guard FileManager.default.fileExists(atPath: transcript) else { return nil }
        return AgentHibernation.carryCommand(transcript: transcript, folder: resume.folder, configDir: account.isDefault ? nil : account.dir,
                                             kitSession: resume.kitSession, skipPermissions: settings.store.settings.agents.launchSkipPermissions)
    }

    /// The account of the Claude running in `terminal`, by its live session.
    func claudeAccount(in terminal: TerminalView) -> AgentAccount? {
        guard terminal.agentStatus != nil else { return nil }
        return AgentsController.shared.sessions.first { self.terminal(of: $0)?.terminal === terminal && $0.account.provider == .claude }?.account
    }

    /// The title bar's account (shownAccountDir, the same as the status bar's usage item), with how
    /// much of its limit it used.
    func refreshTitleAccount() {
        let dir = shownAccountDir()
        let account = AgentsController.shared.everyAccount().first { $0.dir == dir }
        workspace?.titleBar.setAccount(name: account?.name, used: account.flatMap { AgentSwitch.used(AgentUsage.current(of: $0)) },
                                       provider: account?.provider == .codex ? .codex : .claude)
    }

    /// The header's list: every Claude account with its usage, the pane's own marked and inert.
    private func accountMenu(for terminal: TerminalView) -> [MenuEntry] {
        let current = claudeAccount(in: terminal)?.dir
        return AgentUsageController.shared.visibleAccounts().filter { $0.provider == .claude }.map { account in
            let used = AgentSwitch.usedText(AgentSwitch.used(AgentUsage.current(of: account)))
            let title = [account.name, account.dir == current ? T("this session", "esta sessão") : used].filter { !$0.isEmpty }.joined(separator: " · ")
            return MenuEntry(title, icon: .gauge, isEnabled: account.dir != current) { [weak self, weak terminal] in
                guard let terminal else { return }
                self?.switchAccount(terminal, to: account)
            }
        }
    }

    /// The notice at the foot of each Claude whose account hit its limit, offering the account with
    /// the most room; it goes when the numbers drop or the owner says "Not now" (until the pair
    /// changes). Run with the headers' refresh: on every agent change and once a minute.
    func refreshLimitCards() {
        guard let projects else { return }
        let accounts = AgentUsageController.shared.visibleAccounts()
        for terminal in projects.projects.flatMap(\.tabs.allTerminals) {
            let shown = terminal.footCard as? AgentLimitCard
            guard let account = claudeAccount(in: terminal), AgentSwitch.atLimit(AgentUsage.current(of: account)),
                  let next = AgentSwitch.roomiest(accounts, except: account.dir, usage: AgentUsage.current) else {
                if shown != nil { terminal.footCard = nil }
                continue
            }
            let key = account.name + "→" + next.account.name
            let id = key + "@\(ObjectIdentifier(terminal))"
            guard shown?.key != key, !LimitNotices.dismissed.contains(id) else { continue }
            terminal.footCard = AgentLimitCard(account: account.name, next: next.account.name, used: next.used,
                                               go: { [weak self, weak terminal] in
                                                   guard let terminal else { return }
                                                   self?.switchAccount(terminal, to: next.account)
                                               },
                                               close: { [weak terminal] in
                                                   LimitNotices.dismissed.insert(id)
                                                   terminal?.footCard = nil
                                               })
        }
    }

    /// Runs `then` once the terminal's shell is back in front (the agent exited), looking every
    /// 0.2 s; after `tries` it gives up with a beep (the agent did not stop).
    private func whenShellIsBack(_ terminal: TerminalView, tries: Int, then: @escaping @MainActor () -> Void) {
        guard terminal.hasForegroundProcess else { return then() }
        guard tries > 0 else { return NSSound.beep() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            MainActor.assumeIsolated { self?.whenShellIsBack(terminal, tries: tries - 1, then: then) }
        }
    }
}

/// The notices the owner dismissed ("Not now"), by account pair and terminal, for this run.
@MainActor
enum LimitNotices {
    static var dismissed: Set<String> = []
}
