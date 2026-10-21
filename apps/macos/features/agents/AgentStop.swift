import Foundation
import Strings

/// Why an agent stopped and waits for you (docs/spec/agents.md,
/// Notificações): read from the end of its conversation log, the last
/// 64 KB, once per stop, never the whole log (ADR 0019 allows this much).
public enum AgentStop: Equatable, Sendable {
    /// It asks to run a tool: "Bash", "Edit"...
    case permission(String)
    /// It asked you something (or a plan to approve).
    case question
    /// It finished its turn.
    case finished
    /// The log did not say.
    case unknown

    /// Tools that are a question to the user, not work to allow.
    static let questionTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]
    static let tailBytes = 64 * 1024

    /// The conversation log of a session: its id, beside its subagents' folder.
    public static func log(of session: AgentSession) -> String {
        let encoded = session.cwd.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        return "\(session.account.dir)/projects/\(encoded)/\(session.id).jsonl"
    }

    /// Reads the end of the session's log and says why it stopped.
    public static func read(_ session: AgentSession) -> AgentStop {
        guard let handle = FileHandle(forReadingAtPath: log(of: session)) else { return .unknown }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        // The first line may be cut by the seek.
        if size > UInt64(tailBytes), !lines.isEmpty { lines.removeFirst() }
        return classify(lines)
    }

    /// The last message decides: an assistant turn that ended is finished;
    /// one that called a question tool is a question; one that called any
    /// other tool with no result after it waits for permission.
    static func classify(_ lines: [String]) -> AgentStop {
        var answered: Set<String> = []
        for line in lines.reversed() {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let message = object["message"] as? [String: Any] else { continue }
            let content = message["content"] as? [[String: Any]] ?? []
            switch object["type"] as? String {
            case "user":
                for part in content where part["type"] as? String == "tool_result" {
                    if let id = part["tool_use_id"] as? String { answered.insert(id) }
                }
                // A message from you after the last answer: nothing to wait on.
                if content.isEmpty || content.contains(where: { $0["type"] as? String == "text" }) { return .unknown }
            case "assistant":
                let calls = content.filter { $0["type"] as? String == "tool_use" }
                if let call = calls.last(where: { !answered.contains($0["id"] as? String ?? "") }) {
                    let name = call["name"] as? String ?? "?"
                    return questionTools.contains(name) ? .question : .permission(name)
                }
                if message["stop_reason"] as? String == "end_turn" { return .finished }
                if !calls.isEmpty { return .unknown }
            default:
                continue
            }
        }
        return .unknown
    }

    /// The notification's words.
    public var text: String {
        switch self {
        case .permission(let tool): T("Asks permission to run \(tool)", "Pede permissão para rodar \(tool)")
        case .question: T("Asked you a question", "Fez uma pergunta")
        case .finished: T("Finished", "Terminou")
        case .unknown: T("Stopped and waits for you", "Parou e espera você")
        }
    }
}
