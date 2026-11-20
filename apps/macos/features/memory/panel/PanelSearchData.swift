import Foundation
import Strings

/// A search of the Memória page (plan 40 E, MemorySearch.dc.html): the words, the project it is
/// in (nil: every project), the kind and tier filters and "Explicar classificação". It is the
/// place's value: memory.show-panel carries it, back and forward keep it.
public struct PanelSearchQuery: Hashable, Sendable {
    public var words: String
    public var scope: PanelProjectRef?
    public var kind: String
    public var tier: String
    public var explain: Bool

    public init(words: String = "", scope: PanelProjectRef? = nil, kind: String = "", tier: String = "", explain: Bool = false) {
        self.words = words.trimmingCharacters(in: .whitespaces)
        self.scope = scope
        self.kind = kind
        self.tier = tier
        self.explain = explain
    }

    /// The engine's route (`extra/search`, docs/spec/memory.md), only the parts that are set.
    public var path: String {
        var parts: [String] = []
        if !words.isEmpty { parts.append("q=" + PanelPath.value(words)) }
        if let scope { parts.append("scope=" + PanelPath.value(scope.workspace + "/" + scope.name)) }
        if !kind.isEmpty { parts.append("kind=" + PanelPath.value(kind)) }
        if !tier.isEmpty { parts.append("tier=" + PanelPath.value(tier)) }
        if explain { parts.append("explain=1") }
        return "extra/search" + (parts.isEmpty ? "" : "?" + parts.joined(separator: "&"))
    }

    /// memory.show-panel's arguments: `section=search`, and the parts that are set.
    public var arguments: [String: String] {
        var out = ["section": "search"]
        if !words.isEmpty { out["query"] = words }
        if let scope { out["scope"] = scope.workspace + "/" + scope.name }
        if !kind.isEmpty { out["kind"] = kind }
        if !tier.isEmpty { out["tier"] = tier }
        if explain { out["explain"] = "1" }
        return out
    }

    /// The search memory.show-panel's arguments name (`scope` is "workspace/project" or a name).
    public init(arguments a: [String: String]) {
        let scope: PanelProjectRef? = a["scope"].flatMap { raw in
            let parts = raw.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { return PanelProjectRef(workspace: parts[0], name: parts[1]) }
            return raw.isEmpty ? nil : PanelProjectRef(name: raw)
        }
        self.init(words: a["query"] ?? "", scope: scope, kind: a["kind"] ?? "", tier: a["tier"] ?? "", explain: a["explain"] == "1")
    }
}

/// One stream's line in "Rastro da recuperação": rank, raw score and RRF share, as upstream prints them.
public struct PanelStreamRow: Equatable, Sendable {
    public var stream, rank, raw, rrf: String
}

/// How a hit ranked (upstream's `HitTrace`): its position and numbers, then the streams.
public struct PanelHitTrace: Equatable, Sendable {
    public var position = 0
    public var rank = "", fused = "", authority = ""
    public var intentBoost: String?
    public var rerank: String?
    public var streams: [PanelStreamRow] = []
    public var entities = ""
    public var via: String?

    /// "#1 · rank -0.02049 · fused 0.01639 · authority 1.2500", the line over the table.
    public var line: String {
        var out = "#\(position) · " + T("rank", "rank") + " \(rank) · " + T("fused", "fundido") + " \(fused) · " + T("authority", "autoridade") + " \(authority)"
        if let intentBoost { out += " · " + T("intent boost", "reforço de intenção") + " \(intentBoost)" }
        if let rerank { out += " · rerank \(rerank)" }
        return out
    }
}

/// A result: the page, where it lives, the snippet (the match marked) and, explained, its trace.
public struct PanelHit: Equatable, Sendable {
    public var project: PanelProjectRef
    public var path: String
    public var title: String
    public var snippet: PanelMarked
    public var trace: PanelHitTrace?
}

/// What `extra/search` answered.
public struct PanelSearchResult: Equatable, Sendable {
    public var query = PanelSearchQuery()
    public var hits: [PanelHit] = []
    public var truncated = false
    public var maxResults = 0
    public var filtered = false
    public var unknownKind = ""
    public var kinds: [String] = []
    public var tiers: [String] = []
    /// The selector's projects, by workspace and name.
    public var scopes: [PanelProjectRef] = []
    public var streams = ""
    public var embedder = ""
    public var reranker = ""
    public var timings: [(stream: String, ms: String)] = []

    public static func == (a: PanelSearchResult, b: PanelSearchResult) -> Bool {
        a.query == b.query && a.hits == b.hits && a.truncated == b.truncated && a.scopes == b.scopes && a.streams == b.streams
            && a.timings.map(\.stream) == b.timings.map(\.stream)
    }

    /// No words: the newest pages are listed instead.
    public var isRecent: Bool { query.words.isEmpty }

    /// "34 resultados", "primeiros 50 resultados", "1 resultado".
    public var countLine: String {
        if truncated { return T("first \(maxResults) results", "primeiros \(maxResults) resultados") }
        return hits.count == 1 ? T("1 result", "1 resultado") : T("\(hits.count) results", "\(PanelWords.number(hits.count)) resultados")
    }

    public static func parse(_ data: Data?) -> PanelSearchResult? {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let rows = o["hits"] as? [[String: Any]] else { return nil }
        var r = PanelSearchResult()
        let ws = o["workspace"] as? String ?? "", project = o["project"] as? String ?? ""
        r.query = PanelSearchQuery(words: o["query"] as? String ?? "", scope: project.isEmpty ? nil : PanelProjectRef(workspace: ws, name: project),
                                   kind: o["kind"] as? String ?? "", tier: o["tier"] as? String ?? "", explain: o["explain"] as? Bool ?? false)
        r.hits = rows.map { h in
            PanelHit(project: PanelProjectRef(workspace: h["workspace"] as? String ?? "default", name: h["project"] as? String ?? ""),
                     path: h["path"] as? String ?? "", title: h["title"] as? String ?? "",
                     snippet: PanelMarked(html: h["snippet"] as? String ?? ""), trace: (h["trace"] as? [String: Any]).map(trace))
        }
        r.truncated = o["truncated"] as? Bool ?? false
        r.maxResults = PanelOverviewData.int(o["max_results"])
        r.filtered = o["filtered"] as? Bool ?? false
        r.unknownKind = o["unknown_kind"] as? String ?? ""
        r.kinds = o["kinds"] as? [String] ?? []
        r.tiers = o["tiers"] as? [String] ?? []
        r.scopes = (o["scopes"] as? [[String: Any]] ?? []).flatMap { g in
            (g["projects"] as? [String] ?? []).map { PanelProjectRef(workspace: g["workspace"] as? String ?? "default", name: $0) }
        }
        r.streams = o["streams_active"] as? String ?? ""
        r.embedder = o["embedder"] as? String ?? ""
        r.reranker = o["reranker"] as? String ?? ""
        r.timings = (o["timings"] as? [[String: Any]] ?? []).map { ($0["stream"] as? String ?? "", $0["ms"] as? String ?? "") }
        return r
    }

    private static func trace(_ t: [String: Any]) -> PanelHitTrace {
        PanelHitTrace(position: PanelOverviewData.int(t["position"]), rank: t["rank"] as? String ?? "", fused: t["fused"] as? String ?? "",
                      authority: t["authority"] as? String ?? "", intentBoost: t["intent_boost"] as? String, rerank: t["rerank_score"] as? String,
                      streams: (t["streams"] as? [[String: Any]] ?? []).map {
                          PanelStreamRow(stream: $0["stream"] as? String ?? "", rank: $0["rank"] as? String ?? "", raw: $0["raw"] as? String ?? "",
                                         rrf: $0["rrf"] as? String ?? "")
                      },
                      entities: t["matched_entities"] as? String ?? "", via: t["graph_via"] as? String)
    }
}

/// Text with the match marked (components.memoryPanel.search.hit): the engine's snippet (upstream's
/// HTML, `<mark>` around each match and the rest escaped) read into text and ranges; a title gets
/// the same marks where the query's words appear in it (the board marks both).
public struct PanelMarked: Equatable, Sendable {
    public var text: String
    /// The marked parts, as ranges of `text` in UTF-16 (NSAttributedString's unit).
    public var marks: [NSRange]

    public init(text: String, marks: [NSRange] = []) {
        self.text = text
        self.marks = marks
    }

    /// From upstream's snippet HTML; line breaks folded to spaces, so the snippet is one line (the board).
    public init(html: String) {
        var text = "", marks: [NSRange] = []
        var rest = Substring(html)
        while let open = rest.range(of: "<mark>") {
            text += Self.unescape(rest[..<open.lowerBound])
            let after = rest[open.upperBound...]
            guard let close = after.range(of: "</mark>") else { rest = after; break }
            let word = Self.unescape(after[..<close.lowerBound])
            marks.append(NSRange(location: (text as NSString).length, length: (word as NSString).length))
            text += word
            rest = after[close.upperBound...]
        }
        text += Self.unescape(rest)
        self.init(text: text, marks: marks)
        fold()
    }

    /// Runs of spaces (a snippet's blank lines) made one, the marks moved with the text.
    mutating func fold() {
        let units = Array(text.utf16)
        var kept: [UInt16] = []
        var map = [Int](repeating: 0, count: units.count + 1)
        for (i, u) in units.enumerated() {
            map[i] = kept.count
            if u == 32, kept.last == 32 { continue }
            kept.append(u)
        }
        map[units.count] = kept.count
        while kept.last == 32 { kept.removeLast() }
        text = String(utf16CodeUnits: kept, count: kept.count)
        marks = marks.map { NSRange(location: map[$0.location], length: map[NSMaxRange($0)] - map[$0.location]) }.filter { $0.length > 0 && NSMaxRange($0) <= kept.count }
    }

    static func unescape(_ s: Substring) -> String {
        let folded = s.replacingOccurrences(of: "\n", with: " ")
        return folded.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&amp;", with: "&")
    }

    /// `text` with each of the query's words marked where it appears, ignoring case and accents
    /// ("memoria" marks "memória", as FTS matches it); words under two letters mark nothing.
    public init(text: String, words: String) {
        let ns = text as NSString
        var marks: [NSRange] = []
        for word in words.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }) where word.count >= 2 {
            var from = 0
            while from < ns.length {
                let found = ns.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive], range: NSRange(location: from, length: ns.length - from))
                guard found.location != NSNotFound else { break }
                marks.append(found)
                from = found.location + found.length
            }
        }
        self.init(text: text, marks: Self.merged(marks))
    }

    /// Overlapping marks joined, in order.
    static func merged(_ marks: [NSRange]) -> [NSRange] {
        var out: [NSRange] = []
        for mark in marks.sorted(by: { $0.location < $1.location }) {
            if let last = out.last, mark.location <= last.location + last.length {
                out[out.count - 1] = NSUnionRange(last, mark)
            } else {
                out.append(mark)
            }
        }
        return out
    }
}
