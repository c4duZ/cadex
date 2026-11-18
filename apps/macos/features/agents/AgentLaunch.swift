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
    /// with CODEX_HOME; the no-prompts flag when asked for. `cwd`: the
    /// folder it opens in, when known (the memory's folder per project).
    @MainActor
    public static func command(for account: AgentAccount, skipPermissions: Bool, cwd: String? = nil, kit: SessionKit = .shared,
                               defaultClaudeJSON: String = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude.json") -> String {
        let quoted = "'" + account.dir.replacingOccurrences(of: "'", with: "'\\''") + "'"
        switch account.provider {
        case .claude:
            return kit.claudeCommand(configDir: account.isDefault ? nil : account.dir,
                                     arguments: skipPermissions ? ["--dangerously-skip-permissions"] : [], cwd: cwd,
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

    /// "Continue in…" (plan 22 phase E): `cadex continue <agent>` in the
    /// account, the agent in the project's memory workstream (ai-memory's
    /// `run`): the same native session when the agent ran it last, else a
    /// new one with the other agent's conversation as a read-only dossier.
    /// The tab's zsh runs it; `cadex` asks the app for the kit.
    /// With no account, `cadex continue` alone: the launcher continues the
    /// newest session of the project, in whichever agent ran it.
    public static func continueCommand(for account: AgentAccount?, tools: String) -> String {
        let cadex = "'" + tools.replacingOccurrences(of: "'", with: "'\\''") + "'"
        guard let account else { return cadex + " continue" }
        let quoted = "'" + account.dir.replacingOccurrences(of: "'", with: "'\\''") + "'"
        switch account.provider {
        // The default account has no folder to name (~/.claude by its absence): the mark says it was
        // chosen, so `cadex continue` does not take the project's or the active one (plan 33 F).
        case .claude: return (account.isDefault ? "CADEX_ACCOUNT_CHOSEN=1 " : "CLAUDE_CONFIG_DIR=\(quoted) ") + cadex + " continue claude"
        case .codex: return (account.isDefault ? "" : "CODEX_HOME=\(quoted) ") + cadex + " continue codex"
        }
    }

    /// agents.open-account (the accounts in ⌘K), agents.continue-in-agent and
    /// agents.customize-accounts.
    @MainActor
    public static func commands(palette: CommandPaletteController, launch: @escaping @MainActor (AgentAccount) -> Void,
                                continueIn: @escaping @MainActor (AgentAccount?) -> Void,
                                customize: @escaping @MainActor () -> Void) -> [Command] {
        [
            Command(id: "agents.open-account", title: T("Open an Account's Agent", "Abrir o agente de uma conta"),
                    keywords: ["claude", "codex", "agent", "account", "agente", "conta", "abrir"], category: .terminal,
                    // The Agent card of the home screen (plan 29; the Home mockup).
                    defaultShortcut: "cmd+shift+a",
                    action: .run { palette.open(AccountSource(launch: launch)) }),
            Command(id: "agents.continue-in-agent", title: T("Continue in…", "Continuar em…"),
                    keywords: ["continue", "workstream", "handoff", "claude", "codex", "memory", "continuar", "memória"], category: .terminal,
                    action: .run { palette.open(AccountSource(launch: { continueIn($0) }, automatic: { continueIn(nil) }, placeholder: T("The agent and account that continue this project's work",
                                                                                                  "O agente e a conta que continuam o trabalho deste projeto"))) }),
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
    /// "Continue in…" only: a first item for the agent that worked last.
    private let automatic: (() -> Void)?
    let placeholder: String
    private static let automaticID = "\u{0}automatic"

    init(launch: @escaping (AgentAccount) -> Void, automatic: (() -> Void)? = nil,
         placeholder: String = T("Open the agent of an account", "Abrir o agente de uma conta")) {
        self.launch = launch
        self.automatic = automatic
        self.placeholder = placeholder
    }

    var emptyText: String { T("No such account", "Nenhuma conta assim") }
    var icon: Icon { .sparkle }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let accounts = AgentUsageController.shared.visibleAccounts()
        var items = accounts.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.map { account in
            PaletteItem(id: account.dir, title: account.name, detail: account.provider == .codex ? "codex" : "claude", icon: .terminalWindow)
        }
        let lastTitle = T("The agent that worked here last", "O último agente que trabalhou aqui")
        if automatic != nil, query.isEmpty || lastTitle.localizedCaseInsensitiveContains(query) {
            items.insert(PaletteItem(id: Self.automaticID, title: lastTitle, detail: T("its newest session", "a sessão mais nova dele"),
                                     icon: .clockCounterClockwise), at: 0)
        }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) {
        if item.id == Self.automaticID { automatic?(); return }
        guard let account = AgentUsageController.shared.visibleAccounts().first(where: { $0.dir == item.id }) else { return }
        launch(account)
    }

    func stop() {}
}
