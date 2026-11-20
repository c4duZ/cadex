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
            // Short, on one line: the proposal's three long ones wrapped to two (2026-11-20).
            StatusCard.Action(T("Open agent…", "Abrir agente…")) { run("agents.open-account") },
            StatusCard.Action(T("Add account", "Adicionar conta")) { run("agents.add-account") },
            StatusCard.Action(T("Settings", "Configurar")) { run("settings.open-agents") },
        ]))
        return blocks
    }

    /// "2 Claude · 1 Codex".
    static func count(_ accounts: [AgentAccount]) -> String? {
        let claude = accounts.filter { $0.provider == .claude }.count, codex = accounts.count - claude
        let parts = [claude > 0 ? "\(claude) Claude" : nil, codex > 0 ? "\(codex) Codex" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// One block per account: "bkdg  Max · active        84%", the session's bar, and one short
    /// line, "resets 8:00 PM · week 61%". Four lines at three insets read as clutter (the owner,
    /// 2026-11-20); an account with nothing read is its name and what to do.
    private static func account(_ account: AgentAccount, launch: @escaping (AgentAccount) -> Void) -> [StatusCard.Block] {
        let usage = AgentUsageController.shared
        let name = (account.provider == .codex ? "Codex · " : "") + account.name
        let marks = [usage.plans[account.dir]?.capitalized, usage.activeAccount == account.dir ? T("active", "ativa") : nil].compactMap { $0 }
        let detail = marks.isEmpty ? nil : marks.joined(separator: " · ")
        let row = { (value: String?, warn: Bool) in StatusCard.Row(name, detail: detail, value: value, warn: warn) { launch(account) } }
        let quiet = DesignTokens.Color.stateWorking
        switch usage.states[account.dir] ?? .loading {
        case .ready(let numbers, let at):
            let session = numbers.session?.percent ?? 0
            let warn = session >= warnAt
            var caption = [numbers.session?.resets.map { T("resets ", "reinicia ") + AgentResetTime.text($0) },
                           numbers.week.map { T("week ", "semana ") + "\(Int($0.percent.rounded()))%" }].compactMap { $0 }
            if account.provider == .claude, Date().timeIntervalSince(at) > agentUsageOld {
                caption.append(T("read ", "lido há ") + AgentTime.short(since: at) + T(" ago", ""))
            }
            return [.meter(row(numbers.session.map { "\(Int($0.percent.rounded()))%" } ?? "—", warn), bar: session / 100,
                           color: warn ? DesignTokens.Color.stateNeeds : quiet, caption: caption.isEmpty ? nil : caption.joined(separator: " · "))]
        case .noUsage:
            return [.meter(row(nil, false), bar: nil, color: quiet, caption: T("No usage yet: open its agent here", "Sem uso ainda: abra o agente dela aqui"))]
        case .expired:
            return [.meter(row(nil, true), bar: nil, color: quiet, caption: T("Login expired: click to renew", "Login vencido: clique para renovar"), captionWarn: true)]
        case .noLogin:
            return [.meter(row(nil, false), bar: nil, color: quiet, caption: T("No login", "Sem login"))]
        case .loading:
            return [.meter(row(nil, false), bar: nil, color: quiet, caption: T("Reading…", "Lendo…"))]
        }
    }
}
