import Foundation
import Strings

/// The review's filter and order (plan 40 G, upstream's /pending query): a project or all, and one of
/// upstream's four orders.
public struct PanelReviewQuery: Hashable, Sendable {
    public var project: PanelProjectRef?
    public var sort = "project"

    public init(project: PanelProjectRef? = nil, sort: String = "project") {
        self.project = project
        self.sort = Self.sorts.contains(sort) ? sort : "project"
    }

    public static let sorts = ["project", "confidence-asc", "confidence-desc", "staged-desc"]

    /// Upstream's names of the orders.
    public static func sortTitle(_ sort: String) -> String {
        switch sort {
        case "confidence-asc": T("Confidence, low first", "Confiança, menor primeiro")
        case "confidence-desc": T("Confidence, high first", "Confiança, maior primeiro")
        case "staged-desc": T("Staged, newest first", "Envio, mais recentes primeiro")
        default: T("Project, then staged date", "Projeto e depois data de envio")
        }
    }

    /// `extra/review?project=default/cadex&sort=confidence-desc`.
    public var path: String {
        var pairs: [String] = []
        if let project { pairs.append("project=" + PanelPath.value(project.workspace + "/" + project.name)) }
        if sort != "project" { pairs.append("sort=" + sort) }
        return "extra/review" + (pairs.isEmpty ? "" : "?" + pairs.joined(separator: "&"))
    }

    /// memory.show-panel's arguments: `section=review [scope=<w/p>] [sort=<order>]`.
    public var arguments: [String: String] {
        var out = ["section": "review"]
        if let project { out["scope"] = project.workspace + "/" + project.name }
        if sort != "project" { out["sort"] = sort }
        return out
    }

    public init(arguments a: [String: String]) {
        self.init(project: a["scope"].flatMap(PanelSearchQuery.scope(from:)), sort: a["sort"] ?? "project")
    }
}

/// A proposal waiting for the owner, as extra/review gives it.
public struct PanelProposal: Equatable, Sendable {
    public var id: String
    public var title: String
    public var path: String
    public var kind: String
    public var rationale: String
    public var body: String
    public var staged: Date?
    public var project: PanelProjectRef
    public var operation: String
    public var confidence: Double
    public var isRule: Bool
    public var rewrites: Bool
    public var editMode: String

    /// "confiança 80%".
    public var confidenceLine: String { T("confidence ", "confiança ") + "\(Int((confidence * 100).rounded()))%" }
}

/// What extra/review gives: the pending proposals of every project (or one), in the order asked.
public struct PanelReview: Equatable, Sendable {
    public var query: PanelReviewQuery
    public var total = 0
    public var projectCount = 0
    public var truncated = false
    public var scopes: [(project: PanelProjectRef, pending: Int)] = []
    public var proposals: [PanelProposal] = []

    public static func == (a: PanelReview, b: PanelReview) -> Bool {
        a.query == b.query && a.total == b.total && a.projectCount == b.projectCount && a.truncated == b.truncated
            && a.scopes.map(\.project) == b.scopes.map(\.project) && a.scopes.map(\.pending) == b.scopes.map(\.pending) && a.proposals == b.proposals
    }

    public static func parse(_ data: Data?, query: PanelReviewQuery) -> PanelReview? {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let list = o["proposals"] as? [[String: Any]] else { return nil }
        let int = PanelOverviewData.int
        let ref = { (row: [String: Any]) in PanelProjectRef(workspace: row["workspace"] as? String ?? "default", name: row["project"] as? String ?? "") }
        var review = PanelReview(query: query, total: int(o["total"]), projectCount: int(o["project_count"]), truncated: o["truncated"] as? Bool ?? false)
        review.scopes = (o["scopes"] as? [[String: Any]] ?? []).map { (ref($0), int($0["pending"])) }
        review.proposals = list.map { p in
            PanelProposal(id: p["id"] as? String ?? "", title: p["title"] as? String ?? "", path: p["path"] as? String ?? "", kind: p["kind"] as? String ?? "",
                          rationale: p["summary"] as? String ?? "", body: p["body"] as? String ?? "", staged: PanelOverviewData.date(p["created_at"]),
                          project: ref(p), operation: p["operation"] as? String ?? "", confidence: (p["confidence"] as? NSNumber)?.doubleValue ?? 0,
                          isRule: p["is_rule"] as? Bool ?? false, rewrites: p["rewrites_existing"] as? Bool ?? false, editMode: p["edit_mode"] as? String ?? "")
        }
        return review
    }

    /// The project selector's lines: "Todos os projetos (3)", then "cadex (2)"…
    public var projectTitles: [String] {
        [T("All projects (\(total))", "Todos os projetos (\(total))")] + scopes.map { "\(PanelGraph.name($0.project)) (\($0.pending))" }
    }

    /// "3 exibidas · 3 pendentes em 2 projetos".
    public var countLine: String {
        let projects = projectCount == 1 ? T("project", "projeto") : T("projects", "projetos")
        return T("\(proposals.count) shown · \(total) pending in \(projectCount) \(projects)",
                 "\(proposals.count) exibidas · \(total) pendentes em \(projectCount) \(projects)")
    }
}
