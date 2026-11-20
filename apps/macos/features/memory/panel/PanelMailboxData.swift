import Foundation
import Strings

/// Which mailbox the Caixa de entrada shows (plan 40 F, upstream's /inbox query): a project's (nil:
/// the engine picks the first with mail waiting), received or sent, the state filter (nil: the
/// default, waiting mail in Recebidas and every state in Enviadas; "" every state) and the page.
/// `compose` puts the keys in Nova mensagem ("Enviar mensagem a um agente").
public struct PanelMailboxQuery: Hashable, Sendable {
    public var project: PanelProjectRef?
    public var outbox = false
    public var state: String?
    public var offset = 0
    public var compose = false

    public init(project: PanelProjectRef? = nil, outbox: Bool = false, state: String? = nil, offset: Int = 0, compose: Bool = false) {
        (self.project, self.outbox, self.state, self.offset, self.compose) = (project, outbox, state, offset, compose)
    }

    /// Upstream's states, in its selector's order ("" first: every state).
    public static let states = ["", "pending", "claimed", "cancelled", "editing"]
    public static let pageSize = 50

    /// `extra/inbox?workspace=default&project=cadex&box=outbox&state=&offset=50`.
    public var path: String {
        var pairs: [String] = []
        if let project { pairs += ["workspace=" + PanelPath.value(project.workspace), "project=" + PanelPath.value(project.name)] }
        if outbox { pairs.append("box=outbox") }
        if let state { pairs.append("state=" + PanelPath.value(state)) }
        if offset > 0 { pairs.append("offset=\(offset)") }
        return "extra/inbox" + (pairs.isEmpty ? "" : "?" + pairs.joined(separator: "&"))
    }

    /// memory.show-panel's arguments: `section=inbox [scope=<w/p>] [box=outbox] [state=<s|all>] [offset=n] [compose=1]`.
    public var arguments: [String: String] {
        var out = ["section": "inbox"]
        if let project { out["scope"] = project.workspace + "/" + project.name }
        if outbox { out["box"] = "outbox" }
        if let state { out["state"] = state.isEmpty ? "all" : state }
        if offset > 0 { out["offset"] = String(offset) }
        if compose { out["compose"] = "1" }
        return out
    }

    public init(arguments a: [String: String]) {
        project = a["scope"].flatMap(PanelSearchQuery.scope(from:))
        outbox = a["box"] == "outbox"
        state = a["state"].map { $0 == "all" ? "" : $0 }
        offset = Int(a["offset"] ?? "") ?? 0
        compose = a["compose"] == "1"
    }

    /// Upstream's names of the states, in the selector and on a message's chip.
    public static func stateTitle(_ state: String) -> String {
        switch state {
        case "": T("All messages", "Todas as mensagens")
        case "pending": T("Awaiting collection", "Aguardando coleta")
        case "claimed": T("Collected", "Coletadas")
        case "cancelled": T("Cancelled", "Canceladas")
        case "editing": T("Editing", "Em edição")
        default: state
        }
    }

    /// A message's chip: upstream's English "Queued", "Collected"…; its Portuguese common-status words.
    public static func chipTitle(_ state: String) -> String {
        switch state {
        case "pending": T("Queued", "pendente")
        case "claimed": T("Collected", "coletada")
        case "cancelled": T("Cancelled", "cancelada")
        case "editing": T("Editing", "em edição")
        default: state
        }
    }
}

/// A message of the mailbox, as extra/inbox gives it.
public struct PanelMail: Equatable, Sendable {
    public var id: String
    public var subject: String?
    public var body: String
    /// "default / cadex", or nil for a project the engine cannot name.
    public var from: String?
    public var to: String?
    public var fromAgent: String
    public var toAgent: String?
    public var state: String
    public var created: Date?

    /// The subject, or upstream's "Mensagem sem título".
    public var title: String { subject ?? T("Untitled message", "Mensagem sem título") }
    /// "default / cadex → default / site", upstream's words for one it cannot read.
    public var route: String {
        let unknown = T("A project you cannot read", "Um projeto que você não pode ler")
        return (from ?? unknown) + " → " + (to ?? unknown)
    }
    /// The recipient: the agent's name, or upstream's "Qualquer agente do projeto".
    public var agent: String { toAgent.map { PanelWords.agents([$0]) } ?? T("Any project agent", "Qualquer agente do projeto") }
}

/// A recipient of Nova mensagem: an agent with a session in a project (upstream's registered agents).
public struct PanelRecipient: Equatable, Sendable {
    public var project: PanelProjectRef
    public var agent: String
}

/// What extra/inbox gives: the mailbox shown, the queue over every project, the projects for the
/// selectors, the held count, the recipients and one page of messages.
public struct PanelMailbox: Equatable, Sendable {
    public var query: PanelMailboxQuery
    /// The mailbox the engine shows (the first with mail waiting when the query named none).
    public var project: PanelProjectRef?
    public var pendingTotal = 0
    public var pendingProjects = 0
    public var scopes: [(project: PanelProjectRef, pending: Int)] = []
    public var editing = 0
    public var recipients: [PanelRecipient] = []
    public var more = false
    public var messages: [PanelMail] = []

    public static func == (a: PanelMailbox, b: PanelMailbox) -> Bool {
        a.query == b.query && a.project == b.project && a.pendingTotal == b.pendingTotal && a.messages == b.messages
            && a.scopes.map(\.project) == b.scopes.map(\.project) && a.scopes.map(\.pending) == b.scopes.map(\.pending)
            && a.editing == b.editing && a.recipients == b.recipients && a.more == b.more
    }

    /// The projects with mail waiting, in the list's order.
    public var waiting: [(project: PanelProjectRef, pending: Int)] { scopes.filter { $0.pending > 0 } }
    /// The state the engine filtered by: nil is every state.
    public var state: String? { query.state ?? (query.outbox ? nil : "pending") }

    public static func parse(_ data: Data?, query: PanelMailboxQuery) -> PanelMailbox? {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], o["messages"] != nil else { return nil }
        let int = PanelOverviewData.int
        var box = PanelMailbox(query: query)
        let ws = o["workspace"] as? String ?? "", name = o["project"] as? String ?? ""
        box.project = name.isEmpty ? nil : PanelProjectRef(workspace: ws, name: name)
        box.pendingTotal = int(o["pending_total"])
        box.pendingProjects = int(o["pending_projects"])
        box.scopes = (o["scopes"] as? [[String: Any]] ?? []).map {
            (PanelProjectRef(workspace: $0["workspace"] as? String ?? "default", name: $0["project"] as? String ?? ""), int($0["pending"]))
        }
        box.editing = int(o["editing_count"])
        box.recipients = (o["recipients"] as? [[String: Any]] ?? []).map {
            PanelRecipient(project: PanelProjectRef(workspace: $0["workspace"] as? String ?? "default", name: $0["project"] as? String ?? ""),
                           agent: $0["agent"] as? String ?? "")
        }
        box.more = o["more"] as? Bool ?? false
        box.messages = (o["messages"] as? [[String: Any]] ?? []).map { m in
            PanelMail(id: m["id"] as? String ?? "", subject: m["subject"] as? String, body: m["body"] as? String ?? "",
                         from: m["from"] as? String, to: m["to"] as? String, fromAgent: m["from_agent"] as? String ?? "",
                         toAgent: m["to_agent"] as? String, state: m["state"] as? String ?? "", created: PanelOverviewData.date(m["created_at"]))
        }
        return box
    }

    /// "Nenhuma mensagem aguardando agentes", or "2 na fila · 1 projeto".
    public var queueLine: String {
        guard pendingTotal > 0 else { return T("No messages waiting for agents", "Nenhuma mensagem aguardando agentes") }
        let projects = pendingProjects == 1 ? T("1 project", "1 projeto") : T("\(pendingProjects) projects", "\(pendingProjects) projetos")
        return T("\(pendingTotal) queued · ", "\(pendingTotal) na fila · ") + projects
    }

    /// The empty mailbox's line, upstream's three.
    public var emptyLine: String {
        if state != nil { return T("No messages in this state.", "Nenhuma mensagem neste estado.") }
        return query.outbox ? T("No messages sent from this project yet.", "Nenhuma mensagem enviada por este projeto ainda.")
            : T("No messages received by this project yet.", "Nenhuma mensagem recebida por este projeto ainda.")
    }

    /// Upstream's banner while messages are held: "1 mensagem retida para edição."
    public var heldLine: String {
        editing == 1 ? T("1 message held for editing.", "1 mensagem retida para edição.")
            : T("\(editing) messages held for editing.", "\(editing) mensagens retidas para edição.")
    }

    /// The agents registered in `project`, for Para o agente.
    public func agents(in project: PanelProjectRef) -> [String] { recipients.filter { $0.project == project }.map(\.agent) }
}

/// A managed workstream (plan 40 F, extra/workstreams), upstream's row.
public struct PanelWorkstream: Equatable, Sendable {
    public var id: String
    public var name: String
    public var project: PanelProjectRef
    public var status: String
    public var latestRun: String?
    public var latestAgent: String?
    public var events: Int
    public var harnesses: [String]
    public var lastActive: Date?
    public var started: Date?
    public var ended: Date?

    /// Upstream's English labels; in Portuguese its common-status words.
    public var statusTitle: String {
        switch status {
        case "active": T("Active", "ativo")
        case "interrupted": T("Interrupted", "interrompido")
        case "completed": T("Completed", "concluído")
        case "empty": T("Empty", "vazio")
        default: status
        }
    }
}

/// One page of the workstreams, 100 a page (upstream's).
public struct PanelWorkstreams: Equatable, Sendable {
    public var page = 1
    public var hasNext = false
    public var rows: [PanelWorkstream] = []

    public static func parse(_ data: Data?) -> PanelWorkstreams? {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let list = o["workstreams"] as? [[String: Any]] else { return nil }
        let date = PanelOverviewData.date
        return PanelWorkstreams(page: max(1, PanelOverviewData.int(o["page"])), hasNext: o["has_next"] as? Bool ?? false, rows: list.map { w in
            PanelWorkstream(id: w["id"] as? String ?? "", name: w["name"] as? String ?? "",
                            project: PanelProjectRef(workspace: w["workspace"] as? String ?? "default", name: w["project"] as? String ?? ""),
                            status: w["status"] as? String ?? "", latestRun: w["latest_run_id"] as? String, latestAgent: w["latest_agent"] as? String,
                            events: PanelOverviewData.int(w["event_count"]), harnesses: w["linked_harnesses"] as? [String] ?? [],
                            lastActive: date(w["last_active_at"]), started: date(w["latest_started_at"]), ended: date(w["latest_ended_at"]))
        })
    }
}
