import Agents
import AppKit
import SessionKit
import Strings
import Themes

/// Agents › History in this window (docs/spec/agents.md, Histórico; plan 18
/// phase D): the page, its commands, and what each one does with a
/// conversation. Resuming types the command in a tab; Cadex sends no prompt
/// (docs/adr/0021-cadex-managed-accounts.md).
extension WindowSession {
    func makeHistoryPage() -> AgentHistoryView {
        let page = AgentHistoryView()
        page.colors = Self.agentColors()
        page.project = { [weak self] in self?.projectRoot ?? "" }
        page.accountName = Self.accountName
        let actions = historyActions()
        page.onResume = actions.resume
        page.onContinue = actions.continueIn
        page.onCopyCommand = actions.copyCommand
        page.onReveal = actions.reveal
        page.onOpenFolder = { [weak self] entry in self?.openHistoryFolder(entry) }
        page.onEnable = { [weak self] in self?.settings.store.update { $0.agents.history = true } }
        ThemeStore.shared.observe { [weak page] _ in page?.colors = Self.agentColors() }
        return page
    }

    func historyActions() -> AgentHistoryActions {
        AgentHistoryActions(
            resume: { [weak self] entry in self?.typeInNewTab(AgentHistoryLaunch.resume(entry), cwd: AgentHistoryLaunch.folder(entry)) },
            continueIn: { [weak self] entry in self?.chooseAccountToContinue(entry) },
            copyCommand: { entry in
                let command = "cd " + SessionKit.quote(AgentHistoryLaunch.folder(entry)) + " && " + AgentHistoryLaunch.resume(entry)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            },
            reveal: { entry in NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) })
    }

    /// An account's name as Agents shows it, by folder.
    static func accountName(_ dir: String) -> String {
        AgentsController.shared.everyAccount().first { $0.dir == dir }?.name ?? (dir as NSString).lastPathComponent
    }

    /// "Continue in another account": the other Claude accounts in use; the
    /// chosen one gets the conversation copied by --fork-session, the
    /// original untouched (test of 2026-11-14).
    private func chooseAccountToContinue(_ entry: AgentHistoryEntry) {
        let others = AgentUsageController.shared.visibleAccounts().filter { $0.provider == .claude && $0.dir != entry.account }
        guard !others.isEmpty, let palette else { return NSSound.beep() }
        AgentAccountPicker.open(palette: palette, accounts: others, placeholder: T("The account that continues \"\(entry.title)\"",
                                                                                  "A conta que continua \"\(entry.title)\"")) { [weak self] account in
            self?.typeInNewTab(AgentHistoryLaunch.continueIn(entry, account: account), cwd: AgentHistoryLaunch.folder(entry))
        }
    }

    /// "Continue in…" (plan 22 phase E): a new tab in the window's project
    /// with `cadex continue <agent>` in the chosen account. Needs `cadex`
    /// and the memory on (the launcher is the memory's).
    func continueInAgent(_ account: AgentAccount?) {
        guard settings.store.settings.memory.enabled, let tools = SessionKit.shared.toolsPath else { return NSSound.beep() }
        typeInNewTab(AgentLaunch.continueCommand(for: account, tools: tools), cwd: projectRoot ?? NSHomeDirectory())
    }

    /// A new tab in `cwd` with `command` typed and run.
    func typeInNewTab(_ command: String, cwd: String) {
        guard let tabs else { return }
        tabs.newTab(cwd: cwd)
        tabs.activeTerminal?.session?.write(command + "\n")
    }

    /// The conversation's folder becomes this window's workspace.
    private func openHistoryFolder(_ entry: AgentHistoryEntry) {
        guard FileManager.default.fileExists(atPath: entry.cwd) else { return NSSound.beep() }
        folder.open(entry.cwd)
    }
}
