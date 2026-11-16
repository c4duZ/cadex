import Foundation

/// What `cadex memory-agent overview` says of a project (plan 22 phase H):
/// never starts the engine; down, only `running` is false.
public struct MemoryOverview: Equatable, Sendable {
    public struct Account: Equatable, Sendable {
        public var dir: String
        public var sessions: Int
    }

    public var running = false
    public var workspace = ""
    public var project = ""
    public var wikiDir: String?
    /// off, absent, downloading, ready or loaded: the vector model.
    public var model = ""
    public var pages = 0
    public var sessions = 0
    /// none, started or done: the import of the history of the accounts.
    public var importState = "none"
    public var importedSessions = 0
    public var importedAccounts: [Account] = []

    public init() {}

    public static func parse(_ json: [String: Any]) -> MemoryOverview {
        var o = MemoryOverview()
        o.running = json["running"] as? Bool ?? false
        o.workspace = json["workspace"] as? String ?? ""
        o.project = json["project"] as? String ?? ""
        o.wikiDir = (json["wiki_dir"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        o.model = json["model"] as? String ?? ""
        o.pages = MemoryJSON.int(json["pages"])
        o.sessions = MemoryJSON.int(json["sessions"])
        if let imported = json["imported"] as? [String: Any] {
            o.importState = imported["state"] as? String ?? "none"
            o.importedSessions = MemoryJSON.int(imported["sessions"])
            o.importedAccounts = (imported["accounts"] as? [[String: Any]] ?? []).compactMap { a in
                (a["dir"] as? String).map { Account(dir: $0, sessions: MemoryJSON.int(a["sessions"])) }
            }
        }
        return o
    }
}

/// What `cadex memory-agent status` says of the memory agent (ADR 0029).
public struct MemoryAgentStatus: Equatable, Sendable {
    public struct Job: Equatable, Sendable {
        public var kind: String
        public var project: String
        public var state: String
    }

    public struct Run: Equatable, Sendable {
        public var at: Date?
        public var kind: String
        public var project: String
        public var costUsd: Double
        public var ok: Bool
        public var error: String?
    }

    /// False when the engine is down (`{"running":false}`): nothing else is known.
    public var running = false
    public var enabled = false
    public var paused = false
    public var spentTodayUsd = 0.0
    public var dailyBudgetUsd = 0.0
    public var queue: [Job] = []
    public var recent: [Run] = []
    public var proposalsPending = 0
    public var claudeVersion: String?

    public init() {}

    public static func parse(_ json: [String: Any]) -> MemoryAgentStatus {
        var s = MemoryAgentStatus()
        guard json["running"] as? Bool != false, json["enabled"] != nil else { return s }
        s.running = true
        s.enabled = json["enabled"] as? Bool ?? false
        s.paused = json["paused"] as? Bool ?? false
        s.spentTodayUsd = MemoryJSON.double(json["spent_today_usd"])
        s.dailyBudgetUsd = MemoryJSON.double(json["daily_budget_usd"])
        s.queue = (json["queue"] as? [[String: Any]] ?? []).map {
            Job(kind: $0["kind"] as? String ?? "", project: $0["project"] as? String ?? "", state: $0["state"] as? String ?? "")
        }
        s.recent = (json["recent"] as? [[String: Any]] ?? []).map {
            Run(at: MemoryJSON.date($0["at"]), kind: $0["kind"] as? String ?? "", project: $0["project"] as? String ?? "",
                costUsd: MemoryJSON.double($0["cost_usd"]), ok: $0["ok"] as? Bool ?? false,
                error: ($0["error"] as? String).flatMap { $0.isEmpty ? nil : $0 })
        }
        s.proposalsPending = MemoryJSON.int(json["proposals_pending"])
        s.claudeVersion = json["claude_version"] as? String
        return s
    }
}

/// A change the memory agent proposed, waiting for the owner (ADR 0029).
public struct MemoryProposal: Equatable, Sendable {
    public var id: String
    public var title: String
    public var path: String
    public var kind: String
    public var summary: String
    public var createdAt: Date?
    public var body: String

    public init(id: String, title: String, path: String = "", kind: String = "", summary: String = "", createdAt: Date? = nil, body: String = "") {
        self.id = id
        self.title = title
        self.path = path
        self.kind = kind
        self.summary = summary
        self.createdAt = createdAt
        self.body = body
    }

    /// `{"proposals":[…]}`; one without an id is skipped (nothing to approve).
    public static func parseList(_ json: [String: Any]) -> [MemoryProposal] {
        (json["proposals"] as? [[String: Any]] ?? []).compactMap { p in
            guard let id = (p["id"] as? String) ?? (p["id"] as? NSNumber)?.stringValue, !id.isEmpty else { return nil }
            let path = p["path"] as? String ?? ""
            let title = (p["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (path.isEmpty ? id : path)
            return MemoryProposal(id: id, title: title, path: path, kind: p["kind"] as? String ?? "", summary: p["summary"] as? String ?? "",
                                  createdAt: MemoryJSON.date(p["created_at"]), body: p["body"] as? String ?? "")
        }
    }

    /// The first lines of the body, for the page.
    public var preview: String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: true).prefix(3)
        let text = lines.joined(separator: " ")
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }
}

/// `<memory>/projects.json`, written by the engine: the projects it knows,
/// so the page shows the wiki with the engine down.
public enum MemoryProjects {
    public struct Entry: Equatable, Sendable {
        public var workspace: String
        public var project: String
        public var root: String
        public var wikiDir: String
    }

    public nonisolated static func read(folder: String) -> [Entry] {
        guard let data = FileManager.default.contents(atPath: folder + "/projects.json"),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return (json["projects"] as? [[String: Any]] ?? []).compactMap { p in
            guard let root = p["root"] as? String, let wiki = p["wiki_dir"] as? String, !wiki.isEmpty else { return nil }
            return Entry(workspace: p["workspace"] as? String ?? "", project: p["project"] as? String ?? "", root: root, wikiDir: wiki)
        }
    }

    /// The project's entry: the same root, or the same key (the engine may
    /// keep the key as `project`).
    public nonisolated static func entry(root: String, folder: String) -> Entry? {
        let entries = read(folder: folder)
        let key = MemoryProject.key(root: root)
        return entries.first { $0.root == root } ?? entries.first { $0.project == key }
    }

    /// The entry whose wiki holds `path` (a page saved in the editor).
    public nonisolated static func entry(holding path: String, folder: String) -> Entry? {
        read(folder: folder).first { path.hasPrefix($0.wikiDir.hasSuffix("/") ? $0.wikiDir : $0.wikiDir + "/") }
    }
}

/// Lenient readers for the CLI's JSON: numbers may come as Int or Double,
/// times as RFC 3339 text or seconds.
enum MemoryJSON {
    static func int(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? Int(value as? String ?? "") ?? 0 }
    static func double(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "") ?? 0 }

    static func date(_ value: Any?) -> Date? {
        if let seconds = value as? NSNumber { return Date(timeIntervalSince1970: seconds.doubleValue > 1e12 ? seconds.doubleValue / 1000 : seconds.doubleValue) }
        guard let text = value as? String, !text.isEmpty else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// "3m", "2h", "5d": how long ago, as History shows it.
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
