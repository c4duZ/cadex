import Foundation
import Strings

/// What an agent in one terminal last reported (OSC 7501), as the app sees
/// it across its windows; this feature reads no terminal itself.
public struct AgentReport: Equatable, Sendable {
    public enum State: String, Sendable { case idle, working, done, blocked, failed }
    public enum Kind: String, Sendable { case none, permission, question, auth }

    /// The terminal's identity in the app, to go back to it.
    public let key: String
    /// The agent's process group: the `claude` pid its hooks carry.
    public let pid: Int32
    public let state: State
    public let kind: Kind
    public let message: String
    public let finishedUnseen: Bool
    public let project: String
    public let session: String
    public let account: String

    public init(key: String, pid: Int32, state: State, kind: Kind, message: String, finishedUnseen: Bool,
                project: String, session: String, account: String) {
        self.key = key
        self.pid = pid
        self.state = state
        self.kind = kind
        self.message = message
        self.finishedUnseen = finishedUnseen
        self.project = project
        self.session = session
        self.account = account
    }
}

/// A card on the board (docs/spec/agents.md, Quadro): a request still open.
public struct AgentRequest: Equatable, Sendable {
    public enum Kind: Sendable, Equatable { case permission, question }

    public let id: String
    public let kind: Kind
    /// The terminal it runs in, when known.
    public let key: String?
    public let pid: Int32
    /// "Bash", or the question's text.
    public let title: String
    /// The command or file, for a permission.
    public let detail: String
    public let project: String
    public let session: String
    public let account: String
    public let at: Date
    /// Answered by Allow and Deny: its hook waits (docs/adr/0023-answer-agent-permissions.md).
    public let canAnswer: Bool
}

/// One line of the feed: what happened, where and when.
public struct AgentFeedEntry: Equatable, Sendable {
    public enum Kind: String, Sendable { case finished, permission, question, failed, taskCreated, note }

    public let at: Date
    public let kind: Kind
    public let key: String?
    public let text: String
    public let project: String
    public let session: String
    public let account: String
}

/// Attention in one place (plan 19, phase C): the board's cards, the feed and
/// the unseen count of the bell and the Dock. Permissions with a waiting hook
/// come from the app's socket; the rest from the agents' own reports.
/// Nothing is answered without the owner's click.
@MainActor
public final class AgentAttention {
    public static let shared = AgentAttention()

    init() {}

    /// agents.attention: off, no cards, feed or count.
    public var isEnabled = true { didSet { publish() } }
    public private(set) var feed: [AgentFeedEntry] = []
    public private(set) var reports: [AgentReport] = []
    /// A feed line's "Mark as Unread": the app marks that terminal's agent.
    public var onMarkUnread: ((String) -> Void)?
    static let feedLimit = 200

    private var pending: [String: (request: AgentRequest, reply: (String?) -> Void)] = [:]
    private var watchers: [UUID: () -> Void] = [:]

    public func watch(_ changed: @escaping () -> Void) -> UUID {
        let id = UUID()
        watchers[id] = changed
        changed()
        return id
    }

    public func stop(_ id: UUID) { watchers[id] = nil }

    /// The open requests, oldest first: hooks waiting for a click, then what
    /// the agents report blocked without such a hook (outside the kit).
    public var cards: [AgentRequest] {
        guard isEnabled else { return [] }
        let hooked = pending.values.map(\.request).sorted { $0.at < $1.at }
        let reported = reports.filter { report in report.state == .blocked && !hooked.contains { $0.pid == report.pid } }.map { report in
            AgentRequest(id: "report:" + report.key, kind: report.kind == .permission ? .permission : .question, key: report.key, pid: report.pid,
                         title: report.kind == .permission ? Self.tool(report.message) : Self.question(report.message),
                         detail: report.kind == .permission ? Self.subject(report.message) : "",
                         project: report.project, session: report.session, account: report.account, at: Date(), canAnswer: false)
        }
        return hooked + reported
    }

    /// The bell's and the Dock's number: open requests and agents that
    /// finished while nobody looked.
    public var unseen: Int {
        guard isEnabled else { return 0 }
        return cards.count + reports.filter(\.finishedUnseen).count
    }

    /// A permission request whose hook waits; `reply` answers it once.
    public func addPermission(pid: Int32, tool: String, subject: String, project: String, session: String, account: String,
                              key: String?, reply: @escaping (String?) -> Void) -> String {
        let id = UUID().uuidString
        let request = AgentRequest(id: id, kind: .permission, key: key, pid: pid, title: tool, detail: subject,
                                   project: project, session: session, account: account, at: Date(), canAnswer: true)
        pending[id] = (request, reply)
        // The agent may have reported "blocked" a moment before its hook
        // arrived: that line already says it (one line per request).
        let already = feed.first.map { $0.kind == .permission && $0.key == key && key != nil && Date().timeIntervalSince($0.at) < 10 } ?? false
        if !already {
            record(.permission, key: key, text: [tool, subject].filter { !$0.isEmpty }.joined(separator: ": "),
                   project: project, session: session, account: account)
        }
        publish()
        return id
    }

    /// Allow, on the owner's click: the command runs and the TUI's dialog closes.
    public func approve(_ id: String) { answer(id, Self.decision(allow: true)) }

    /// Deny, on the owner's click: the agent is told the owner said no.
    public func deny(_ id: String) { answer(id, Self.decision(allow: false)) }

    /// The request went away without a click here (answered in the TUI, or
    /// the hook left): its card goes and its hook gets no answer.
    public func resolve(_ id: String) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.reply(nil)
        publish()
    }

    private func answer(_ id: String, _ decision: String) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.reply(decision)
        publish()
    }

    /// The hook's answer (tested with Claude Code 2.1.325, 2026-11-15:
    /// allow ran the command, deny stopped it and the agent read the message).
    static func decision(allow: Bool) -> String {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { decision["message"] = "The owner denied this in Cadex." }
        let object: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data(), as: UTF8.self)
    }

    /// The agents' reports now: what changed goes to the feed, and a hooked
    /// permission whose agent left "blocked" was answered in the TUI.
    public func update(_ next: [AgentReport]) {
        for report in next {
            let before = reports.first { $0.key == report.key }
            guard before?.state != report.state || before?.message != report.message else { continue }
            switch report.state {
            case .blocked where report.kind != .permission:
                record(.question, key: report.key, text: Self.question(report.message), project: report.project, session: report.session, account: report.account)
            case .blocked where !pending.values.contains { $0.request.pid == report.pid }:
                record(.permission, key: report.key, text: report.message, project: report.project, session: report.session, account: report.account)
            case .done where before?.state != .done:
                record(.finished, key: report.key, text: report.message, project: report.project, session: report.session, account: report.account)
            case .failed where before?.state != .failed:
                record(.failed, key: report.key, text: report.message, project: report.project, session: report.session, account: report.account)
            default:
                break
            }
        }
        // Only leaving "blocked" counts: the hook can arrive before the
        // agent reports blocked, and must not be closed meanwhile.
        let left = Set(next.filter { report in
            report.state != .blocked && reports.contains { $0.key == report.key && $0.state == .blocked }
        }.map(\.pid))
        for (id, entry) in pending where left.contains(entry.request.pid) { resolve(id) }
        reports = next
        publish()
    }

    /// Something outside the agents' reports: a task created (plan 19 phase
    /// D), an agent's `cadex notify` (plan 20), with its terminal's key.
    public func note(_ kind: AgentFeedEntry.Kind, text: String, project: String, session: String = "", key: String? = nil) {
        record(kind, key: key, text: text, project: project, session: session, account: "")
        publish()
    }

    public func markUnread(_ key: String) { onMarkUnread?(key) }

    /// The feed narrowed to a kind and a project; nil keeps all.
    public func feed(kind: AgentFeedEntry.Kind?, project: String?) -> [AgentFeedEntry] {
        feed.filter { entry in (kind == nil || entry.kind == kind) && (project == nil || entry.project == project) }
    }

    /// The projects the feed has lines of, for its filter, by name.
    public var feedProjects: [String] {
        Array(Set(feed.map(\.project).filter { !$0.isEmpty })).sorted()
    }

    private func record(_ kind: AgentFeedEntry.Kind, key: String?, text: String, project: String, session: String, account: String) {
        feed.insert(AgentFeedEntry(at: Date(), kind: kind, key: key, text: text, project: project, session: session, account: account), at: 0)
        if feed.count > Self.feedLimit { feed.removeLast(feed.count - Self.feedLimit) }
    }

    private func publish() {
        for changed in watchers.values { changed() }
    }

    /// "approve Bash: touch x" → "Bash", "touch x"; "answer: Which?" → "Which?".
    static func tool(_ message: String) -> String {
        if case .permission(let tool, _) = AgentStop.fromReport(state: "blocked", kind: "permission", message: message) { return tool }
        return message
    }

    static func subject(_ message: String) -> String {
        if case .permission(_, let subject) = AgentStop.fromReport(state: "blocked", kind: "permission", message: message) { return subject }
        return ""
    }

    static func question(_ message: String) -> String {
        if case .question(let text) = AgentStop.fromReport(state: "blocked", kind: "question", message: message) {
            return text.isEmpty ? T("It waits for your answer.", "Espera a sua resposta.") : text
        }
        return message
    }
}
