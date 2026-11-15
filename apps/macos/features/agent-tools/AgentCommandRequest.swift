import Foundation

/// A command the agent of a session Cadex opened asks the app to run, by
/// `cadex run`, a shortcut or `cadex mcp` (docs/adr/0024-agent-tools.md):
/// its id (nil: the list), the arguments, the pids above the asking
/// process (the agent's terminal runs one of them) and the kit session its
/// token belongs to.
public struct AgentCommandRequest: Sendable, Equatable {
    public let id: String?
    public let arguments: [String: String]
    public let pids: [Int32]
    public let kitSession: String

    /// The line `cadex` sent, its token already checked; nil when it is not
    /// a command request (a hook) or does not read.
    static func parse(_ object: [String: Any], kitSession: String) -> AgentCommandRequest? {
        let pids = (object["pids"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.int32Value }
        if object["list"] as? Bool == true { return AgentCommandRequest(id: nil, arguments: [:], pids: pids, kitSession: kitSession) }
        guard let id = object["run"] as? String, !id.isEmpty else { return nil }
        let arguments = (object["args"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
        return AgentCommandRequest(id: id, arguments: arguments, pids: pids, kitSession: kitSession)
    }
}

/// What the app answers a command request.
public enum AgentCommandAnswer: Sendable, Equatable {
    case ok(String)
    case failed(String)

    var json: [String: Any] {
        switch self {
        case .ok(let text): ["ok": true, "result": text]
        case .failed(let text): ["ok": false, "error": text]
        }
    }
}

/// The commands the agent may run (docs/adr/0024-agent-tools.md): open,
/// tell the owner, the task's status and comment, the preview. Never close,
/// delete, change the repository, an account, a token, a setting or a
/// permission. Only an ADR adds to this list.
public enum AgentCommandList {
    public static let allowed: [String] = [
        "agent-tools.open-file", "agent-tools.open-diff", "agent-tools.notify",
        "preview.open", "preview.reload", "preview.back", "preview.forward", "preview.agent",
        "worktrees.set-status", "worktrees.set-comment",
        // Computer use (docs/adr/0026-computer-use.md): off by default, asked app by app.
        "computer-use.agent",
    ]

    public static func allows(_ id: String) -> Bool { allowed.contains(id) }
}
