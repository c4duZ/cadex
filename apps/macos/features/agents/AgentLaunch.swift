import CommandPalette
import Foundation
import Icons
import SessionKit
import Strings

/// Opening an account's agent (docs/spec/agents.md, Accounts): what Cadex
/// starts, at the owner's request (2026-10-21, ADR 0019, widened by ADR
/// 0021). It is a command typed in a terminal, like ssh.connect; Cadex
/// never sends a prompt, reads an answer or talks to a model.
public enum AgentLaunch {
    /// `claude` in the account (CLAUDE_CONFIG_DIR, none for the default one)
    /// with the session kit (`--settings` with Cadex's status line, which
    /// tells the usage without a token; the environment cleaned), or `codex`
    /// with CODEX_HOME; the no-prompts flag when asked for.
    @MainActor
    public static func command(for account: AgentAccount, skipPermissions: Bool, kit: SessionKit = .shared,
                               defaultClaudeJSON: String = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude.json") -> String {
        let quoted = "'" + account.dir.replacingOccurrences(of: "'", with: "'\\''") + "'"
        switch account.provider {
        case .claude:
            return kit.claudeCommand(configDir: account.isDefault ? nil : account.dir,
                                     arguments: skipPermissions ? ["--dangerously-skip-permissions"] : [],
                                     defaultClaudeJSON: defaultClaudeJSON)
        case .codex:
            let env = account.isDefault ? "" : "CODEX_HOME=\(quoted) "
            return env + "codex" + (skipPermissions ? " --dangerously-bypass-approvals-and-sandbox" : "")
        }
    }

    /// `claude attach <job>` for a background session, with its account's
    /// folder: the session's own screen, where a permission or question is
    /// answered (test loop, 2026-11-14). Typed like the command above.
    public static func attachCommand(job: String, account: AgentAccount) -> String {
        let quoted = "'" + account.dir.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let safeJob = job.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return (account.isDefault ? "" : "CLAUDE_CONFIG_DIR=\(quoted) ") + "claude attach " + safeJob
    }

    /// agents.open-account (the accounts in ⌘K) and agents.customize-accounts.
    @MainActor
    public static func commands(palette: CommandPaletteController, launch: @escaping @MainActor (AgentAccount) -> Void,
                                customize: @escaping @MainActor () -> Void) -> [Command] {
        [
            Command(id: "agents.open-account", title: T("Open an Account's Agent", "Abrir o agente de uma conta"),
                    keywords: ["claude", "codex", "agent", "account", "agente", "conta", "abrir"], category: .terminal,
                    action: .run { palette.open(AccountSource(launch: launch)) }),
            Command(id: "agents.customize-accounts", title: T("Customize Accounts", "Personalizar as contas"),
                    keywords: ["accounts", "hide", "show", "contas", "esconder", "mostrar"], category: .view,
                    action: .run { customize() }),
        ]
    }
}

/// ⌘K's list of the accounts in use; choosing one opens its agent.
@MainActor
final class AccountSource: PaletteSource {
    private let launch: (AgentAccount) -> Void

    init(launch: @escaping (AgentAccount) -> Void) { self.launch = launch }

    var placeholder: String { T("Open the agent of an account", "Abrir o agente de uma conta") }
    var emptyText: String { T("No such account", "Nenhuma conta assim") }
    var icon: Icon { .sparkle }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let accounts = AgentUsageController.shared.visibleAccounts()
        let items = accounts.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.map { account in
            PaletteItem(id: account.dir, title: account.name, detail: account.provider == .codex ? "codex" : "claude", icon: .terminalWindow)
        }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) {
        guard let account = AgentUsageController.shared.visibleAccounts().first(where: { $0.dir == item.id }) else { return }
        launch(account)
    }

    func stop() {}
}
