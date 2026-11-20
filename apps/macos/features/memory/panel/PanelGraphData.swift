import Foundation
import Strings

/// A node of the link graph (plan 40 E, MemoryGraph.dc.html): a page of the project, or in the
/// general graph a project that has a link to or from another one.
public struct PanelGraphNode: Equatable, Sendable {
    public var title: String
    /// The page's path; empty for a project node.
    public var path: String
    public var project: PanelProjectRef
    /// The page's kind ("decision", "rule"…), "project" for a project node; colors the dot.
    public var kind: String
    public var tier: String

    /// What the tip and VoiceOver say: the title and where it lives.
    public var place: String { path.isEmpty ? project.workspace + "/" + project.name : path }
}

/// One line of CONEXÕES: from a page to a page, each one a link.
public struct PanelConnection: Equatable, Sendable {
    public var from: PanelGraphEnd
    public var to: PanelGraphEnd
}

public struct PanelGraphEnd: Equatable, Sendable {
    public var project: PanelProjectRef
    public var path: String
    /// "decisions/engine.md" in a project; "site:deploy.md" across projects.
    public var label: String
}

/// The graph a screen draws: the nodes, the links as index pairs, and the connections listed.
public struct PanelGraph: Equatable, Sendable {
    /// The project of a project's graph; nil for the general one.
    public var project: PanelProjectRef?
    public var nodes: [PanelGraphNode] = []
    public var edges: [PanelEdge] = []
    public var connections: [PanelConnection] = []
    /// Cut at the engine's node cap (120).
    public var truncated = false

    public struct PanelEdge: Equatable, Sendable {
        public var from: Int
        public var to: Int
    }

    /// "cadex", or "acct/cadex" outside the default workspace (the trail's rule).
    public static func name(_ p: PanelProjectRef) -> String { p.workspace == "default" ? p.name : p.workspace + "/" + p.name }

    /// Nodes with no link: drawn dimmer, at the edge.
    public var loose: Set<Int> {
        var linked = Set<Int>()
        for e in edges { linked.insert(e.from); linked.insert(e.to) }
        return Set(nodes.indices).subtracting(linked)
    }

    /// The kinds drawn, in the legend's order (by count, then name).
    public var kinds: [String] {
        var count: [String: Int] = [:]
        for n in nodes { count[n.kind, default: 0] += 1 }
        return count.keys.sorted { (count[$0]!, $1) > (count[$1]!, $0) }
    }

    /// A project's graph: upstream's `/graph` (nodes, edges, truncated) with the kind and tier of
    /// each page from `/pages`, which may be missing (the dots then all "other").
    public static func parse(project ref: PanelProjectRef, graph: Data?, pages: Data?) -> PanelGraph? {
        guard let graph, let o = (try? JSONSerialization.jsonObject(with: graph)) as? [String: Any], let rows = o["nodes"] as? [[String: Any]] else { return nil }
        var meta: [String: (String, String)] = [:]
        for p in (pages.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [[String: Any]]) ?? [] {
            meta[p["path"] as? String ?? ""] = (p["kind"] as? String ?? "", p["tier"] as? String ?? "")
        }
        var out = PanelGraph(project: ref, truncated: o["truncated"] as? Bool ?? false)
        out.nodes = rows.map { row in
            let path = row["path"] as? String ?? ""
            let (kind, tier) = meta[path] ?? ("", "")
            return PanelGraphNode(title: row["title"] as? String ?? path, path: path, project: ref, kind: kind.isEmpty ? "other" : kind, tier: tier)
        }
        let index = Dictionary(out.nodes.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { a, _ in a })
        for edge in o["edges"] as? [[String: Any]] ?? [] {
            let from = edge["from_path"] as? String ?? "", to = edge["to_path"] as? String ?? ""
            out.connections.append(PanelConnection(from: PanelGraphEnd(project: ref, path: from, label: from), to: PanelGraphEnd(project: ref, path: to, label: to)))
            // Upstream draws a line only when both ends are among the nodes and differ.
            if let a = index[from], let b = index[to], a != b { out.edges.append(PanelEdge(from: a, to: b)) }
        }
        return out
    }

    /// The general graph: upstream's `/api/v1/graph` edges between projects. A node per project
    /// (by workspace, then name, as upstream's `aggregate_projects`), a line per pair; every edge
    /// listed in CONEXÕES as "site:deploy.md → cadex:decisions/engine.md".
    public static func parse(global data: Data?) -> PanelGraph? {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let rows = o["edges"] as? [[String: Any]] else { return nil }
        var out = PanelGraph()
        let ends: [(PanelGraphEnd, PanelGraphEnd)] = rows.map { e in
            func end(_ side: String) -> PanelGraphEnd {
                let p = PanelProjectRef(workspace: e[side + "_workspace"] as? String ?? "default", name: e[side + "_project"] as? String ?? "")
                let path = e[side + "_path"] as? String ?? ""
                return PanelGraphEnd(project: p, path: path, label: name(p) + ":" + path)
            }
            return (end("from"), end("to"))
        }
        let projects = Set(ends.flatMap { [$0.0.project, $0.1.project] }).sorted { ($0.workspace, $0.name) < ($1.workspace, $1.name) }
        out.nodes = projects.map { PanelGraphNode(title: name($0), path: "", project: $0, kind: "project", tier: "") }
        let index = Dictionary(uniqueKeysWithValues: projects.enumerated().map { ($1, $0) })
        var drawn = Set<[Int]>()
        for (from, to) in ends {
            out.connections.append(PanelConnection(from: from, to: to))
            guard let a = index[from.project], let b = index[to.project], a != b, drawn.insert([min(a, b), max(a, b)]).inserted else { continue }
            out.edges.append(PanelEdge(from: a, to: b))
        }
        return out
    }

    /// The line under the title: "5 páginas mais recentes · 3 links entre elas" (a project), "Links
    /// entre projetos" (the general one).
    public var summary: String {
        guard project != nil else { return T("Links between projects", "Links entre projetos") }
        let pages = nodes.count == 1 ? T("1 most recent page", "1 página mais recente") : T("\(nodes.count) most recent pages", "\(PanelWords.number(nodes.count)) páginas mais recentes")
        let links = connections.count == 1 ? T("1 link between them", "1 link entre elas") : T("\(connections.count) links between them", "\(PanelWords.number(connections.count)) links entre elas")
        return pages + " · " + links
    }

    /// With nothing linked, why, in one line (the owner's real memory has no links yet).
    public var emptyLine: String? {
        if project == nil {
            return connections.isEmpty ? T("No links between projects yet: a page links another project's with [[project:path]].",
                                          "Ainda não há links entre projetos: uma página liga a de outro com [[projeto:caminho]].") : nil
        }
        if nodes.isEmpty { return T("No pages in this project yet.", "Ainda não há páginas neste projeto.") }
        return connections.isEmpty ? T("No links between these pages: none cites another with [[path]].",
                                       "Nenhum link entre estas páginas: nenhuma cita outra com [[caminho]].") : nil
    }
}
