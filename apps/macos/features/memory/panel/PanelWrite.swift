import Foundation

/// A write of the panel: the inbox's (plan 40 F: send, hold a queued message for editing, save it,
/// discard the edit) and the review's and the health's (plan 40 G: approve or reject a proposal, a
/// health fix). Each is a command (memory.send-message, memory.edit-message, memory.save-message,
/// memory.discard-message-edit, memory.approve, memory.reject, memory.fix-health; ADR 0005) and a
/// POST of the engine's panel routes.
public enum PanelWrite: Equatable, Sendable {
    case send(from: PanelProjectRef, to: PanelProjectRef, agent: String, subject: String, body: String)
    case hold(id: String, mailbox: PanelProjectRef)
    case save(id: String, mailbox: PanelProjectRef, subject: String, body: String)
    case discard(id: String, mailbox: PanelProjectRef)
    case approve(id: String)
    case reject(id: String, reason: String)
    /// `spool`, `embed`, `embed-all` or `compact` (PanelHealth.Fix).
    case fix(String)

    public static let bodyLimit = 8_000
    public static let subjectLimit = 200

    public var path: String {
        switch self {
        case .send: "extra/messages"
        case .hold(let id, _): "extra/messages/\(PanelPath.segment(id))/edit"
        case .save(let id, _, _, _): "extra/messages/\(PanelPath.segment(id))/save"
        case .discard(let id, _): "extra/messages/\(PanelPath.segment(id))/release"
        case .approve: "extra/review/approve"
        case .reject: "extra/review/reject"
        case .fix: "extra/fix"
        }
    }

    /// The JSON the route takes, as upstream's page sends it.
    public var body: String {
        var o: [String: String]
        switch self {
        case .send(let from, let to, let agent, let subject, let body):
            o = ["from_workspace": from.workspace, "from_project": from.name, "to_workspace": to.workspace, "to_project": to.name,
                 "to_agent": agent, "subject": subject, "body": body]
        case .hold(_, let m), .discard(_, let m): o = ["workspace": m.workspace, "project": m.name]
        case .save(_, let m, let subject, let body): o = ["workspace": m.workspace, "project": m.name, "subject": subject, "body": body]
        case .approve(let id): o = ["id": id]
        case .reject(let id, let reason): o = ["id": id, "reason": reason]
        case .fix(let what): o = ["what": what]
        }
        let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public var command: String {
        switch self {
        case .send: "memory.send-message"
        case .hold: "memory.edit-message"
        case .save: "memory.save-message"
        case .discard: "memory.discard-message-edit"
        case .approve: "memory.approve"
        case .reject: "memory.reject"
        case .fix: "memory.fix-health"
        }
    }

    /// The command's arguments.
    public var arguments: [String: String] {
        let key = { (p: PanelProjectRef) in p.workspace + "/" + p.name }
        switch self {
        case .send(let from, let to, let agent, let subject, let body):
            return ["from": key(from), "to": key(to), "agent": agent, "subject": subject, "body": body]
        case .hold(let id, let m), .discard(let id, let m): return ["id": id, "mailbox": key(m)]
        case .save(let id, let m, let subject, let body): return ["id": id, "mailbox": key(m), "subject": subject, "body": body]
        case .approve(let id): return ["id": id]
        case .reject(let id, let reason): return reason.isEmpty ? ["id": id] : ["id": id, "reason": reason]
        case .fix(let what): return ["what": what]
        }
    }

    /// The write a command's arguments name; nil when one is missing.
    public init?(command: String, arguments a: [String: String]) {
        let ref = { (key: String) in a[key].flatMap(PanelSearchQuery.scope(from:)) }
        switch command {
        case "memory.send-message":
            guard let from = ref("from"), let agent = a["agent"], let body = a["body"] else { return nil }
            self = .send(from: from, to: ref("to") ?? from, agent: agent, subject: a["subject"] ?? "", body: body)
        case "memory.edit-message", "memory.discard-message-edit":
            guard let id = a["id"], let m = ref("mailbox") else { return nil }
            self = command == "memory.edit-message" ? .hold(id: id, mailbox: m) : .discard(id: id, mailbox: m)
        case "memory.save-message":
            guard let id = a["id"], let m = ref("mailbox"), let body = a["body"] else { return nil }
            self = .save(id: id, mailbox: m, subject: a["subject"] ?? "", body: body)
        case "memory.approve", "memory.reject":
            guard let id = a["id"], !id.isEmpty else { return nil }
            self = command == "memory.approve" ? .approve(id: id) : .reject(id: id, reason: a["reason"] ?? "")
        case "memory.fix-health":
            guard let what = a["what"], PanelHealth.fixes.contains(what) else { return nil }
            self = .fix(what)
        default: return nil
        }
    }
}

/// A screen that sends writes and shows what the engine answered.
@MainActor
protocol PanelWriting: AnyObject {
    func finished(_ done: PanelWrite, _ answer: Result<Data, PanelReadError>)
}
