import Foundation
import Strings

/// What the Memory page shows (plan 22 phase H), gathered by the app from
/// `cadex memory-agent` and the wiki folder; the texts made from it are
/// pure, so they are tested without a window.
public struct MemoryPageState: Sendable {
    /// memory.enabled: off, the page explains and offers to turn it on.
    public var enabled: Bool
    /// Nil until the overview answers, or when `cadex` could not run.
    public var overview: MemoryOverview?
    public var agent: MemoryAgentStatus?
    public var proposals: [MemoryProposal] = []
    public var wikiDir: String?
    public var tree: MemoryFolder?
    /// Why the agent's CLI did not answer, when it did not.
    public var problem: String?

    public init(enabled: Bool, overview: MemoryOverview? = nil, agent: MemoryAgentStatus? = nil, proposals: [MemoryProposal] = [],
                wikiDir: String? = nil, tree: MemoryFolder? = nil, problem: String? = nil) {
        self.enabled = enabled
        self.overview = overview
        self.agent = agent
        self.proposals = proposals
        self.wikiDir = wikiDir
        self.tree = tree
        self.problem = problem
    }

    /// The wiki folder: the overview's, else projects.json's for the root.
    public static func wikiDir(overview: MemoryOverview?, root: String, folder: String) -> String? {
        overview?.wikiDir ?? MemoryProjects.entry(root: root, folder: folder)?.wikiDir
    }
}

/// The status block's lines.
public enum MemoryStatusText {
    public static let offText = T("Project memory is off. Turned on, each agent session Cadex opens starts with what the earlier ones did in this project, and the wiki of decisions, gotchas and concepts shows here.",
                                  "A memória do projeto está desligada. Ligada, cada sessão de agente que o Cadex abre começa com o que as anteriores fizeram neste projeto, e a wiki de decisões, armadilhas e conceitos aparece aqui.")

    /// The engine and its vector model.
    public static func engine(_ overview: MemoryOverview?) -> String {
        guard let overview else { return T("Memory engine: unknown", "Engine da memória: desconhecido") }
        guard overview.running else {
            return T("Memory engine: not running (starts with the next agent session)", "Engine da memória: parado (sobe com a próxima sessão de agente)")
        }
        return T("Memory engine: running", "Engine da memória: rodando") + " · " + model(overview.model)
    }

    public static func model(_ state: String) -> String {
        switch state {
        case "off": T("semantic search off", "busca por sentido desligada")
        case "absent": T("model not downloaded", "modelo não baixado")
        case "downloading": T("downloading the model", "baixando o modelo")
        case "ready": T("model ready", "modelo pronto")
        case "loaded": T("model loaded", "modelo carregado")
        default: T("model: ", "modelo: ") + state
        }
    }

    /// "42 pages · 17 sessions".
    public static func counts(_ overview: MemoryOverview?) -> String? {
        guard let overview, overview.running else { return nil }
        return T("\(overview.pages) pages · \(overview.sessions) sessions", "\(overview.pages) páginas · \(overview.sessions) sessões")
    }

    /// "Imported 120 sessions: Personal (100), Work (20)".
    public static func imported(_ overview: MemoryOverview?, accountName: (String) -> String) -> String? {
        guard let overview, overview.running else { return nil }
        let accounts = overview.importedAccounts.map { "\(accountName($0.dir)) (\($0.sessions))" }.joined(separator: ", ")
        switch overview.importState {
        case "started": return T("Importing the history: \(overview.importedSessions) sessions so far", "Importando o histórico: \(overview.importedSessions) sessões até agora")
            + (accounts.isEmpty ? "" : " · " + accounts)
        case "done": return T("History imported: \(overview.importedSessions) sessions", "Histórico importado: \(overview.importedSessions) sessões")
            + (accounts.isEmpty ? "" : " · " + accounts)
        default: return T("History not imported yet", "Histórico ainda não importado")
        }
    }

    /// The memory agent: on or off, paused, spent today against the cap.
    public static func agent(_ status: MemoryAgentStatus?) -> String {
        guard let status, status.running else { return T("Memory agent: no answer (the engine is down)", "Agente de memória: sem resposta (o engine está parado)") }
        guard status.enabled else { return T("Memory agent: off", "Agente de memória: desligado") }
        let spent = "US$ " + usd(status.spentTodayUsd) + " / " + String(format: "%.2f", status.dailyBudgetUsd)
        let state = status.paused ? T("paused", "pausado") : T("on", "ligado")
        return T("Memory agent: \(state) · today \(spent)", "Agente de memória: \(state) · hoje \(spent)")
    }

    /// The queue's jobs, "consolidate · waiting".
    public static func queue(_ status: MemoryAgentStatus?) -> [String] {
        (status?.queue ?? []).prefix(5).map { [$0.kind, $0.state].filter { !$0.isEmpty }.joined(separator: " · ") }
    }

    /// A cost with the digits that matter: a Haiku job costs a fraction of
    /// a cent, which two decimals showed as 0.00 (snapshot, 2026-11-16).
    public static func usd(_ value: Double) -> String {
        if value == 0 || value >= 0.01 { return String(format: "%.2f", value) }
        return String(format: "%.4f", value)
    }

    /// The last runs with their cost, newest first: "dream · US$ 0.04 · 2h".
    public static func recent(_ status: MemoryAgentStatus?, now: Date = Date()) -> [String] {
        (status?.recent ?? []).sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }.prefix(3).map { run in
            [run.kind, "US$ " + usd(run.costUsd), run.at.map { MemoryJSON.ago($0, now: now) } ?? "",
             run.ok ? "" : T("failed", "falhou") + (run.error.map { ": " + $0 } ?? "")]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }

    /// A page's second line: "session a1b2c3d4 · Work · 3h".
    /// A page learned today as the Inspector mockup says it: "gotcha · from perf-subagent-window ·
    /// Claude", the kind, the task its session ran in, who wrote it.
    public static func learned(_ page: MemoryPage, place: String?) -> String {
        [page.kind, place.map { T("from ", "de ") + $0 }, page.agent.map(agentName)]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The agent as people say it: "claude-code" is Claude, "codex" Codex.
    static func agentName(_ agent: String) -> String {
        switch agent.lowercased() {
        case "claude-code", "claude": "Claude"
        case "codex": "Codex"
        default: agent
        }
    }

    public static func origin(_ page: MemoryPage, account: String?, now: Date = Date()) -> String {
        [page.sessionID.map { T("session ", "sessão ") + MemoryWiki.shortID($0) }, account ?? page.agent,
         page.time.map { MemoryJSON.ago($0, now: now) }]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
