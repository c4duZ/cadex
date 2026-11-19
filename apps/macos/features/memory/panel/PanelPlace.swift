import Foundation
import Strings

/// A project of the memory as the routes name it: its workspace and its name (plan 40 D).
public struct PanelProjectRef: Hashable, Sendable {
    public var workspace: String
    public var name: String
    public init(workspace: String = "default", name: String) {
        self.workspace = workspace
        self.name = name
    }

    /// `api/v1/workspaces/default/projects/cadex`, each part escaped.
    public var api: String { "api/v1/workspaces/\(PanelPath.segment(workspace))/projects/\(PanelPath.segment(name))" }
    /// `extra/workspaces/default/projects/cadex`.
    public var extra: String { "extra/workspaces/\(PanelPath.segment(workspace))/projects/\(PanelPath.segment(name))" }
}

/// The project screen's tabs, upstream's order (MemoryProject.dc.html).
public enum PanelProjectTab: String, CaseIterable, Sendable {
    case overview, agents, tokens, sessions, knowledge

    public var title: String {
        switch self {
        case .overview: T("Overview", "Visão geral")
        case .agents: T("Agents", "Agentes")
        case .tokens: T("Token usage", "Uso de tokens")
        case .sessions: T("Sessions", "Sessões")
        case .knowledge: T("Knowledge", "Conhecimento")
        }
    }
}

/// Where the Memória page is: a section of the sidebar, or one of a project's screens (upstream's
/// /w/{ws}/{project}, its pages, history, sessions, retrievals and agents). Inside a project the
/// sidebar keeps Projetos lit, as upstream does.
public enum PanelPlace: Hashable, Sendable {
    case section(MemoryPanelSection)
    case project(PanelProjectRef, PanelProjectTab)
    case page(PanelProjectRef, String)
    /// A page's history; `from` and `to` are version ids (nil: upstream's default pair).
    case history(PanelProjectRef, String, from: String?, to: String?)
    /// A session's timeline from `offset` (50 a page).
    case session(PanelProjectRef, String, offset: Int)
    /// A session's retrievals from `offset` (25 a page).
    case retrievals(PanelProjectRef, String, offset: Int)
    case agent(PanelProjectRef, String)

    public var section: MemoryPanelSection {
        if case .section(let section) = self { return section }
        return .projects
    }

    public var project: PanelProjectRef? {
        switch self {
        case .section: nil
        case .project(let p, _), .page(let p, _), .history(let p, _, _, _), .session(let p, _, _), .retrievals(let p, _, _), .agent(let p, _): p
        }
    }

    /// memory.show-panel's arguments for this place, so every click runs the command (ADR 0005).
    public var arguments: [String: String] {
        guard let project else { return ["section": section.rawValue] }
        var out = ["project": project.name]
        if project.workspace != "default" { out["workspace"] = project.workspace }
        switch self {
        case .section: break
        case .project(_, let tab): out["tab"] = tab.rawValue
        case .page(_, let path): out["page"] = path
        case .history(_, let path, let from, let to):
            out["history"] = path
            out["from"] = from
            out["to"] = to
        case .session(_, let id, let offset):
            out["session"] = id
            if offset > 0 { out["offset"] = String(offset) }
        case .retrievals(_, let id, let offset):
            out["retrievals"] = id
            if offset > 0 { out["offset"] = String(offset) }
        case .agent(_, let wire): out["agent"] = wire
        }
        return out
    }

    /// The place memory.show-panel's arguments name; nil when they name none.
    public init?(arguments a: [String: String]) {
        guard let name = a["project"], !name.isEmpty else {
            guard let section = MemoryPanelSection(rawValue: a["section"] ?? "projects") else { return nil }
            self = .section(section)
            return
        }
        let project = PanelProjectRef(workspace: a["workspace"] ?? "default", name: name)
        if let path = a["page"] { self = .page(project, path) }
        else if let path = a["history"] { self = .history(project, path, from: a["from"], to: a["to"]) }
        else if let id = a["session"] { self = .session(project, id, offset: Int(a["offset"] ?? "") ?? 0) }
        else if let id = a["retrievals"] { self = .retrievals(project, id, offset: Int(a["offset"] ?? "") ?? 0) }
        else if let wire = a["agent"] { self = .agent(project, wire) }
        else if let tab = PanelProjectTab(rawValue: a["tab"] ?? "overview") { self = .project(project, tab) }
        else { return nil }
    }

    /// The trail above the title (the boards): "Projetos › cadex › …", the workspace only when it is
    /// not "default"; each crumb but the last goes somewhere.
    public var crumbs: [PanelCrumb] {
        guard let p = project else { return [] }
        var out = [PanelCrumb(T("Projects", "Projetos"), .section(.projects))]
        if p.workspace != "default" { out.append(PanelCrumb(p.workspace, nil)) }
        let home = PanelCrumb(p.name, .project(p, .overview))
        switch self {
        case .section: return []
        case .project: return out + [PanelCrumb(p.name, nil)]
        case .page(_, let path): return out + [home, PanelCrumb(path, nil)]
        case .history(_, let path, _, _): return out + [home, PanelCrumb(path, .page(p, path)), PanelCrumb(T("history", "histórico"), nil)]
        case .session(_, let id, _): return out + [home, PanelCrumb(PanelWords.sessionCrumb(id), nil)]
        case .retrievals(_, let id, _):
            return out + [home, PanelCrumb(PanelWords.sessionCrumb(id), .session(p, id, offset: 0)), PanelCrumb(T("retrievals", "recuperações"), nil)]
        case .agent(_, let wire): return out + [home, PanelCrumb(PanelWords.agents([wire]), nil)]
        }
    }
}

/// A piece of the trail: its words and where a click goes (nil: the current one, or the workspace).
public struct PanelCrumb: Equatable, Sendable {
    public var title: String
    public var place: PanelPlace?
    public init(_ title: String, _ place: PanelPlace?) {
        self.title = title
        self.place = place
    }
}

/// Back and forward within the page, as a browser keeps them.
public struct PanelTrail: Equatable, Sendable {
    public private(set) var back: [PanelPlace] = []
    public private(set) var current: PanelPlace = .section(.projects)
    public private(set) var forward: [PanelPlace] = []
    public init() {}

    /// A new place: the one before goes back, and what was ahead is gone. The same place twice is one.
    public mutating func go(_ place: PanelPlace) {
        guard place != current else { return }
        back.append(current)
        current = place
        forward.removeAll()
    }

    public mutating func goBack() -> PanelPlace? {
        guard let previous = back.popLast() else { return nil }
        forward.append(current)
        current = previous
        return previous
    }

    public mutating func goForward() -> PanelPlace? {
        guard let next = forward.popLast() else { return nil }
        back.append(current)
        current = next
        return next
    }
}

/// The routes' path pieces, escaped as a URL path wants them.
public enum PanelPath {
    static let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))

    public static func segment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// A page path ("decisions/engine.md"), each segment escaped, the slashes kept.
    public static func page(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false).map { segment(String($0)) }.joined(separator: "/")
    }

    /// A query value.
    public static func value(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? text
    }
}
