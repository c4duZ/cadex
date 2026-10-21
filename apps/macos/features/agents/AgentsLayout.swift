import Foundation
import Strings

/// How the Agents page arranges the sessions, pure so it is tested
/// without a window (docs/spec/agents.md, Sessions).
public enum AgentsLayout {
    public struct Group: Equatable {
        public let project: AgentProject
        public let sessions: [AgentSession]
    }

    /// One group per repository (or folder), the one with the latest
    /// change first; in a group, waiting ones first (they need you), then
    /// working, newest first.
    public static func groups(_ sessions: [AgentSession], project: (String) -> AgentProject = AgentProject.of) -> [Group] {
        var projects: [String: AgentProject] = [:]
        var byRoot: [String: [AgentSession]] = [:]
        var order: [String] = []
        for session in sessions {
            let found = projects[session.cwd] ?? project(session.cwd)
            projects[session.cwd] = found
            if byRoot[found.root] == nil { order.append(found.root) }
            byRoot[found.root, default: []].append(session)
        }
        let groups = order.map { root -> Group in
            let list = byRoot[root] ?? []
            let first = list.first.map { projects[$0.cwd] } ?? nil
            return Group(project: first ?? AgentProject(root: root, name: (root as NSString).lastPathComponent, branch: nil),
                         sessions: list.sorted(by: before))
        }
        return groups.sorted { ($0.sessions.map(\.since).max() ?? .distantPast) > ($1.sessions.map(\.since).max() ?? .distantPast) }
    }

    static func before(_ a: AgentSession, _ b: AgentSession) -> Bool {
        let rank = { (s: AgentSession) -> Int in s.status == .waiting ? 0 : s.status == .working ? 1 : 2 }
        return rank(a) != rank(b) ? rank(a) < rank(b) : a.since > b.since
    }

    /// The line under a session's name: "main · Liderhub", "waiting for
    /// you · BKDG", with "outside Cadex" for one in another terminal.
    public static func detail(_ session: AgentSession, project: AgentProject, inCadex: Bool) -> String {
        var parts: [String] = []
        switch session.status {
        case .waiting: parts.append(T("waiting for you", "esperando você"))
        case .other(let status) where !status.isEmpty: parts.append(status)
        default: if let branch = project.branch { parts.append(branch) }
        }
        parts.append(session.account.name)
        if !inCadex { parts.append(T("outside Cadex", "fora do Cadex")) }
        return parts.joined(separator: " · ")
    }
}
