import Foundation

/// The Memória page's data (plan 40 C), read from the engine's panel routes (docs/spec/memory.md,
/// "Os dados do painel Memória") through `cadex memory-agent panel --path P`. Only reads.

/// One project of the overview: upstream's `/api/v1/projects` row, with what only its HTML shows
/// (the agents and the inbox count, from `extra/home`).
public struct PanelProject: Equatable, Sendable {
    public var workspace: String
    public var name: String
    public var sessions: Int
    public var events: Int
    public var pages: Int
    public var open: Int
    /// The last event captured; nil: nothing captured yet.
    public var lastActivity: Date?
    /// Upstream's wire names ("claude-code", "codex"), in its order.
    public var agents: [String]
    public var inbox: Int

    public init(workspace: String = "default", name: String, sessions: Int = 0, events: Int = 0, pages: Int = 0, open: Int = 0,
                lastActivity: Date? = nil, agents: [String] = [], inbox: Int = 0) {
        self.workspace = workspace
        self.name = name
        self.sessions = sessions
        self.events = events
        self.pages = pages
        self.open = open
        self.lastActivity = lastActivity
        self.agents = agents
        self.inbox = inbox
    }

    /// The key a project goes by in the routes and the commands: "default/cadex".
    public var key: String { workspace + "/" + name }
    /// The project as the routes and the places name it.
    public var ref: PanelProjectRef { PanelProjectRef(workspace: workspace, name: name) }
}

/// Upstream's "hook capture health" block, from the local engine's counters since it started.
public struct PanelCapture: Equatable, Sendable {
    public var accepted = 0
    public var droppedByPolicy = 0
    public var shedSaturated = 0
    public var shedRateLimited = 0
    public init(accepted: Int = 0, droppedByPolicy: Int = 0, shedSaturated: Int = 0, shedRateLimited: Int = 0) {
        self.accepted = accepted
        self.droppedByPolicy = droppedByPolicy
        self.shedSaturated = shedSaturated
        self.shedRateLimited = shedRateLimited
    }
}

/// The messages waiting, as upstream's notifications say them (the five busiest projects).
public struct PanelInbox: Equatable, Sendable {
    public var pending = 0
    public var projects: [(name: String, pending: Int)] = []
    public init(pending: Int = 0, projects: [(name: String, pending: Int)] = []) {
        self.pending = pending
        self.projects = projects
    }
    public static func == (a: PanelInbox, b: PanelInbox) -> Bool {
        a.pending == b.pending && a.projects.map(\.name) == b.projects.map(\.name) && a.projects.map(\.pending) == b.projects.map(\.pending)
    }
}

/// The three reads of the overview, put together.
public struct PanelOverviewData: Equatable, Sendable {
    public var projects: [PanelProject]
    public var capture: PanelCapture
    public var inbox: PanelInbox

    public init(projects: [PanelProject], capture: PanelCapture = PanelCapture(), inbox: PanelInbox = PanelInbox()) {
        self.projects = projects
        self.capture = capture
        self.inbox = inbox
    }

    /// The routes the overview reads, in the order `parse` takes their answers.
    public static let paths = ["api/v1/projects", "extra/home", "extra/inbox/notifications"]

    /// `api/v1/projects` (an array), `extra/home` and `extra/inbox/notifications`; nil when the
    /// projects do not read (an error answer is an object). The other two may be missing.
    public static func parse(projects: Data, home: Data?, notifications: Data?) -> PanelOverviewData? {
        guard let rows = (try? JSONSerialization.jsonObject(with: projects)) as? [[String: Any]] else { return nil }
        let homeJSON = home.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        var extras: [String: [String: Any]] = [:]
        for row in homeJSON["projects"] as? [[String: Any]] ?? [] {
            extras[(row["workspace"] as? String ?? "") + "/" + (row["project"] as? String ?? "")] = row
        }
        let list = rows.map { row -> PanelProject in
            var project = PanelProject(workspace: row["workspace_name"] as? String ?? "default", name: row["project_name"] as? String ?? "",
                                       sessions: int(row["session_count"]), events: int(row["observation_count"]),
                                       pages: int(row["page_count"]), open: int(row["open_session_count"]),
                                       lastActivity: date(row["last_activity"]))
            let extra = extras[project.key] ?? [:]
            project.agents = extra["agents"] as? [String] ?? []
            project.inbox = int(extra["pending_inbox"])
            return project
        }
        let c = homeJSON["capture"] as? [String: Any] ?? [:]
        let capture = PanelCapture(accepted: int(c["accepted"]), droppedByPolicy: int(c["dropped_by_policy"]),
                                   shedSaturated: int(c["shed_saturated"]), shedRateLimited: int(c["shed_rate_limited"]))
        let n = notifications.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
        let inbox = PanelInbox(pending: int(n["pending"]),
                               projects: (n["projects"] as? [[String: Any]] ?? []).map { ($0["project"] as? String ?? "", int($0["pending"])) })
        return PanelOverviewData(projects: list, capture: capture, inbox: inbox)
    }

    /// What an error answer says (`{"error":"…"}`), or the bytes as text.
    public static func errorText(_ data: Data) -> String {
        if let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let error = object["error"] as? String { return error }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }

    /// Upstream's RFC 3339 with microseconds ("2026-11-19T22:43:36.212394Z").
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// The upstream the engine is built from, beside the lit Memória row (MemorySidebar.dc.html). The
/// engine pins it in core/features/memory/server/Cargo.toml (commit 411d90d, release 3.5.0): a
/// pin there that moves changes this line with it.
public enum MemoryPanelInfo {
    public static let upstream = "ai-memory 3.5.0"
}
