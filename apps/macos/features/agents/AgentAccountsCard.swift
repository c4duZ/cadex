import AppKit
import Menus
import Strings
import UILooks

/// The accounts card (the cards' proposal the owner approved on 2026-11-18, "Agent usage"; the
/// new frame's Anatomy, "Usage: a chip, not a page"), over the status bar's usage item and the top
/// bar's account: "Accounts · 2 Claude", then each account with its plan, the session's percent and
/// when it resets, the bar (amber from 80%, as the chip) and "84% of the 5-hour window · 61% of the
/// week"; at the foot Open an agent on…, Add account and Accounts settings, each a command. Built
/// on StatusCard like every other card. The card of before (AgentUsageCard, one block per account
/// with two bars) stayed on the top bar after 2026-11-20 and the owner asked for this one.
@MainActor
public enum AgentAccountsCard {
    /// The amber from here, as the usage chip (AgentUsageStrip).
    static let warnAt = 80.0

    /// `launch`: a click on an account (its agent opens, or the focused Claude goes on there);
    /// `run`: a foot action's command id.
    public static func make(launch: @escaping (AgentAccount) -> Void, run: @escaping (String) -> Void, close: @escaping () -> Void) -> NSView {
        StatusCard.build(blocks(AgentUsageController.shared.visibleAccounts(), launch: launch, run: run), close: close)
    }

    static func blocks(_ accounts: [AgentAccount], launch: @escaping (AgentAccount) -> Void, run: @escaping (String) -> Void) -> [StatusCard.Block] {
        var blocks: [StatusCard.Block] = [.header(T("Accounts", "Contas"), detail: count(accounts))]
        if accounts.isEmpty { blocks.append(.note(T("No account in use on this Mac.", "Nenhuma conta em uso neste Mac."))) }
        for account in accounts { blocks += self.account(account, launch: launch) }
        blocks.append(.actions([
            StatusCard.Action(T("Open an agent on…", "Abrir um agente em…")) { run("agents.open-account") },
            StatusCard.Action(T("Add account", "Adicionar conta")) { run("agents.add-account") },
            StatusCard.Action(T("Accounts settings", "Configurar contas")) { run("settings.open-agents") },
        ]))
        return blocks
    }

    /// "2 Claude · 1 Codex".
    static func count(_ accounts: [AgentAccount]) -> String? {
        let claude = accounts.filter { $0.provider == .claude }.count, codex = accounts.count - claude
        let parts = [claude > 0 ? "\(claude) Claude" : nil, codex > 0 ? "\(codex) Codex" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func account(_ account: AgentAccount, launch: @escaping (AgentAccount) -> Void) -> [StatusCard.Block] {
        let usage = AgentUsageController.shared
        let name = (account.provider == .codex ? "Codex · " : "") + account.name
        let marks = [usage.plans[account.dir]?.capitalized, usage.activeAccount == account.dir ? T("active", "ativa") : nil].compactMap { $0 }
        let detail = marks.isEmpty ? nil : marks.joined(separator: " · ")
        let row = { (value: String?, warn: Bool) in StatusCard.Row(name, detail: detail, value: value, warn: warn) { launch(account) } }
        switch usage.states[account.dir] ?? .loading {
        case .ready(let numbers, let at):
            let session = numbers.session?.percent ?? 0
            let warn = session >= warnAt
            let color = warn ? DesignTokens.Color.stateNeeds : DesignTokens.Color.stateWorking
            var blocks: [StatusCard.Block] = [.rows([row(value(numbers), warn)]), .bar([(session / 100, color)])]
            if let line = windows(numbers) { blocks.append(.note(line)) }
            if account.provider == .claude, Date().timeIntervalSince(at) > agentUsageOld {
                blocks.append(.note(T("updated ", "atualizado há ") + AgentTime.short(since: at)))
            }
            return blocks
        case .noUsage:
            return [.rows([row("—", false)]), .note(T("Open the agent from Cadex to see usage", "Abra o agente pelo Cadex para ver o uso"))]
        case .expired:
            return [.rows([row("—", true)]), .note(T("Login expired. Click to open claude with this account and renew it.",
                                                     "Login vencido. Clique para abrir o claude nesta conta e renovar."), warn: true)]
        case .noLogin:
            return [.rows([row("—", false)]), .note(T("No login", "Sem login"))]
        case .loading:
            return [.rows([row(nil, false)]), .note(T("Reading…", "Lendo…"))]
        }
    }

    /// "84% · resets 21:10" (the session's window).
    static func value(_ numbers: AgentUsage) -> String {
        guard let session = numbers.session else { return "—" }
        let resets = session.resets.map { T(" · resets ", " · reinicia ") + AgentResetTime.text($0) } ?? ""
        return "\(Int(session.percent.rounded()))%" + resets
    }

    /// "84% of the 5-hour window · 61% of the week".
    static func windows(_ numbers: AgentUsage) -> String? {
        let parts = [numbers.session.map { "\(Int($0.percent.rounded()))%" + T(" of the 5-hour window", " da janela de 5 horas") },
                     numbers.week.map { "\(Int($0.percent.rounded()))%" + T(" of the week", " da semana") }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
