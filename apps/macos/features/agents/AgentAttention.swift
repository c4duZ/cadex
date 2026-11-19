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
    /// A question's options, as the agent reported them; empty: none known (AgentAnswer.parse).
    public var options: [String] = []
    /// The agent's report as it came, to check it still asks the same right before answering.
    public var message: String = ""
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
        let reported = reports.filter { report in
            report.state == .blocked && !hooked.contains { $0.pid == report.pid } && answered[report.key] != report.message
        }.map { report in
            let text = Self.question(report.message)
            let options = report.kind == .permission ? [] : AgentAnswer.options(reported: text, asked: asked[report.pid])
            // The hook's question when it matched: a label with " (" would cut the report's.
            let title = report.kind == .permission ? Self.tool(report.message)
                : options.isEmpty ? AgentAnswer.parse(text).question : asked[report.pid]?.first?.question ?? text
            return AgentRequest(id: "report:" + report.key, kind: report.kind == .permission ? .permission : .question, key: report.key, pid: report.pid,
                                title: title, detail: report.kind == .permission ? Self.subject(report.message) : "",
                                project: report.project, session: report.session, account: report.account, at: Date(), canAnswer: false,
                                options: options, message: report.message)
        }
        return hooked + reported
    }

    /// The bell's and the Dock's number: only what waits on you (the open
    /// requests). With the finished agents nobody saw added, an amber "3" did
    /// not say whether anything was blocked, and people stopped looking (UX
    /// audit, 2026-11-18; ADR 0035 asked for this from the start).
    public var unseen: Int {
        guard isEnabled else { return 0 }
        return cards.count
    }

    /// The agents that finished while nobody looked: shown quietly in the
    /// bell's list, never in its number.
    public var finishedUnseen: Int {
        guard isEnabled else { return 0 }
        return reports.filter(\.finishedUnseen).count
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

    /// The app answers a question in the agent's terminal (it has the terminals; this feature reads
    /// none): true when it sent the keys, false when the agent no longer asks it.
    public var onAnswer: ((AgentRequest, AgentAnswer.Reply) -> Bool)?

    /// An option or words of the owner's for an open question, from its card or ⌘K
    /// (docs/adr/0036-owner-words-reach-the-agent.md). The agent moved on: nothing is typed, and
    /// the feed says so.
    ///
    /// `asked` is the question as the owner saw it: a card keeps its id while its agent asks the
    /// next question, so a reply to the old one must not pass for the new one (review of
    /// 2026-11-17). Once answered, the card goes until the agent reports something else, so a
    /// second click sends nothing.
    public func answerQuestion(_ id: String, asked: String, _ reply: AgentAnswer.Reply) {
        guard let request = cards.first(where: { $0.id == id && $0.message == asked }), request.kind == .question,
              let key = request.key, onAnswer?(request, reply) == true else {
            let gone = cards.first { $0.id == id }
            note(.note, text: T("The agent moved on: nothing was typed", "O agente seguiu: nada foi digitado"),
                 project: gone?.project ?? "", session: gone?.session ?? "", key: gone?.key)
            return
        }
        answered[key] = asked
        publish()
    }

    /// What each agent (by its `claude` pid) last asked through AskUserQuestion, from the hook the
    /// app passes on (AgentAnswer.options). The hook comes before the report.
    private var asked: [Int32: [AgentAnswer.Asked]] = [:]

    public func noteAsked(pid: Int32, _ questions: [AgentAnswer.Asked]) {
        asked[pid] = questions
        publish()
    }

    /// The questions answered from here, by terminal: their cards stay away until the agent
    /// reports something else.
    private var answered: [String: String] = [:]

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
        // An answered question whose agent now says something else is done with.
        answered = answered.filter { key, message in next.contains { $0.key == key && $0.message == message } }
        asked = asked.filter { pid, _ in next.contains { $0.pid == pid } }
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
