import AppKit
import Icons
import Menus
import Strings
import UILooks

/// Agents › Accounts (docs/spec/agents.md, Accounts): the same blocks as
/// the card over the usage item, one per account in use, spaced as in the
/// card and with no line between them (the owner found the lines and the
/// tight rows crude, 2026-10-21).
/// An account with no login, or one expired for more than a day, is left
/// out; hidden ones are shown again from Customize › Accounts. A click
/// opens that account's agent in the focused terminal; the right click
/// renames or hides it.
extension AgentsView {
    func renderAccounts() {
        let accounts = usage.visibleAccounts()
        if accounts.isEmpty {
            return note(T("No account in use on this Mac. Hidden and unused ones are in Customize › Accounts.",
                          "Nenhuma conta em uso neste Mac. As escondidas e sem uso estão em Personalizar › Contas."))
        }
        let list = NSStackView(views: accounts.map(block))
        list.orientation = .vertical
        list.alignment = .leading
        // Each row pads its block by 5 pt above and below, so 2 pt between
        // rows leaves the card's 12 pt between blocks (AgentUsageCard.make).
        list.spacing = 2
        for row in list.arrangedSubviews { row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        add(list)
    }

    private func block(_ account: AgentAccount) -> NSView {
        let row = AgentRow(AgentUsageCard.block(account, colors: colors, width: nil), inset: 8)
        row.toolTip = "~/" + (account.dir as NSString).lastPathComponent + "\n" + T("Click: open its agent in the terminal", "Clique: abrir o agente dela no terminal")
        row.hoverFill = colors.fill.withAlphaComponent(0.5)
        row.onClick = { [weak self] in self?.onLaunch?(account) }
        row.onRightClick = { [weak self, weak row] in
            guard let self, let row else { return }
            PopupMenu.show(self.accountMenu(account), below: row)
        }
        return row
    }

    func accountMenu(_ account: AgentAccount) -> [MenuEntry] {
        [MenuEntry(T("Open Its Agent", "Abrir o agente dela"), icon: .terminalWindow) { [weak self] in self?.onLaunch?(account) },
         MenuEntry(T("Rename…", "Renomear…"), icon: .pencilSimple) { [weak self] in self?.onRename?(account) },
         MenuEntry(T("Hide", "Esconder"), icon: .x) { [weak self] in self?.onHide?(account, true) }]
    }
}
