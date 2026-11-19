import AgentTools
import Terminal

/// The terminals from the phone (plan 39, docs/plans/39-terminals-from-the-phone.md):
/// `cadex attach` asks the app for the open terminals and joins one in the
/// terminal daemon. Only terminals the daemon keeps (terminal.keepSessions)
/// can be joined: the rest have no name there.
extension AppDelegate {
    func startRemoteTerminals() {
        AgentToolsServer.shared.onTerminals = { [weak self] in self?.remoteTerminals() ?? [] }
    }

    /// The main window's projects, in their order, and each kept terminal.
    func remoteTerminals() -> [[String: Any]] {
        guard let projects = sessions.first?.projects else { return [] }
        return projects.projects.flatMap { project in
            project.tabs.listedTerminals.compactMap { title, terminal -> [String: Any]? in
                guard let id = terminal.keptID else { return nil }
                var row: [String: Any] = ["id": id, "project": project.name, "tab": title,
                                          "folder": terminal.currentDirectory ?? project.folder]
                if let agent = terminal.agentStatus, agent.state != .none { row["agent"] = Self.agentWord(agent.state) }
                return row
            }
        }
    }

    private static func agentWord(_ state: TerminalAgentStatus.State) -> String {
        switch state {
        case .none: return ""
        case .idle: return "idle"
        case .working: return "working"
        case .done: return "done"
        case .blocked: return "waiting"
        case .failed: return "failed"
        }
    }
}
