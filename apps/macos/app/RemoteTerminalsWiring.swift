import AgentTools
import Foundation
import Terminal

/// The terminals from the phone (plan 39, docs/plans/39-terminals-from-the-phone.md):
/// `cadex attach` asks the app for the open terminals and joins one in the
/// terminal daemon. Only terminals the daemon keeps (terminal.keepSessions)
/// can be joined: the rest have no name there.
extension AppDelegate {
    func startRemoteTerminals() {
        AgentToolsServer.shared.onTerminals = { [weak self] in self?.remoteTerminals() ?? [] }
        AgentToolsServer.shared.onNewTerminal = { [weak self] project, claude in
            self?.newRemoteTerminal(project, claude: claude) ?? ["ok": false, "error": "Cadex is closing"]
        }
    }

    /// The project named `project` (its name, any case, or its folder) gets a new tab by
    /// project.new-terminal or project.new-claude; the answer is its daemon session's id.
    func newRemoteTerminal(_ project: String, claude: Bool) -> [String: Any] {
        guard let window = sessions.first, let projects = window.projects else { return ["ok": false, "error": "no Cadex window"] }
        let wanted = project.lowercased()
        guard let found = projects.projects.first(where: { $0.name.lowercased() == wanted || $0.folder == project })
            ?? projects.projects.first(where: { $0.name.lowercased().hasPrefix(wanted) }) else {
            return ["ok": false, "error": "no project \(project); open: " + projects.projects.map(\.name).joined(separator: ", ")]
        }
        window.projectTarget = found.folder
        guard window.commands.run(claude ? "project.new-claude" : "project.new-terminal"),
              let terminal = found.tabs.activeTerminal else { return ["ok": false, "error": "the tab did not open"] }
        guard let id = terminal.keptID else {
            return ["ok": false, "error": "opened in Cadex, but Terminal > Keep sessions is off, so it cannot be shared"]
        }
        return ["ok": true, "id": id, "project": found.name, "tab": claude ? "claude" : (terminal.currentDirectory as NSString?)?.lastPathComponent ?? found.name]
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
