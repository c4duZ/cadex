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

    /// The line `cadex hook` sent, without its token; nil when it does not read.
    static func parse(_ object: [String: Any]) -> AgentHookEvent? {
        guard let event = object["event"] as? String, !event.isEmpty else { return nil }
        let payload = object["payload"] as? [String: Any] ?? [:]
        return AgentHookEvent(event: event, pid: (object["pid"] as? NSNumber)?.int32Value ?? 0,
                              sessionID: payload["session_id"] as? String, transcriptPath: payload["transcript_path"] as? String,
                              cwd: payload["cwd"] as? String, source: payload["source"] as? String,
                              notificationType: payload["notification_type"] as? String, toolName: payload["tool_name"] as? String,
                              toolSubject: subject(payload["tool_input"] as? [String: Any] ?? [:]), kitSession: nil)
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
