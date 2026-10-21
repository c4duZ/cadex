import Agents
import AppKit
import Customize
import Icons
import Settings
import Strings
import Themes

/// Hiding accounts, Customize › Accounts and opening an account's agent
/// (docs/spec/agents.md). Opening is the one thing Cadex starts, at the
/// owner's request (2026-10-21, ADR 0019): it types the agent's command in a
/// terminal, as ssh.connect types ssh; it never sends a prompt or reads an
/// answer.
extension WindowSession {
    /// Hide or show an account; a hidden one keeps its login of now, so it
    /// comes back when that login changes.
    func hideAccount(_ account: AgentAccount, _ hide: Bool) {
        let key = SettingsBridge.tilde(account.dir)
        Task { [weak self] in
            let login = hide ? await AgentUsageController.shared.fingerprint(account) : nil
            self?.settings.store.update { s in
                s.agents.hiddenAccounts.removeAll { $0 == key }
                s.agents.hiddenLogins[key] = login
                if hide { s.agents.hiddenAccounts.append(key) }
            }
        }
    }

    /// A click on an account: in the focused terminal when its shell is at
    /// the prompt, else in a new tab in that terminal's folder.
    func launchAgent(for account: AgentAccount) {
        guard let tabs else { return }
        let command = AgentLaunch.command(for: account, skipPermissions: settings.store.settings.agents.launchSkipPermissions)
        if let terminal = tabs.activeTerminal, !terminal.hasForegroundProcess {
            terminal.session?.write(command + "\n")
            tabs.focus(terminal)
            return
        }
        tabs.newTab(cwd: tabs.activeTerminal?.currentDirectory)
        tabs.activeTerminal?.session?.write(command + "\n")
    }

    /// Customize › Accounts: every account with a switch to show it, the
    /// state under its name, and how a click opens its agent.
    func accountsPage() -> CustomizePage {
        let hidden = AgentsController.shared.hidden
        let rows = AgentsController.shared.everyAccount().map { account -> CustomizeEntry in
            var row = CustomizeRow(id: account.dir, title: account.name, subtitle: Self.accountState(account), on: !hidden.contains(account.dir))
            row.logo = account.logo
            return .row(row)
        }
        let skip = settings.store.settings.agents.launchSkipPermissions
        let entries: [CustomizeEntry] = [.header(T("Accounts", "Contas"))] + rows + [
            .header(T("Opening an agent", "Abrir um agente")),
            .row(CustomizeRow(id: "launch.skipPermissions", icon: .lockKey, title: T("Without permission prompts", "Sem pedir permissões"),
                              subtitle: T("A click on an account opens claude --dangerously-skip-permissions (codex: --dangerously-bypass-approvals-and-sandbox)",
                                          "Um clique numa conta abre claude --dangerously-skip-permissions (codex: --dangerously-bypass-approvals-and-sandbox)"),
                              on: skip)),
        ]
        return CustomizePage(id: "accounts", title: T("Accounts", "Contas"), icon: .sparkle,
                             note: T("Shown accounts appear in Agents, the usage item and its card. One with no login, or out for over a day, stays out until it is used again; a hidden one comes back when its login changes.",
                                     "As contas que aparecem estão em Agents, no item de uso e no cartão dele. Uma sem login, ou vencida há mais de um dia, fica de fora até ser usada de novo; uma escondida volta quando o login dela muda."),
                             entries: entries) { [weak self] entries in
            guard let self else { return }
            let rows = entries.compactMap(\.row)
            for account in AgentsController.shared.everyAccount() {
                guard let row = rows.first(where: { $0.id == account.dir }) else { continue }
                if row.on == AgentsController.shared.hidden.contains(account.dir) { self.hideAccount(account, !row.on) }
            }
            if let flag = rows.first(where: { $0.id == "launch.skipPermissions" }), flag.on != self.settings.store.settings.agents.launchSkipPermissions {
                self.settings.store.update { $0.agents.launchSkipPermissions = flag.on }
            }
        }
    }

    /// "Team · 55% of the session", "No login", "Login out for 3 days".
    static func accountState(_ account: AgentAccount) -> String {
        let usage = AgentUsageController.shared
        let plan = usage.plans[account.dir].map { $0.capitalized + " · " } ?? ""
        switch usage.states[account.dir] {
        case .ready(let numbers, _), .failed(let numbers?, _):
            return plan + (numbers.session.map { T("\(Int($0.percent.rounded()))% of the session", "\(Int($0.percent.rounded()))% da sessão") } ?? "")
        case .expired:
            let since = usage.expiredSince[account.dir].map { " " + AgentResetTime.relative($0) } ?? ""
            return T("Login out", "Login vencido") + since
        case .noLogin: return T("No login", "Sem login")
        default: return plan.isEmpty ? T("Not read yet", "Ainda não lido") : String(plan.dropLast(3))
        }
    }
}
