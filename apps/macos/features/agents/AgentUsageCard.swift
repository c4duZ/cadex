import AppKit
import Strings
import UILooks

/// One account's usage as a block: logo, name and plan on one line, the
/// session's and the week's bars with when they reset. The card over the
/// usage item lists one per account, and so does Agents › Accounts: the
/// owner liked the card's look and asked the same for the tab (2026-10-21).
@MainActor
enum AgentUsageCard {
    /// Every account worth showing, one block each, in the card over the usage item.
    static func make(colors: AgentColors) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        let accounts = AgentUsageController.shared.visibleAccounts()
        if accounts.isEmpty {
            stack.addArrangedSubview(AgentText.label(T("No account in use on this Mac.", "Nenhuma conta em uso neste Mac."), size: 12, color: colors.secondary))
        }
        for account in accounts { stack.addArrangedSubview(block(account, colors: colors, width: UILooks.pt(272))) }
        stack.widthAnchor.constraint(equalToConstant: UILooks.pt(272)).isActive = true
        return stack
    }

    static func block(_ account: AgentAccount, colors: AgentColors, width: CGFloat?) -> NSView {
        let usage = AgentUsageController.shared
        let logo = NSImageView(image: account.logo.image(size: UILooks.pt(14)))
        logo.contentTintColor = colors.text
        logo.setContentHuggingPriority(.required, for: .horizontal)
        let name = AgentText.label(account.name, size: 12, weight: .semibold, color: colors.text)
        // "· Max · active": the active account is the one new sessions open in.
        let marks = [usage.plans[account.dir]?.capitalized, usage.activeAccount == account.dir ? T("active", "ativa") : nil].compactMap { $0 }
        let plan = AgentText.label(marks.map { "· " + $0 }.joined(separator: " "), size: 11, color: colors.secondary)
        plan.setContentCompressionResistancePriority(.required, for: .horizontal)
        let head = NSStackView(views: [logo, name, plan])
        head.spacing = 6
        var views: [NSView] = [head]
        switch usage.states[account.dir] ?? .loading {
        case .ready(let numbers, let at):
            let old = account.provider == .claude && Date().timeIntervalSince(at) > agentUsageOld
            views += AgentUsageRows.bars(numbers, colors: colors, dim: old)
            if account.provider == .codex {
                views.append(AgentText.label(T("as of ", "em ") + AgentResetTime.text(at), size: 11, color: colors.secondary))
            } else if old {
                views.append(AgentText.label(T("updated ", "atualizado há ") + AgentTime.short(since: at), size: 11, color: colors.secondary))
            }
        case .noUsage:
            views.append(AgentText.label(T("Open the agent from Cadex to see usage", "Abra o agente pelo Cadex para ver o uso"), size: 11, color: colors.secondary))
        case .expired:
            let note = NSTextField(wrappingLabelWithString: T("Login expired. Click to open claude with this account and renew it.",
                                                              "Login vencido. Clique para abrir o claude nesta conta e renovar."))
            note.font = UILooks.font(11)
            note.textColor = colors.secondary
            views.append(note)
        case .noLogin:
            views.append(AgentText.label(T("No login", "Sem login"), size: 11, color: colors.secondary))
        case .loading:
            views.append(AgentText.label(T("Reading…", "Lendo…"), size: 11, color: colors.secondary))
        }
        let part = NSStackView(views: views)
        part.orientation = .vertical
        part.alignment = .leading
        part.spacing = 4
        for view in views.dropFirst() {
            if let width { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
            else { view.widthAnchor.constraint(equalTo: part.widthAnchor).isActive = true }
        }
        head.widthAnchor.constraint(lessThanOrEqualTo: part.widthAnchor).isActive = true
        return part
    }
}
