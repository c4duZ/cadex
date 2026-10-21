import CommandPalette
import Foundation
import Icons
import Strings

/// Opening an account's agent (docs/spec/agents.md, Accounts): the one
/// thing Cadex starts, at the owner's request (2026-10-21, ADR 0019). It is
/// a command typed in a terminal, like ssh.connect; Cadex never sends a
/// prompt, reads an answer or talks to a model.
public enum AgentLaunch {
    /// `claude` with the account's folder in CLAUDE_CONFIG_DIR (none for
    /// the default one), or `codex` with CODEX_HOME; the no-prompts flag when
    /// asked for.
    public static func command(for account: AgentAccount, skipPermissions: Bool) -> String {
        let quoted = "'" + account.dir.replacingOccurrences(of: "'", with: "'\\''") + "'"
        switch account.provider {
        case .claude:
            let env = account.isDefault ? "" : "CLAUDE_CONFIG_DIR=\(quoted) "
            return env + "claude" + (skipPermissions ? " --dangerously-skip-permissions" : "")
        case .codex:
            let env = account.isDefault ? "" : "CODEX_HOME=\(quoted) "
            return env + "codex" + (skipPermissions ? " --dangerously-bypass-approvals-and-sandbox" : "")
        }
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
