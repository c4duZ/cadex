import Agents
import AgentTools
import AppKit
import SessionKit
import Terminal

/// The `claude` typed in a Cadex zsh tab gets the session kit (plan 22,
/// phase C; docs/spec/terminal.md): the tab's zsh runs `cadex claude`,
/// which asks here over the app's socket. Only a process under the shell
/// of one of this app's terminals gets it; the account stays the tab's.
extension AppDelegate {
    /// The zsh integration's variables in this process's environment, which
    /// the tabs and the terminal daemon inherit; a test instance's tabs
    /// (CADEX_SOCKETS_DIR) ask its own socket, not the owner's app.
    static func exportTypedClaudeEnvironment() {
        TerminalShellIntegration.export(tools: SessionKit.shared.toolsPath)
        if ProcessInfo.processInfo.environment["CADEX_SOCKETS_DIR"] != nil {
            setenv("CADEX_APP_SOCKET", SessionKit.socketsFolder + "/app.sock", 1)
        }
    }

    func startTypedClaude() {
        AgentToolsServer.shared.onKit = { [weak self] request in
            guard let self else { return .refused("Cadex is closing") }
            guard request.comesFrom(shells: self.terminalShells()) else { return .refused("not a Cadex terminal") }
            // A tab with no account of its own gets the project's or the active one, as the sessions
            // Cadex opens (plan 33 F); the default account needs no folder.
            let chosen = request.configDir.isEmpty ? self.newSessionAccount(cwd: request.cwd).flatMap { $0.isDefault ? nil : $0.dir } : nil
            switch SessionKit.shared.typedLaunch(configDir: chosen ?? request.configDir, cwd: request.cwd,
                                                 ownerSettings: request.userSettings, arguments: request.arguments) {
            case .success(let kit):
                self.noteTypedAccount(chosen ?? request.configDir, request: request)
                let skip = SessionKit.skipPermissions(on: self.settings.store.settings.agents.launchSkipPermissions, typed: request.arguments)
                return .kit(arguments: kit.arguments + skip, unset: kit.unset, pathFirst: kit.pathFirst, configDir: chosen)
            case .failure(let refusal): return .refused(refusal.reason)
            }
        }
    }

    /// A `claude` typed in the terminal the owner is looking at makes its account the one the next
    /// `claude` and new terminals open in (the owner, 2026-11-18: ⌘D follows the last Claude). Only
    /// from the focused terminal of the key window (any window's with none key, as a test instance
    /// in the background): an automation's tab must not move it. A project with its own account
    /// keeps it.
    private func noteTypedAccount(_ dir: String, request: AgentKitRequest) {
        let key = sessions.filter { $0.window.isKeyWindow || $0.window.isMainWindow }
        let focused = (key.isEmpty ? sessions : key).compactMap { $0.tabs?.activeTerminal?.shellPid }.filter { $0 > 0 }
        guard request.comesFrom(shells: focused) else { return }
        let projectKey = SettingsBridge.tilde(AgentProject.of(request.cwd).root)
        guard settings.store.settings.agents.projectAccounts[projectKey] == nil else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser.path + "/.claude"
        let value = dir.isEmpty || dir == home ? "" : SettingsBridge.tilde(dir)
        guard settings.store.settings.agents.activeAccount != value else { return }
        settings.store.update { $0.agents.activeAccount = value }
    }

    /// The account of a new session in `cwd`: the project's, else the active one, else the default.
    func newSessionAccount(cwd: String) -> AgentAccount? {
        let agents = settings.store.settings.agents
        let projects = agents.projectAccounts.reduce(into: [String: String]()) { $0[SettingsBridge.expand($1.key)] = SettingsBridge.expand($1.value) }
        return AgentNewSession.account(cwd: cwd, accounts: AgentsController.shared.everyAccount(),
                                       active: agents.activeAccount.isEmpty ? nil : SettingsBridge.expand(agents.activeAccount), projects: projects)
    }

    /// The shells of every terminal in every window and space, the kept
    /// ones (in the terminal daemon) included.
    private func terminalShells() -> [Int32] {
        // The drawer's quick terminals too (plan 33 F: a claude typed there was refused).
        let projects = sessions.flatMap { $0.projects?.projects ?? [] }.flatMap(\.tabs.allTerminals)
        let drawers = sessions.compactMap(\.drawer).flatMap(\.tabs.allTerminals)
        return (projects + drawers).map(\.shellPid).filter { $0 > 0 }
    }
}

