import AppKit
import Strings
import UILooks

/// Every account of every provider, in the card over the usage item
/// (`HoverCard`, shared with the SSH item): logo, name, plan, the session's
/// and the week's bars with when they reset.
@MainActor
enum AgentUsageCard {
    static func make(colors: AgentColors) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        let usage = AgentUsageController.shared
        let accounts = usage.accounts()
        if accounts.isEmpty {
            stack.addArrangedSubview(AgentText.label(T("No account on this Mac.", "Nenhuma conta neste Mac."), size: 12, color: colors.secondary))
        }
        for account in accounts {
            let logo = NSImageView(image: account.logo.image(size: UILooks.pt(14)))
            logo.contentTintColor = colors.text
            let plan = usage.plans[account.dir].map { " · " + $0.capitalized } ?? ""
            let head = NSStackView(views: [logo, AgentText.label(account.name, size: 12, weight: .semibold, color: colors.text),
                                           AgentText.label(plan, size: 11, color: colors.secondary)])
            head.spacing = 6
            var views: [NSView] = [head]
            switch usage.states[account.dir] ?? .loading {
            case .ready(let numbers, let at):
                views += AgentUsageRows.bars(numbers, colors: colors, dim: false)
                if account.provider == .codex {
                    views.append(AgentText.label(T("as of ", "em ") + AgentResetTime.text(at), size: 11, color: colors.secondary))
                }
            case .failed(let numbers, _):
                if let numbers { views += AgentUsageRows.bars(numbers, colors: colors, dim: true) }
                views.append(AgentText.label(T("Could not read now", "Não deu para ler agora"), size: 11, color: colors.secondary))
            case .expired:
                views.append(AgentText.label(T("Login expired", "Login vencido"), size: 11, color: colors.secondary))
            case .noLogin:
                views.append(AgentText.label(T("No login", "Sem login"), size: 11, color: colors.secondary))
            case .loading:
                views.append(AgentText.label(T("Reading…", "Lendo…"), size: 11, color: colors.secondary))
            }
            let part = NSStackView(views: views)
            part.orientation = .vertical
            part.alignment = .leading
            part.spacing = 4
            for view in views.dropFirst() { view.widthAnchor.constraint(equalToConstant: UILooks.pt(272)).isActive = true }
            stack.addArrangedSubview(part)
        }
        stack.widthAnchor.constraint(equalToConstant: UILooks.pt(272)).isActive = true
        return stack
    }

}
