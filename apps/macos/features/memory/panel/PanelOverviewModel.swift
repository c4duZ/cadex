import Foundation
import Strings

/// The order of the project cards (MemoryOverview.dc.html, "Ordenar"): upstream's `?sort=`.
public enum PanelSort: String, CaseIterable, Sendable {
    /// Upstream's own order, the list as the engine gives it.
    case standard, sessions, events, pages, open

    public var title: String {
        switch self {
        case .standard: T("Default", "Padrão")
        case .sessions: T("Sessions", "Sessões")
        case .events: T("Captured events", "Eventos capturados")
        case .pages: T("Compiled pages", "Páginas compiladas")
        case .open: T("Open sessions", "Sessões abertas")
        }
    }
}

/// Which projects show (upstream's select): all, with an open session, with messages waiting.
public enum PanelScope: String, CaseIterable, Sendable {
    case all, withOpen, withInbox

    public var title: String {
        switch self {
        case .all: T("All projects", "Todos os projetos")
        case .withOpen: T("With open sessions", "Com sessões abertas")
        case .withInbox: T("With queued messages", "Com mensagens na fila")
        }
    }
}

/// The overview's numbers and the cards it shows, from the data and the owner's choices. Pure, so
/// the sorting and filtering are tested without a window.
public struct PanelOverviewModel: Equatable, Sendable {
    public var data: PanelOverviewData
    public var sort: PanelSort = .standard
    public var scope: PanelScope = .all
    public var filter = ""

    public init(data: PanelOverviewData) { self.data = data }

    public var totalSessions: Int { data.projects.reduce(0) { $0 + $1.sessions } }
    public var totalEvents: Int { data.projects.reduce(0) { $0 + $1.events } }
    public var totalPages: Int { data.projects.reduce(0) { $0 + $1.pages } }
    public var totalOpen: Int { data.projects.reduce(0) { $0 + $1.open } }

    /// Upstream's "Última captura": the first last_activity of the list as it comes.
    public var lastCapture: Date? { data.projects.lazy.compactMap(\.lastActivity).first }

    /// The cards: filtered by the scope and the text (in the name), then sorted, most first; a tie
    /// keeps upstream's order (a stable sort).
    public var visible: [PanelProject] {
        let words = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let kept = data.projects.filter { project in
            switch scope {
            case .all: break
            case .withOpen: if project.open == 0 { return false }
            case .withInbox: if project.inbox == 0 { return false }
            }
            return words.isEmpty || project.name.lowercased().contains(words)
        }
        guard let key = sortKey else { return kept }
        return kept.enumerated().sorted { a, b in
            let (x, y) = (key(a.element), key(b.element))
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
    }

    private var sortKey: ((PanelProject) -> Int)? {
        switch sort {
        case .standard: nil
        case .sessions: { $0.sessions }
        case .events: { $0.events }
        case .pages: { $0.pages }
        case .open: { $0.open }
        }
    }

    /// Filtering hides some: "2 de 5"; nil when all show.
    public var shownOfTotal: String? {
        let shown = visible.count
        return shown == data.projects.count ? nil : T("\(shown) of \(data.projects.count)", "\(shown) de \(data.projects.count)")
    }

    /// A counter clicked (upstream's links): its order in the selector; Sessões abertas also keeps
    /// only the projects with one (`?sort=open&state=open`).
    public mutating func pick(_ counter: PanelSort) {
        sort = counter
        if counter == .open { scope = .withOpen }
    }
}

/// The overview's words: numbers, times and agents as upstream writes them in Portuguese.
public enum PanelWords {
    /// 86.023 in Portuguese, 86,023 in English.
    public static func number(_ value: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.locale = Locale(identifier: Strings.language == .pt ? "pt_BR" : "en_US")
        return format.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// "há 9 horas", "há 1 dia", "agora".
    public static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let (n, en, pt): (Int, String, String) = switch seconds {
        case ..<60: (0, "", "")
        case ..<3600: (seconds / 60, "minute", "minuto")
        case ..<86400: (seconds / 3600, "hour", "hora")
        case ..<(30 * 86400): (seconds / 86400, "day", "dia")
        case ..<(365 * 86400): (seconds / (30 * 86400), "month", "mês")
        default: (seconds / (365 * 86400), "year", "ano")
        }
        guard n > 0 else { return T("just now", "agora") }
        let ptPlural = pt == "mês" ? "meses" : pt + "s"
        return T("\(n) \(n == 1 ? en : en + "s") ago", "há \(n) \(n == 1 ? pt : ptPlural)")
    }

    /// "Última captura: há 9 horas", or "Nenhuma captura ainda".
    public static func lastCapture(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return T("No capture yet", "Nenhuma captura ainda") }
        return T("Last capture: ", "Última captura: ") + ago(date, now: now)
    }

    /// Upstream's agent labels ("claude-code" is "Claude Code"); none: "Nenhuma sessão de agente ainda".
    public static func agents(_ wire: [String]) -> String {
        guard !wire.isEmpty else { return T("No agent session yet", "Nenhuma sessão de agente ainda") }
        return wire.map { name in
            switch name {
            case "claude-code": "Claude Code"
            case "codex": "Codex"
            case "gemini": "Gemini"
            case "opencode": "OpenCode"
            default: name
            }
        }.joined(separator: " · ")
    }

    /// The card's two letters, the sidebar's rule (WorkProject.initials): "bkdg-center" BC,
    /// "_global" GL, "cadex" CA (the board's CX was by hand; one rule in the app).
    public static func mark(_ name: String) -> String {
        let parts = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if parts.count >= 2, let a = parts[0].first, let b = parts[1].first { return (String(a) + String(b)).uppercased() }
        let letters = name.filter { $0.isLetter || $0.isNumber }
        return letters.isEmpty ? "•" : String(letters.prefix(2)).uppercased()
    }

    /// "Captura: 0 aceitos · 0 descartados pela política · 0 por capacidade · 0 limitados por taxa".
    public static func capture(_ c: PanelCapture) -> String {
        T("Capture: \(number(c.accepted)) accepted · \(number(c.droppedByPolicy)) dropped by policy · \(number(c.shedSaturated)) at capacity · \(number(c.shedRateLimited)) rate limited",
          "Captura: \(number(c.accepted)) aceitos · \(number(c.droppedByPolicy)) descartados pela política · \(number(c.shedSaturated)) por capacidade · \(number(c.shedRateLimited)) limitados por taxa")
    }

    /// The amber notice: "2 mensagens aguardando agentes em cadex (2)".
    public static func inboxNotice(_ inbox: PanelInbox) -> String {
        let list = inbox.projects.prefix(5).map { "\($0.name) (\($0.pending))" }.joined(separator: ", ")
        return inbox.pending == 1 ? T("1 message waiting for agents in ", "1 mensagem aguardando agentes em ") + list
            : T("\(number(inbox.pending)) messages waiting for agents in ", "\(number(inbox.pending)) mensagens aguardando agentes em ") + list
    }

    /// Upstream's capture note, cut from the line into the ⓘ (screens-memory.md, MemoryOverview).
    public static var captureHelp: String {
        T("Open means no SessionEnd was received: an agent still working or an interruption. The counters hold only metadata; raw prompts and commands stay in the scope's detailed views.",
          "Aberta significa que nenhum SessionEnd foi recebido; pode ser um agente ativo ou uma interrupção. Os contadores contêm apenas metadados; prompts e comandos brutos permanecem nas visualizações detalhadas do escopo.")
    }
}
