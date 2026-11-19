import Foundation

/// A project's screens' data (plan 40 D), read from the engine's panel routes (docs/spec/memory.md,
/// "Os dados do painel Memória"): `extra/.../summary`, `api/v1/.../pages`, `.../sessions`,
/// `.../agents`, `.../tokens`. Only reads; each parse is pure, so the tests read the recorded seed.

/// The JSON pieces the parsers share.
enum PanelJSON {
    static func object(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    }
    static func array(_ data: Data?) -> [[String: Any]]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]
    }
    static func rows(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
    static func int(_ value: Any?) -> Int { PanelOverviewData.int(value) }
    static func text(_ value: Any?) -> String? { (value as? String).flatMap { $0.isEmpty ? nil : $0 } }
    static func date(_ value: Any?) -> Date? { PanelOverviewData.date(value) }
}

/// Reported token totals (a session's `usage`, the project's total).
public struct PanelUsage: Equatable, Sendable {
    public var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
    public var model: String?
    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite: Int = 0, model: String? = nil) {
        (self.input, self.output, self.cacheRead, self.cacheWrite, self.model) = (input, output, cacheRead, cacheWrite, model)
    }
    static func parse(_ value: Any?) -> PanelUsage? {
        guard let u = value as? [String: Any] else { return nil }
        return PanelUsage(input: PanelJSON.int(u["input_tokens"]), output: PanelJSON.int(u["output_tokens"]),
                          cacheRead: PanelJSON.int(u["cache_read_tokens"]), cacheWrite: PanelJSON.int(u["cache_write_tokens"]),
                          model: PanelJSON.text(u["model"]))
    }
}

/// A session row, as `/api/v1/.../sessions` and the extra routes give it.
public struct PanelSession: Equatable, Sendable {
    public var id: String
    public var cwd: String
    public var agent: String
    public var started: Date?
    public var ended: Date?
    public var events: Int
    public var usage: PanelUsage?
    public var name: String?
    public var isOpen: Bool { ended == nil }

    static func parse(_ row: [String: Any]) -> PanelSession {
        PanelSession(id: row["session_id"] as? String ?? "", cwd: row["cwd"] as? String ?? "", agent: row["agent_kind"] as? String ?? "",
                     started: PanelJSON.date(row["started_at"]), ended: PanelJSON.date(row["ended_at"]),
                     events: PanelJSON.int(row["observation_count"]), usage: PanelUsage.parse(row["usage"]), name: PanelJSON.text(row["display_name"]))
    }

    /// `{"sessions":[…]}` (the extra routes) or a bare array.
    public static func list(_ data: Data?) -> [PanelSession]? {
        if let rows = PanelJSON.object(data)?["sessions"] as? [[String: Any]] { return rows.map(parse) }
        return PanelJSON.array(data)?.map(parse)
    }
}

/// A page row of `pages` and `recent`.
public struct PanelPageRow: Equatable, Sendable {
    public var path: String
    public var title: String
    public var kind: String
    public var tier: String
    public var updated: Date?

    public static func list(_ data: Data?) -> [PanelPageRow]? {
        PanelJSON.array(data)?.map {
            PanelPageRow(path: $0["path"] as? String ?? "", title: $0["title"] as? String ?? "", kind: $0["kind"] as? String ?? "",
                         tier: $0["tier"] as? String ?? "", updated: PanelJSON.date($0["updated_at"]))
        }
    }
}

/// A message waiting in the project's mailbox.
public struct PanelMessage: Equatable, Sendable {
    public var subject: String?
    public var nature: String
    public var sender: String?
    public var snippet: String
    public var created: Date?
}

/// The project's `extra/.../summary`: its token total, its sessions per agent, its mailbox and the
/// agent that last wrote each page.
public struct PanelProjectSummary: Equatable, Sendable {
    public var tokens: PanelUsage?
    public var agents: [(agent: String, sessions: Int)]
    public var mailboxTotal: Int
    public var messages: [PanelMessage]
    public var pageAgents: [String: String]

    public static func parse(_ data: Data?) -> PanelProjectSummary? {
        guard let o = PanelJSON.object(data), o["error"] == nil else { return nil }
        let box = o["mailbox"] as? [String: Any] ?? [:]
        return PanelProjectSummary(
            tokens: PanelUsage.parse(o["tokens"]),
            agents: PanelJSON.rows(o["agents"]).map { ($0["agent"] as? String ?? "", PanelJSON.int($0["sessions"])) },
            mailboxTotal: PanelJSON.int(box["total"]),
            messages: PanelJSON.rows(box["messages"]).map {
                PanelMessage(subject: PanelJSON.text($0["subject"]), nature: $0["nature"] as? String ?? "", sender: PanelJSON.text($0["sender"]),
                             snippet: $0["snippet"] as? String ?? "", created: PanelJSON.date($0["created_at"]))
            },
            pageAgents: o["page_agents"] as? [String: String] ?? [:])
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.tokens == b.tokens && a.agents.map(\.agent) == b.agents.map(\.agent) && a.agents.map(\.sessions) == b.agents.map(\.sessions)
            && a.mailboxTotal == b.mailboxTotal && a.messages == b.messages && a.pageAgents == b.pageAgents
    }
}

/// An agent's card (the agents tab and the agent screen): upstream's `agent_card`.
public struct PanelAgentCard: Equatable, Sendable {
    public var agent: String
    public var sessions = 0, open = 0, measured = 0, coverage = 0, calls = 0
    public var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
    public var reported: Int { input + output + cacheRead + cacheWrite }

    static func parse(_ o: [String: Any]) -> PanelAgentCard {
        PanelAgentCard(agent: o["agent"] as? String ?? "", sessions: PanelJSON.int(o["sessions"]), open: PanelJSON.int(o["open"]),
                       measured: PanelJSON.int(o["measured_sessions"]), coverage: PanelJSON.int(o["coverage"]), calls: PanelJSON.int(o["calls"]),
                       input: PanelJSON.int(o["input"]), output: PanelJSON.int(o["output"]), cacheRead: PanelJSON.int(o["cache_read"]),
                       cacheWrite: PanelJSON.int(o["cache_write"]))
    }

    /// `{"agents":[card]}`.
    public static func list(_ data: Data?) -> [PanelAgentCard]? {
        (PanelJSON.object(data)?["agents"] as? [[String: Any]])?.map(parse)
    }
}

/// The agent screen's `extra/.../agents/{agent}`: its card, its sessions (50 a page) and whether
/// there are more.
public struct PanelAgentData: Equatable, Sendable {
    public var card: PanelAgentCard
    public var sessions: [PanelSession]
    public var more: Bool

    public static func parse(_ data: Data?) -> PanelAgentData? {
        guard let o = PanelJSON.object(data), let card = o["agent"] as? [String: Any] else { return nil }
        return PanelAgentData(card: .parse(card), sessions: PanelJSON.rows(o["sessions"]).map(PanelSession.parse), more: o["more"] as? Bool ?? false)
    }
}

/// One model response of the token usage panel.
public struct PanelTokenCall: Equatable, Sendable {
    public var session: String
    public var model: String
    public var input = 0, output = 0, cache = 0, total = 0
    public var signal: String?
}

/// The "Uso de tokens" box (`extra/.../tokens`, of the project or a session).
public struct PanelTokenReport: Equatable, Sendable {
    public var callCount = 0, matchingCalls = 0, matchingTokens = 0
    public var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
    public var offset = 0
    public var calls: [PanelTokenCall] = []
    public init() {}

    public static func parse(_ data: Data?) -> PanelTokenReport? {
        guard let o = PanelJSON.object(data), o["error"] == nil else { return nil }
        var r = PanelTokenReport()
        (r.callCount, r.matchingCalls, r.matchingTokens) = (PanelJSON.int(o["call_count"]), PanelJSON.int(o["matching_calls"]), PanelJSON.int(o["matching_tokens"]))
        (r.input, r.output, r.cacheRead, r.cacheWrite) = (PanelJSON.int(o["input"]), PanelJSON.int(o["output"]), PanelJSON.int(o["cache_read"]), PanelJSON.int(o["cache_write"]))
        r.offset = PanelJSON.int(o["offset"])
        r.calls = PanelJSON.rows(o["calls"]).map {
            PanelTokenCall(session: $0["session_id"] as? String ?? "", model: $0["model"] as? String ?? "", input: PanelJSON.int($0["input"]),
                           output: PanelJSON.int($0["output"]), cache: PanelJSON.int($0["cache_read"]) + PanelJSON.int($0["cache_write"]),
                           total: PanelJSON.int($0["total"]), signal: PanelJSON.text($0["signal"]))
        }
        return r
    }
}
