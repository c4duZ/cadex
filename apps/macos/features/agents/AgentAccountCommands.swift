import CommandPalette
import Foundation
import Icons
import Strings

/// Which account a new session opened by Cadex uses (docs/spec/agents.md,
/// Contas gerenciadas): the project's own account (by git root) beats the
/// active one; an account that is no longer there falls back to the default.
public enum AgentNewSession {
    public static func account(cwd: String, accounts: [AgentAccount], active: String?, projects: [String: String],
                               projectRoot: (String) -> String = { AgentProject.of($0).root }) -> AgentAccount? {
        let claude = accounts.filter { $0.provider == .claude }
        if let dir = projects[projectRoot(cwd)], let found = claude.first(where: { $0.dir == dir }) { return found }
        if let active, let found = claude.first(where: { $0.dir == active }) { return found }
        return claude.first { $0.isDefault }
    }
}

/// What the app does for each account command: the asking, confirming and
/// the tab are the app's (apps/macos/app/AgentsAccounts.swift); the folders'
/// work is AgentManagedAccounts and AgentConfigShare.
public struct AgentAccountActions {
    public var add: @MainActor () -> Void
    public var setActive: @MainActor (AgentAccount) -> Void
    public var sync: @MainActor () -> Void
    public var share: @MainActor (AgentAccount) -> Void
    public var ownCopy: @MainActor (_ account: String, _ item: String) -> Void
    public var follow: @MainActor (_ account: String, _ item: String) -> Void
    public var remove: @MainActor (_ account: String) -> Void
    /// This window's project gets its own account; nil goes back to the active one.
    public var setProject: @MainActor (AgentAccount?) -> Void = { _ in }
    /// Rename an account (the app asks the name): it was the Accounts page's right click until
    /// the page left the sidebar (plan 26 phase E).
    public var rename: @MainActor (AgentAccount) -> Void = { _ in }
    /// Plan 33 E: the Claude in the focused terminal goes on in this account (the session ends, its
    /// handoff goes to the memory, "Continue in…" runs in the same pane); with none, the account opens.
    public var switchTo: @MainActor (AgentAccount) -> Void = { _ in }
    /// The account the focused agent runs in (the one both bars show): marked in the switch's list.
    public var current: @MainActor () -> String? = { nil }
    /// A Claude runs in the focused terminal: the list takes it to another account; with none, the
    /// list picks the account the next `claude` typed there opens in (the owner, 2026-11-18).
    public var inSession: @MainActor () -> Bool = { true }
    /// The account this window's project has now, by folder.
    public var projectAccount: @MainActor () -> String? = { nil }

    public init(add: @escaping @MainActor () -> Void, setActive: @escaping @MainActor (AgentAccount) -> Void,
                sync: @escaping @MainActor () -> Void, share: @escaping @MainActor (AgentAccount) -> Void,
                ownCopy: @escaping @MainActor (String, String) -> Void, follow: @escaping @MainActor (String, String) -> Void,
                remove: @escaping @MainActor (String) -> Void,
                setProject: @escaping @MainActor (AgentAccount?) -> Void = { _ in },
                projectAccount: @escaping @MainActor () -> String? = { nil }) {
        self.add = add
        self.setActive = setActive
        self.sync = sync
        self.share = share
        self.ownCopy = ownCopy
        self.follow = follow
        self.remove = remove
        self.setProject = setProject
        self.projectAccount = projectAccount
    }
}

/// The account commands (ADR 0005: every action is a command). The ones
/// that need a choice open a list in ⌘K.
public enum AgentAccountCommands {
    @MainActor
    public static func commands(palette: CommandPaletteController, actions: AgentAccountActions) -> [Command] {
        let agents = AgentsController.shared
        let source = agents.home + "/.claude"
        func list(_ placeholder: String, _ empty: String, _ items: @escaping @MainActor () -> [PaletteItem],
                  _ choose: @escaping @MainActor (String) -> Void) -> Command.Action {
            .run { palette.open(AgentChoiceSource(placeholder: placeholder, empty: empty, items: items, choose: choose)) }
        }
        return [
            Command(id: "agents.add-account", title: T("Add Agent Account", "Adicionar conta de agente"),
                    keywords: ["account", "claude", "login", "new", "conta", "nova", "agente"], category: .terminal,
                    action: .run { actions.add() }),
            Command(id: "agents.set-active-account", title: T("Set Active Agent Account", "Escolher a conta ativa dos agentes"),
                    keywords: ["account", "active", "default", "conta", "ativa", "padrão", "claude"], category: .terminal,
                    action: list(T("The account of new sessions", "A conta das sessões novas"), T("No account in use", "Nenhuma conta em uso"), {
                        AgentUsageController.shared.visibleAccounts().filter { $0.provider == .claude }.map { account in
                            PaletteItem(id: account.dir, title: account.name,
                                        detail: account.dir == AgentUsageController.shared.activeAccount ? T("active", "ativa") : nil, icon: .gauge)
                        }
                    }) { dir in
                        if let account = agents.everyAccount().first(where: { $0.dir == dir }) { actions.setActive(account) }
                    }),
            Command(id: "agents.switch-account", title: T("Switch Account…", "Trocar de conta…"),
                    keywords: ["account", "switch", "limit", "continue", "conta", "trocar", "limite", "continuar", "claude"], category: .terminal,
                    action: .run {
                        let session = actions.inSession()
                        palette.open(AgentChoiceSource(
                            placeholder: session ? T("Go on in another account…", "Continuar em outra conta…")
                                                 : T("Account for the next claude…", "Conta do próximo claude…"),
                            empty: T("No account in use", "Nenhuma conta em uso"),
                            hint: session ? T("This session ends and the work goes on in the account you choose, through the memory.",
                                              "A sessão de agora termina e o trabalho continua na conta escolhida, pela memória.")
                                          : T("Type claude here, or open a new terminal, and it starts in the account you choose.",
                                              "Digite claude aqui, ou abra um terminal novo, e ele começa na conta escolhida."),
                            icon: .arrowsLeftRight, items: { AgentSwitch.rows(current: actions.current(), inSession: session) }) { dir in
                            if let account = agents.everyAccount().first(where: { $0.dir == dir }) { actions.switchTo(account) }
                        })
                    }),
            Command(id: "agents.rename-account", title: T("Rename an Agent Account…", "Renomear uma conta de agente…"),
                    keywords: ["account", "rename", "name", "conta", "renomear", "nome"], category: .terminal,
                    action: list(T("The account to rename", "A conta a renomear"), T("No account in use", "Nenhuma conta em uso"), {
                        AgentUsageController.shared.visibleAccounts().map { PaletteItem(id: $0.dir, title: $0.name, detail: nil, icon: .gauge) }
                    }) { dir in
                        if let account = agents.everyAccount().first(where: { $0.dir == dir }) { actions.rename(account) }
                    }),
            Command(id: "agents.set-project-account", title: T("Set This Project's Agent Account", "Escolher a conta de agente deste projeto"),
                    keywords: ["account", "project", "repository", "conta", "projeto", "repositório", "claude"], category: .terminal,
                    action: list(T("The account of this project's new sessions", "A conta das sessões novas deste projeto"), T("No account in use", "Nenhuma conta em uso"), {
                        let current = actions.projectAccount()
                        let follow = PaletteItem(id: "", title: T("Use the Active Account", "Usar a conta ativa"),
                                                 detail: current == nil ? T("now", "agora") : nil, icon: .arrowCounterClockwise)
                        return [follow] + AgentUsageController.shared.visibleAccounts().filter { $0.provider == .claude }.map { account in
                            PaletteItem(id: account.dir, title: account.name, detail: account.dir == current ? T("this project", "este projeto") : nil, icon: .gauge)
                        }
                    }) { dir in
                        actions.setProject(dir.isEmpty ? nil : agents.everyAccount().first { $0.dir == dir })
                    }),
            Command(id: "agents.sync-account-config", title: T("Sync Agent Accounts' Config", "Sincronizar a configuração das contas"),
                    keywords: ["sync", "skills", "settings", "link", "sincronizar", "configuração", "contas"], category: .terminal,
                    action: .run { actions.sync() }),
            Command(id: "agents.share-account-config", title: T("Share the Default Account's Config…", "Compartilhar a configuração da conta padrão…"),
                    keywords: ["share", "link", "skills", "settings", "compartilhar", "configuração", "conta"], category: .terminal,
                    action: list(T("The account that follows ~/.claude", "A conta que segue o ~/.claude"), T("Every account already follows it", "Todas as contas já seguem"), {
                        agents.everyAccount().filter { account in
                            account.provider == .claude && !account.isDefault
                                && !AgentConfigShare.follows(account: account.dir, source: source, managed: AgentManagedAccounts.isManaged(account.dir, home: agents.home))
                        }.map { PaletteItem(id: $0.dir, title: $0.name, detail: "~/" + ($0.dir as NSString).lastPathComponent, icon: .gauge) }
                    }) { dir in
                        if let account = agents.everyAccount().first(where: { $0.dir == dir }) { actions.share(account) }
                    }),
            Command(id: "agents.use-own-copy", title: T("Use an Account's Own Copy…", "Usar uma cópia própria numa conta…"),
                    keywords: ["copy", "own", "unlink", "cópia", "própria", "configuração"], category: .terminal,
                    action: list(T("The item that stops following ~/.claude", "O item que deixa de seguir o ~/.claude"), T("Nothing linked", "Nada lincado"), {
                        items(.linked)
                    }) { id in split(id).map { actions.ownCopy($0.0, $0.1) } }),
            Command(id: "agents.follow-default-config", title: T("Follow the Default Account Again…", "Voltar a seguir a conta padrão…"),
                    keywords: ["follow", "link", "copy", "seguir", "cópia", "configuração"], category: .terminal,
                    action: list(T("The own copy that follows ~/.claude again", "A cópia própria que volta a seguir o ~/.claude"), T("No own copies", "Nenhuma cópia própria"), {
                        items(.own)
                    }) { id in split(id).map { actions.follow($0.0, $0.1) } }),
            Command(id: "agents.remove-account", title: T("Remove Agent Account…", "Remover conta de agente…"),
                    keywords: ["remove", "delete", "account", "remover", "apagar", "conta"], category: .terminal,
                    action: list(T("The account Cadex made to remove", "A conta criada pelo Cadex a remover"), T("Cadex made no account", "O Cadex não criou nenhuma conta"), {
                        AgentManagedAccounts.all(home: agents.home).map { dir in
                            PaletteItem(id: dir, title: agents.everyAccount().first { $0.dir == dir }?.name ?? (dir as NSString).lastPathComponent,
                                        detail: (dir as NSString).lastPathComponent, icon: .trash)
                        }
                    }) { dir in actions.remove(dir) }),
        ]
    }

    /// "account › item" for every account that follows the default one.
    @MainActor
    static func items(_ wanted: AgentConfigShare.Item) -> [PaletteItem] {
        let agents = AgentsController.shared
        let source = agents.home + "/.claude"
        return followers().flatMap { account in
            AgentConfigShare.sharable(source: source).filter { AgentConfigShare.item($0, account: account.dir, source: source) == wanted }.map { name in
                PaletteItem(id: account.dir + "\n" + name, title: account.name + " › " + name, icon: wanted == .linked ? .copy : .link)
            }
        }
    }

    /// The accounts that follow ~/.claude: the managed ones and those with a link into it.
    @MainActor
    public static func followers() -> [AgentAccount] {
        let agents = AgentsController.shared
        let source = agents.home + "/.claude"
        var list = agents.everyAccount().filter {
            $0.provider == .claude && !$0.isDefault
                && AgentConfigShare.follows(account: $0.dir, source: source, managed: AgentManagedAccounts.isManaged($0.dir, home: agents.home))
        }
        // A managed account before its first run has no .claude.json, so it is not an account yet.
        for dir in AgentManagedAccounts.all(home: agents.home) where !list.contains(where: { $0.dir == dir }) {
            list.append(AgentAccount(dir: dir, name: (dir as NSString).lastPathComponent, isDefault: false))
        }
        return list
    }

    static func split(_ id: String) -> (String, String)? {
        let parts = id.split(separator: "\n", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
}

/// ⌘K's list of accounts for a choice another feature's action needs
/// ("Continue in another account").
public enum AgentAccountPicker {
    @MainActor
    public static func open(palette: CommandPaletteController, accounts: [AgentAccount], placeholder: String,
                            choose: @escaping @MainActor (AgentAccount) -> Void) {
        palette.open(AgentChoiceSource(placeholder: placeholder, empty: T("No other account in use", "Nenhuma outra conta em uso"), items: {
            accounts.map { PaletteItem(id: $0.dir, title: $0.name, detail: "~/" + ($0.dir as NSString).lastPathComponent, icon: .gauge) }
        }) { dir in
            if let account = accounts.first(where: { $0.dir == dir }) { choose(account) }
        })
    }
}

/// A ⌘K list of choices for one command (the app's agent-tools.show-sessions too).
@MainActor
public final class AgentChoiceSource: PaletteSource {
    public let placeholder: String
    public let emptyText: String
    public let hint: String?
    public let icon: Icon
    private let items: () -> [PaletteItem]
    private let pick: (String) -> Void

    public init(placeholder: String, empty: String, hint: String? = nil, icon: Icon = .gauge,
                items: @escaping () -> [PaletteItem], choose: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.emptyText = empty
        self.hint = hint
        self.icon = icon
        self.items = items
        self.pick = choose
    }

    public func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        show(items().filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }, nil)
    }

    public func choose(_ item: PaletteItem) { pick(item.id) }

    public func stop() {}
}
