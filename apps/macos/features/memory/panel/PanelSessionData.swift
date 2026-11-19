import Foundation
import Strings

/// A session's screens' data (plan 40 D): its timeline (`api/v1/.../sessions/{id}/observations`,
/// 50 a page) and its retrievals (`extra/.../sessions/{id}/retrievals`, 25 a page).

/// One captured observation.
public struct PanelObservation: Equatable, Sendable {
    public var kind: String
    public var title: String
    public var body: String
    public var created: Date?
}

public struct PanelTimeline: Equatable, Sendable {
    public var session: PanelSession
    public var observations: [PanelObservation]
    public var total: Int
    public var offset: Int
    public var limit: Int
    /// What this session left in another project (upstream's "elided_other_scope").
    public var elsewhere: Int

    public static let pageSize = 50

    public static func parse(_ data: Data?) -> PanelTimeline? {
        guard let o = PanelJSON.object(data), let s = o["session"] as? [String: Any] else { return nil }
        return PanelTimeline(session: .parse(s), observations: PanelJSON.rows(o["observations"]).map {
            PanelObservation(kind: $0["kind"] as? String ?? "", title: $0["title"] as? String ?? "", body: $0["body"] as? String ?? "",
                             created: PanelJSON.date($0["created_at"]))
        }, total: PanelJSON.int(o["total"]), offset: PanelJSON.int(o["offset"]), limit: max(1, PanelJSON.int(o["limit"])),
           elsewhere: PanelJSON.int(o["elided_other_scope"]))
    }

    public var pager: PanelPager { PanelPager(offset: offset, limit: limit, total: total) }
}

/// A search the agent ran in this session, and what it found.
public struct PanelRetrieval: Equatable, Sendable {
    public var created: Date?
    public var query: String
    public var scope: String
    public var limit: Int
    public var durationMicros: Int
    public var resultCount: Int
    public var notice: String?
    public var hits: [(position: Int, path: String)]

    public static func == (a: Self, b: Self) -> Bool {
        a.created == b.created && a.query == b.query && a.scope == b.scope && a.resultCount == b.resultCount && a.hits.map(\.path) == b.hits.map(\.path)
    }
}

public struct PanelRetrievals: Equatable, Sendable {
    public var total: Int
    public var offset: Int
    public var limit: Int
    public var records: [PanelRetrieval]

    public static func parse(_ data: Data?) -> PanelRetrievals? {
        guard let o = PanelJSON.object(data), o["records"] != nil else { return nil }
        return PanelRetrievals(total: PanelJSON.int(o["total"]), offset: PanelJSON.int(o["offset"]), limit: max(1, PanelJSON.int(o["limit"])),
                               records: PanelJSON.rows(o["records"]).map { r in
            PanelRetrieval(created: PanelJSON.date(r["created_at"]), query: r["query"] as? String ?? "", scope: r["scope_kind"] as? String ?? "",
                           limit: PanelJSON.int(r["result_limit"]), durationMicros: PanelJSON.int(r["duration_us"]),
                           resultCount: PanelJSON.int(r["result_count"]), notice: PanelJSON.text(r["notice"]),
                           hits: PanelJSON.rows(r["hits"]).map { (PanelJSON.int($0["position"]), $0["page_path"] as? String ?? "") })
        })
    }
}

/// The page bar (« Primeira ‹ Anterior 1–50 de 882 Próxima › Última », "Ir para"): the offsets each
/// button goes to, nil when it would go nowhere.
public struct PanelPager: Equatable, Sendable {
    public var offset: Int
    public var limit: Int
    public var total: Int

    public var range: String {
        guard total > 0 else { return T("0 of 0", "0 de 0") }
        let last = min(offset + limit, total)
        return T("\(PanelWords.number(offset + 1))–\(PanelWords.number(last)) of \(PanelWords.number(total))",
                 "\(PanelWords.number(offset + 1))–\(PanelWords.number(last)) de \(PanelWords.number(total))")
    }

    public var first: Int? { offset > 0 ? 0 : nil }
    public var previous: Int? { offset > 0 ? max(0, offset - limit) : nil }
    public var next: Int? { offset + limit < total ? offset + limit : nil }
    public var last: Int? { offset + limit < total ? lastOffset : nil }
    public var lastOffset: Int { total == 0 ? 0 : ((total - 1) / limit) * limit }
    public var page: Int { offset / limit + 1 }
    public var pages: Int { max(1, (total + limit - 1) / limit) }

    /// "Ir para" observation `n` (1-based, held inside the total): the page that has it.
    public func offset(ofItem n: Int) -> Int { total == 0 ? 0 : ((min(max(n, 1), total) - 1) / limit) * limit }
}
