import Foundation

/// One hook event from a session Cadex opened, as `cadex hook` sends it
/// (core/features/agent-tools/hook.zig): the event's name, the pid of the
/// `claude` that ran the hook, and what Claude Code gave the hook.
public struct AgentHookEvent: Sendable, Equatable {
    /// "SessionStart", "Stop", "Notification", "PermissionRequest", "SessionEnd", "CwdChanged".
    public let event: String
    public let pid: Int32
    public let sessionID: String?
    public let transcriptPath: String?
    public let cwd: String?
    /// SessionStart's: "startup", "resume", "clear", "compact".
    public let source: String?
    /// Notification's: "permission_prompt", "idle_prompt"….
    public let notificationType: String?
    public let toolName: String?
    /// What the tool would act on: the command, the file, the pattern or the address.
    public let toolSubject: String?
    /// The session kit's name for the session (its token's file), set by
    /// the socket: a hibernated agent comes back with the same token.
    public internal(set) var kitSession: String?
    /// PostToolUse (plan 21 phase E): the file an agent edited and the lines
    /// it wrote, as `cadex hook` cut them (never the file's text).
    public var edit: AgentEdit?
    /// PreToolUse of AskUserQuestion (plan 26 D2): the questions as the agent wrote them, each
    /// option apart. The report in the terminal joins the labels with " · " and shows only the
    /// first question of a form (Claude Code 2.1.326, 2026-11-17): only this is exact.
    public var questions: [AgentAskedQuestion]?

    /// The line `cadex hook` sent, without its token; nil when it does not read.
    static func parse(_ object: [String: Any]) -> AgentHookEvent? {
        guard let event = object["event"] as? String, !event.isEmpty else { return nil }
        let payload = object["payload"] as? [String: Any] ?? [:]
        return AgentHookEvent(event: event, pid: (object["pid"] as? NSNumber)?.int32Value ?? 0,
                              sessionID: payload["session_id"] as? String, transcriptPath: payload["transcript_path"] as? String,
                              cwd: payload["cwd"] as? String, source: payload["source"] as? String,
                              notificationType: payload["notification_type"] as? String, toolName: payload["tool_name"] as? String,
                              toolSubject: subject(payload["tool_input"] as? [String: Any] ?? [:]), kitSession: nil,
                              edit: event == "PostToolUse" ? AgentEdit(payload) : nil,
                              questions: event == "PreToolUse" && payload["tool_name"] as? String == "AskUserQuestion"
                                  ? AgentAskedQuestion.list(payload["tool_input"] as? [String: Any] ?? [:]) : nil)
    }

    /// The part of a tool's input a person reads first, as the permission
    /// dialog shows it.
    static func subject(_ input: [String: Any]) -> String? {
        for key in ["command", "file_path", "path", "pattern", "url", "query", "prompt", "description"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        return input.values.compactMap { $0 as? String }.first
    }
}

/// An agent's edit: the file, the lines it wrote ([start, end], 1-based),
/// or the whole file (a Write that made it).
public struct AgentEdit: Sendable, Equatable {
    public let file: String
    public let lines: [ClosedRange<Int>]
    public let whole: Bool

    init?(_ payload: [String: Any]) {
        guard let file = payload["file"] as? String, !file.isEmpty else { return nil }
        self.file = file
        whole = payload["whole"] as? Bool ?? false
        lines = (payload["lines"] as? [[Any]] ?? []).compactMap { pair in
            guard pair.count == 2, let a = (pair[0] as? NSNumber)?.intValue, let b = (pair[1] as? NSNumber)?.intValue, a <= b else { return nil }
            return a...b
        }
    }
}

/// One question of an AskUserQuestion: its text, its options' labels, and whether several may be
/// picked.
public struct AgentAskedQuestion: Sendable, Equatable {
    public let question: String
    public let options: [String]
    public let multiSelect: Bool

    static func list(_ input: [String: Any]) -> [AgentAskedQuestion] {
        (input["questions"] as? [[String: Any]] ?? []).compactMap { item in
            guard let question = item["question"] as? String else { return nil }
            let options = (item["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            return AgentAskedQuestion(question: question, options: options, multiSelect: item["multiSelect"] as? Bool ?? false)
        }
    }
}
