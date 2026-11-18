import Agents
import AppKit
import SessionKit
import Settings
import Strings

/// Managed accounts and the shared configuration in this window
/// (docs/spec/agents.md, Contas gerenciadas; plan 18 phase C). The folders'
/// work is the agents feature's; here are the questions, the confirmations,
/// the login tab and the settings. Never a token: the login is Claude
/// Code's own /login, in a tab (docs/adr/0021-cadex-managed-accounts.md).
extension WindowSession {
    func accountActions() -> AgentAccountActions {
        var actions = AgentAccountActions(
            add: { [weak self] in self?.addAccount() },
            setActive: { [weak self] account in self?.setActiveAccount(account) },
            sync: { [weak self] in self?.syncAccountConfig() },
            share: { [weak self] account in self?.shareAccountConfig(account) },
            ownCopy: { [weak self] dir, item in self?.accountChange { try AgentConfigShare.ownCopy(item, account: dir, source: Self.claudeSource) } },
            follow: { [weak self] dir, item in
                self?.accountChange { try AgentConfigShare.follow(item, account: dir, source: Self.claudeSource, trash: AgentManagedAccounts.moveToTrash) }
            },
            remove: { [weak self] dir in self?.removeAccount(dir) },
            setProject: { [weak self] account in self?.setProjectAccount(account) },
            projectAccount: { [weak self] in
                guard let self else { return nil }
                return self.settings.store.settings.agents.projectAccounts[SettingsBridge.tilde(self.projectRoot)].map(SettingsBridge.expand)
            })
        actions.rename = { [weak self] account in self?.renameAccount(account) }
        actions.switchTo = { [weak self] account in self?.switchOrLaunch(account) }
        actions.current = { [weak self] in self?.shownAccountDir() }
        return actions
    }

    /// This window's project: the git root of its workspace folder.
    var projectRoot: String { AgentProject.of(folder.root).root }

    /// agents.set-project-account: the project's new sessions use this
    /// account, whatever the active one is; nil follows the active one again.
    func setProjectAccount(_ account: AgentAccount?) {
        let key = SettingsBridge.tilde(projectRoot)
        settings.store.update { $0.agents.projectAccounts[key] = account.map { SettingsBridge.tilde($0.dir) } }
    }

    static var claudeSource: String { AgentsController.shared.homeFolder + "/.claude" }

    /// agents.add-account: a name, the folder with its links, and a tab with
    /// claude in it, where the user logs in with /login.
    func addAccount() {
        let alert = NSAlert()
        alert.messageText = T("Add an agent account", "Adicionar uma conta de agente")
        alert.informativeText = T("Cadex makes the account's folder, linked to the configuration of ~/.claude, and opens claude in it in a new tab: log in there with /login. Cadex never sees the login.",
                                  "O Cadex cria a pasta da conta, ligada à configuração do ~/.claude, e abre o claude nela numa aba nova: faça o login ali com /login. O Cadex nunca vê o login.")
        let field = NSTextField(string: "")
        field.placeholderString = T("Name, like Work", "Nome, como Trabalho")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: T("Add", "Adicionar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            do {
                let dir = try AgentManagedAccounts.create(name: name, home: AgentsController.shared.homeFolder)
                self.settings.store.update { $0.agents.accountNames[SettingsBridge.tilde(dir)] = name }
                self.tabs?.newTab(cwd: self.folder.root)
                self.tabs?.activeTerminal?.typeWhenReady(SessionKit.shared.claudeCommand(configDir: dir, cwd: self.folder.root) + "\n")
            } catch AgentManagedAccounts.Failure.taken(let dir) {
                self.tell(T("An account with this name exists", "Já existe uma conta com esse nome"), dir)
            } catch AgentManagedAccounts.Failure.badName {
                self.tell(T("Give the account a name", "Dê um nome à conta"), T("Letters or digits, like Work.", "Letras ou números, como Trabalho."))
            } catch {
                self.tell(T("Could not make the account", "Não deu para criar a conta"), error.localizedDescription)
            }
        }
    }

    /// agents.set-active-account and "Use for New Sessions": the default
    /// account is kept as empty.
    func setActiveAccount(_ account: AgentAccount) {
        settings.store.update { $0.agents.activeAccount = account.isDefault ? "" : SettingsBridge.tilde(account.dir) }
    }

    /// agents.sync-account-config: what is new at the top of ~/.claude
    /// becomes a link in every account that follows it; own copies stay.
    func syncAccountConfig() {
        var linked: [String] = []
        accountChange {
            for account in AgentAccountCommands.followers() {
                let plan = AgentConfigShare.plan(account: account.dir, source: Self.claudeSource, replacing: false)
                try AgentConfigShare.apply(plan, account: account.dir, source: Self.claudeSource, trash: AgentManagedAccounts.moveToTrash)
                linked += plan.link.map { account.name + " › " + $0 }
            }
        }
        tell(T("Accounts' configuration in sync", "Configuração das contas sincronizada"),
             linked.isEmpty ? T("Nothing new in ~/.claude.", "Nada de novo no ~/.claude.") : linked.joined(separator: "\n"))
    }

    /// agents.share-account-config on an account that existed before: what
    /// becomes a link and what goes to the trash, shown before anything moves.
    func shareAccountConfig(_ account: AgentAccount) {
        let plan = AgentConfigShare.plan(account: account.dir, source: Self.claudeSource, replacing: true)
        guard !plan.link.isEmpty else { return tell(T("Nothing to share", "Nada a compartilhar"), account.name) }
        let alert = NSAlert()
        alert.messageText = T("Share ~/.claude's configuration with \(account.name)?", "Compartilhar a configuração do ~/.claude com \(account.name)?")
        var text = T("Become links: ", "Viram links: ") + plan.link.joined(separator: ", ") + "."
        if !plan.trash.isEmpty {
            text += "\n\n" + T("Already there, they go to the trash first: ", "Já existem e vão antes para a lixeira: ") + plan.trash.joined(separator: ", ") + "."
        }
        text += "\n\n" + T("Its login, conversations and history stay its own. What Claude writes in a linked file counts for every account.",
                           "O login, as conversas e o histórico continuam dela. O que o Claude grava num arquivo lincado vale para todas as contas.")
        alert.informativeText = text
        alert.addButton(withTitle: T("Share", "Compartilhar"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.accountChange {
                try AgentConfigShare.apply(plan, account: account.dir, source: Self.claudeSource, trash: AgentManagedAccounts.moveToTrash)
            }
        }
    }

    /// agents.remove-account: only an account Cadex made; its folder goes to
    /// the trash after a confirmation, and Cadex forgets its settings.
    func removeAccount(_ dir: String) {
        guard AgentManagedAccounts.isManaged(dir, home: AgentsController.shared.homeFolder) else { return }
        let alert = NSAlert()
        alert.messageText = T("Remove the account \((dir as NSString).lastPathComponent)?", "Remover a conta \((dir as NSString).lastPathComponent)?")
        alert.informativeText = T("Its folder, with its conversations and login, goes to the trash. Your ~/.claude is not touched.",
                                  "A pasta dela, com as conversas e o login, vai para a lixeira. O seu ~/.claude não é tocado.")
        alert.addButton(withTitle: T("Remove", "Remover"))
        alert.addButton(withTitle: T("Cancel", "Cancelar"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.accountChange { try AgentManagedAccounts.moveToTrash(dir) }
            let key = SettingsBridge.tilde(dir)
            self.settings.store.update { s in
                s.agents.accountNames[key] = nil
                s.agents.hiddenAccounts.removeAll { $0 == key }
                s.agents.hiddenLogins[key] = nil
                if s.agents.activeAccount == key { s.agents.activeAccount = "" }
                s.agents.projectAccounts = s.agents.projectAccounts.filter { $0.value != key }
            }
        }
    }

    /// Runs a change on the folders; a failure is said, never silent.
    private func accountChange(_ body: () throws -> Void) {
        do { try body() } catch { tell(T("Could not change the account's folder", "Não deu para mudar a pasta da conta"), error.localizedDescription) }
    }

    private func tell(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.beginSheetModal(for: window)
    }
}
