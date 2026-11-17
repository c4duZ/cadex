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
            switch SessionKit.shared.typedLaunch(configDir: request.configDir, cwd: request.cwd,
                                                 ownerSettings: request.userSettings, arguments: request.arguments) {
            case .success(let kit): return .kit(arguments: kit.arguments, unset: kit.unset, pathFirst: kit.pathFirst)
            case .failure(let refusal): return .refused(refusal.reason)
            }
        }
    }

    /// The shells of every terminal in every window and space, the kept
    /// ones (in the terminal daemon) included.
    private func terminalShells() -> [Int32] {
        sessions.flatMap { $0.projects?.projects ?? [] }.flatMap(\.tabs.allTerminals).map(\.shellPid).filter { $0 > 0 }
    }
}
