import Foundation

/// A page's screens' data (plan 40 D): the page (`api/v1/.../pages/{path}`), its evidence and
/// metadata (`extra/.../evidence/{path}`) and its history with the diff (`api/v1/.../history/{path}`).

/// A page another one links to or from.
public struct PanelPageLink: Equatable, Sendable {
    public var path: String
    public var title: String
    public var project: String
}

public struct PanelPageDetail: Equatable, Sendable {
    public var id: String
    public var path: String
    public var title: String
    public var kind: String
    public var tier: String
    public var pinned: Bool
    public var created: Date?
    public var updated: Date?
    public var supersedes: String?
    public var body: String
    public var links: [PanelPageLink]
    public var backlinks: [PanelPageLink]

    public static func parse(_ data: Data?) -> PanelPageDetail? {
        guard let o = PanelJSON.object(data), let path = o["path"] as? String else { return nil }
        func links(_ key: String) -> [PanelPageLink] {
            PanelJSON.rows(o[key]).map {
                PanelPageLink(path: $0["path"] as? String ?? "", title: $0["title"] as? String ?? "", project: $0["project"] as? String ?? "")
            }
        }
        return PanelPageDetail(id: o["id"] as? String ?? "", path: path, title: o["title"] as? String ?? path, kind: o["kind"] as? String ?? "",
                               tier: o["tier"] as? String ?? "", pinned: o["pinned"] as? Bool ?? false, created: PanelJSON.date(o["created_at"]),
                               updated: PanelJSON.date(o["updated_at"]), supersedes: PanelJSON.text(o["supersedes"]),
                               body: o["body_markdown"] as? String ?? "", links: links("links"), backlinks: links("backlinks"))
    }
}

/// The "Evidências e validade" box and what only `page_meta` has (author, expiry).
public struct PanelEvidence: Equatable, Sendable {
    public var author: String?
    public var expires: Date?
    public var expired = false
    public var version = ""
    public var sources: [(kind: String, created: Date?)] = []
    public var sourceCount = 0
    public var contradictions: [(path: String, title: String, outgoing: Bool)] = []
    public var contradictionCount = 0
    public init() {}

    public static func parse(_ data: Data?) -> PanelEvidence? {
        guard let o = PanelJSON.object(data), let e = o["evidence"] as? [String: Any] else { return nil }
        let meta = o["meta"] as? [String: Any] ?? [:]
        var out = PanelEvidence()
        out.author = PanelJSON.text(meta["author"])
        out.expires = PanelJSON.date(meta["expires_at"])
        out.expired = meta["expired"] as? Bool ?? false
        out.version = e["version"] as? String ?? ""
        out.sources = PanelJSON.rows(e["sources"]).map { ($0["kind"] as? String ?? "", PanelJSON.date($0["created_at"])) }
        out.sourceCount = PanelJSON.int(e["source_count"])
        out.contradictions = PanelJSON.rows(e["disagreements"]).map {
            let page = $0["page"] as? [String: Any] ?? [:]
            return (page["path"] as? String ?? "", page["title"] as? String ?? "", $0["outgoing"] as? Bool ?? false)
        }
        out.contradictionCount = PanelJSON.int(e["disagreement_count"])
        return out
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.author == b.author && a.expires == b.expires && a.expired == b.expired && a.version == b.version && a.sourceCount == b.sourceCount
            && a.contradictionCount == b.contradictionCount && a.sources.map(\.kind) == b.sources.map(\.kind)
            && a.contradictions.map(\.path) == b.contradictions.map(\.path)
    }
}

/// One version of a page's history.
public struct PanelVersion: Equatable, Sendable {
    public var id: String
    public var supersedes: String?
    public var isLatest: Bool
    public var title: String
    public var created: Date?
    public var chars: Int
}

/// One line of the unified diff, as the history draws it.
public enum PanelDiffLine: Equatable, Sendable {
    case hunk(String)
    case same(String)
    case add(String)
    case del(String)
}

/// What the diff says: its lines, or the one sentence in their place.
public enum PanelDiffState: Equatable, Sendable {
    case lines([PanelDiffLine], truncated: Bool)
    case same
    case tooLarge(String)
}

public struct PanelHistory: Equatable, Sendable {
    public var path: String
    public var total: Int
    public var offset: Int
    public var limit: Int
    public var versions: [PanelVersion]
    public var from: String?
    public var to: String
    public var toTitle: String
    public var diff: PanelDiffState

    public static func parse(_ data: Data?) -> PanelHistory? {
        guard let o = PanelJSON.object(data), let d = o["diff"] as? [String: Any], let to = d["to"] as? [String: Any] else { return nil }
        let versions = PanelJSON.rows(o["versions"]).map {
            PanelVersion(id: $0["id"] as? String ?? "", supersedes: PanelJSON.text($0["supersedes"]), isLatest: $0["is_latest"] as? Bool ?? false,
                         title: $0["title"] as? String ?? "", created: PanelJSON.date($0["created_at"]), chars: PanelJSON.int($0["body_chars"]))
        }
        let state: PanelDiffState = switch d["status"] as? String {
        case "same": .same
        case "too_large": .tooLarge(d["reason"] as? String ?? "")
        default: .lines(lines(PanelJSON.rows(d["hunks"])), truncated: d["truncated"] as? Bool ?? false)
        }
        return PanelHistory(path: o["path"] as? String ?? "", total: PanelJSON.int(o["total"]), offset: PanelJSON.int(o["offset"]),
                            limit: PanelJSON.int(o["limit"]), versions: versions, from: (d["from"] as? [String: Any])?["id"] as? String,
                            to: to["id"] as? String ?? "", toTitle: to["title"] as? String ?? "", diff: state)
    }

    /// The hunks as lines: "@@ -0,0 +1,7 @@" over each, then its lines by their op.
    static func lines(_ hunks: [[String: Any]]) -> [PanelDiffLine] {
        hunks.flatMap { h -> [PanelDiffLine] in
            let head = PanelDiffLine.hunk("@@ -\(PanelJSON.int(h["old_start"])),\(PanelJSON.int(h["old_len"])) +\(PanelJSON.int(h["new_start"])),\(PanelJSON.int(h["new_len"])) @@")
            return [head] + PanelJSON.rows(h["lines"]).map { line in
                let text = line["text"] as? String ?? ""
                switch line["op"] as? String {
                case "+": return .add(text)
                case "-": return .del(text)
                default: return .same(text)
                }
            }
        }
    }

    /// The version `id` is, as its short form ("5ef7d2d8", the last 8 of the id as upstream shows).
    public static func short(_ id: String) -> String { String(id.suffix(8)) }
}
