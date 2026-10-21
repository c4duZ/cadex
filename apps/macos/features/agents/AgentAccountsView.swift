import AppKit
import Icons
import Menus
import Strings
import UILooks

/// Agents › Accounts (docs/spec/agents.md, Accounts): a card per Claude
/// Code account on this Mac, named by its organization or as renamed; the
/// right click renames or hides it. Hidden ones stay at the end, dimmed,
/// with "Show", so none is lost.
extension AgentsView {
    func renderAccounts() {
        let accounts = controllerAccounts
        if accounts.all.isEmpty {
            return note(T("No Claude Code account on this Mac.", "Nenhuma conta do Claude Code neste Mac."))
        }
        for account in accounts.shown { add(paddedTop(card(account, hidden: false))) }
        if !accounts.hidden.isEmpty {
            add(paddedTop(AgentText.label(T("HIDDEN", "ESCONDIDAS"), size: 11, weight: .semibold, color: colors.secondary)))
            for account in accounts.hidden { add(paddedTop(card(account, hidden: true))) }
        }
    }

    private func card(_ account: AgentAccount, hidden: Bool) -> NSView {
        let title = AgentText.label(account.name, size: 13, weight: .semibold, color: hidden ? colors.secondary : colors.text)
        let logo = NSImageView(image: account.logo.image(size: UILooks.pt(15)))
        logo.contentTintColor = hidden ? colors.secondary : colors.text
        logo.setContentHuggingPriority(.required, for: .horizontal)
        let name = NSStackView(views: [logo, title])
        name.spacing = 6
        let folder = AgentText.label("~/" + (account.dir as NSString).lastPathComponent, size: 11, color: colors.secondary)
        var lines: [NSView] = [name, folder]
        // A hidden account is not read: nothing about its usage.
        if !hidden { lines += usageLines(account) }
        let stack = NSStackView(views: lines)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        let row = AgentRow(stack, inset: 10)
        row.fill = colors.fill.withAlphaComponent(hidden ? 0.4 : 1)
        row.layer?.cornerRadius = 9
        row.toolTip = account.dir
        row.onRightClick = { [weak self, weak row] in
            guard let self, let row else { return }
            PopupMenu.show(self.accountMenu(account, hidden: hidden), below: row)
        }
        return row
    }

    func accountMenu(_ account: AgentAccount, hidden: Bool) -> [MenuEntry] {
        [MenuEntry(T("Rename…", "Renomear…"), icon: .pencilSimple) { [weak self] in self?.onRename?(account) },
         hidden ? MenuEntry(T("Show", "Mostrar"), icon: .eye) { [weak self] in self?.onHide?(account, false) }
                : MenuEntry(T("Hide", "Esconder"), icon: .x) { [weak self] in self?.onHide?(account, true) }]
    }
}
