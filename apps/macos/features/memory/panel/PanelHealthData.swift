import Foundation
import Strings

/// The engine's health (plan 40 G, extra/health): upstream's checks and sections, this Mac's
/// cadex-memory as the server (the owner, 2026-11-19). The words are upstream's (its web.ftl, in
/// English and Portuguese), rebuilt from the numbers, since the engine says its checks in English.
public struct PanelHealth: Equatable, Sendable {
    public struct Check: Equatable, Sendable {
        public var id: String
        public var error: Bool
        public var words: String
        /// The Cadex action that fixes it (memory.fix-health's `what`), or nil.
        public var fix: String?
        /// What fixes it when no button does (the run journal: the next `cadex continue`).
        public var note: String?
    }

    public struct Row: Equatable, Sendable {
        public var name: String
        public var value: String
    }

    public struct Section: Equatable, Sendable {
        public var title: String
        public var rows: [Row]
    }

    public var checks: [Check] = []
    /// Upstream's five, in its order: hooks, writer, consolidation, models, index.
    public var sections: [Section] = []

    /// memory.fix-health's choices, upstream's fix lines done by the engine.
    public static let fixes = ["spool", "embed", "embed-all", "compact"]

    /// The button of a fix.
    public static func fixTitle(_ what: String) -> String {
        switch what {
        case "spool": T("Send the queue again", "Reenviar a fila")
        case "embed": T("Make the missing vectors", "Gerar os vetores que faltam")
        case "embed-all": T("Make every vector again", "Refazer todos os vetores")
        default: T("Compact the database", "Compactar o banco")
        }
    }

    public static func parse(_ data: Data?, now: Date = Date()) -> PanelHealth? {
        guard let data, let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], o["checks"] != nil else { return nil }
        let n = { (object: Any?, key: String) in PanelOverviewData.int((object as? [String: Any])?[key]) }
        let hooks = o["hooks"], queue = o["write_queue"], spool = o["spool"] as? [String: Any], journal = o["journal"] as? [String: Any]
        let consolidation = o["consolidation"], derived = o["derived"] as? [String: Any] ?? [:], storage = o["storage"] as? [String: Any]
        let never = T("never", "nunca")
        func when(_ value: Any?, scale: Double) -> String {
            guard let number = value as? NSNumber else { return never }
            return PanelWords.ago(Date(timeIntervalSince1970: number.doubleValue / scale), now: now)
        }
        func age(_ ms: Any?) -> String { (ms as? NSNumber).map { "\($0.intValue / 60_000) min" } ?? T("age unknown", "idade desconhecida") }
        var out = PanelHealth()
        for check in o["checks"] as? [[String: Any]] ?? [] {
            let id = check["id"] as? String ?? ""
            let detail = check["detail"] as? String ?? id
            let words = Self.words(id, detail: detail, hooks: hooks, queue: queue, spool: spool, journal: journal, derived: derived, storage: storage,
                                   consolidation: consolidation, age: age) ?? detail
            let fix: String? = switch id {
            case "spool_evicting", "spool_pending": "spool"
            case "missing_vectors": "embed"
            case "stale_vectors": "embed-all"
            case "storage_reclaim": "compact"
            default: nil
            }
            let note = id.hasPrefix("journal_") ? T("The next session continued in another agent (cadex continue) replays it.",
                                                    "A próxima sessão continuada em outro agente (cadex continue) refaz o registro.") : nil
            out.checks.append(Check(id: id, error: check["status"] as? String == "error", words: words, fix: fix, note: note))
        }
        let row = { (name: String, value: String) in Row(name: name, value: value) }
        out.sections.append(Section(title: T("Hooks (since the server started)", "Hooks (desde o início do servidor)"), rows: [
            row(T("accepted", "aceitos"), "\(n(hooks, "accepted"))"),
            row(T("shed (429)", "rejeitados (429)"), T("\(n(hooks, "shed_saturated") + n(hooks, "shed_rate_limited")) (\(n(hooks, "shed_saturated")) saturated, \(n(hooks, "shed_rate_limited")) rate-limited)",
                                                     "\(n(hooks, "shed_saturated") + n(hooks, "shed_rate_limited")) (\(n(hooks, "shed_saturated")) por saturação, \(n(hooks, "shed_rate_limited")) por limite de taxa)")),
            row(T("outcomes", "resultados"), T("\(n(hooks, "stored")) stored, \(n(hooks, "replayed")) replayed, \(n(hooks, "resumed")) resumed, \(n(hooks, "ignored_end")) ignored end, \(n(hooks, "failed")) failed",
                                              "\(n(hooks, "stored")) armazenados, \(n(hooks, "replayed")) reproduzidos, \(n(hooks, "resumed")) retomados, \(n(hooks, "ignored_end")) encerramentos ignorados, \(n(hooks, "failed")) falhas")),
            row(T("dropped", "descartados"), T("\(n(hooks, "dropped_by_policy")) capture policy, \(n(hooks, "dropped_unauthorized")) unauthorized, \(n(hooks, "dropped_collision")) collision, \(n(hooks, "dropped_invalid")) invalid",
                                              "\(n(hooks, "dropped_by_policy")) pela política de captura, \(n(hooks, "dropped_unauthorized")) não autorizados, \(n(hooks, "dropped_collision")) colisões, \(n(hooks, "dropped_invalid")) inválidos")),
            row(T("last write", "última gravação"), when((hooks as? [String: Any])?["last_persisted_ms"], scale: 1_000)),
        ]))
        let spoolLine = spool.map { s in
            let pending = PanelOverviewData.int(s["pending"])
            return T("\(pending) queued", "\(pending) na fila") + (pending > 0 ? T(" (oldest \(age(s["oldest_age_ms"])))", " (mais antigo \(age(s["oldest_age_ms"])))") : "")
        } ?? T("not visible to this server", "não visível para este servidor")
        let journalLine = journal.map { j in
            (j["unreadable"] as? Bool ?? false) ? T("unreadable", "ilegível")
                : T("\(n(j, "pending")) pending (\(n(j, "degraded")) degraded, \(n(j, "finish_failed")) finish-failed)",
                    "\(n(j, "pending")) pendentes (\(n(j, "degraded")) degradadas, \(n(j, "finish_failed")) com falha no encerramento)")
        } ?? T("not visible to this server", "não visível para este servidor")
        out.sections.append(Section(title: T("Writer, spool and recovery", "Gravação, spool e recuperação"), rows: [
            row(T("write queue", "fila de gravação"), queue == nil ? T("unknown", "desconhecido") : "\(n(queue, "queued"))/\(n(queue, "capacity"))"),
            row(T("hook spool", "spool de hooks"), spoolLine), row(T("recovery journal", "registro de recuperação"), journalLine),
        ]))
        let c = consolidation as? [String: Any]
        out.sections.append(Section(title: T("Consolidation", "Consolidação"), rows: [
            row(T("last completed", "última conclusão"), when(c?["last_completed_at_us"], scale: 1_000_000)),
            row(T("queue", "fila"), T("\(n(c, "pending")) pending, \(n(c, "running")) running, \(n(c, "completed")) completed, \(n(c, "failed")) failed",
                                      "\(n(c, "pending")) pendentes, \(n(c, "running")) em execução, \(n(c, "completed")) concluídas, \(n(c, "failed")) com falha")),
            row(T("oldest pending", "pendente mais antigo"), when(c?["oldest_pending_requested_at_us"], scale: 1_000_000)),
        ]))
        out.sections.append(Section(title: T("Embedder and models", "Embeddings e modelos"), rows: modelRows(o, derived: derived)))
        out.sections.append(Section(title: T("Index and storage", "Índice e armazenamento"), rows: [
            row("fts", T("pages \(n(derived, "pages_fts_rows"))/\(n(derived, "pages_rows")); observations \(n(derived, "observations_fts_rows"))/\(n(derived, "observations_rows"))",
                         "páginas \(n(derived, "pages_fts_rows"))/\(n(derived, "pages_rows")); observações \(n(derived, "observations_fts_rows"))/\(n(derived, "observations_rows"))")),
            row(T("database", "banco de dados"), storage.map { s in
                T("\(n(s, "database_bytes")) bytes, \(n(s, "reclaimable_bytes")) reclaimable", "\(n(s, "database_bytes")) bytes, \(n(s, "reclaimable_bytes")) recuperáveis")
            } ?? T("unknown", "desconhecido")),
        ]))
        return out
    }

    private static func modelRows(_ o: [String: Any], derived: [String: Any]) -> [Row] {
        let n = { (key: String) in PanelOverviewData.int(derived[key]) }
        let embedder = (o["embedder"] as? [String: Any]).map { e in
            "\(e["provider"] as? String ?? "")/\(e["model"] as? String ?? "")" + T(" (dim \(PanelOverviewData.int(e["dim"])))", " (dimensão \(PanelOverviewData.int(e["dim"])))")
        } ?? T("none (FTS5 + entity + graph only)", "nenhum (somente FTS5 + entidades + grafo)")
        var rows = [Row(name: T("embedder", "gerador de embeddings"), value: embedder),
                    Row(name: T("reranker", "reclassificador"), value: (o["reranker"] as? Bool ?? false) ? "on" : "off"),
                    Row(name: T("vectors", "vetores"), value: T("\(n("embedding_rows")) rows; \(n("latest_pages_missing_embeddings")) latest pages missing; \(n("latest_pages_unembeddable")) unembeddable",
                                                                "\(n("embedding_rows")) registros; \(n("latest_pages_missing_embeddings")) páginas mais recentes sem embedding; \(n("latest_pages_unembeddable")) sem embedding possível"))]
        for t in derived["embedding_triples"] as? [[String: Any]] ?? [] {
            let dim = PanelOverviewData.int(t["dim"]), count = PanelOverviewData.int(t["count"])
            let who = "\(t["provider"] as? String ?? "")/\(t["model"] as? String ?? "")"
            rows.append(Row(name: T("stored triple", "identidade armazenada"), value: T("\(who) dim \(dim): \(count) rows", "\(who) dimensão \(dim): \(count) registros")))
        }
        return rows
    }

    /// Upstream's sentence for a check, from the numbers (its web.ftl); nil for an id it does not know.
    private static func words(_ id: String, detail: String, hooks: Any?, queue: Any?, spool: [String: Any]?, journal: [String: Any]?, derived: [String: Any],
                              storage: [String: Any]?, consolidation: Any?, age: (Any?) -> String) -> String? {
        let n = { (object: Any?, key: String) in PanelOverviewData.int((object as? [String: Any])?[key]) }
        switch id {
        case "hook_shed":
            let sat = n(hooks, "shed_saturated"), rate = n(hooks, "shed_rate_limited")
            return T("\(sat + rate) hook event(s) were answered 429 since the server started (\(sat) saturated, \(rate) rate-limited); clients spool and retry them.",
                     "\(sat + rate) evento(s) de hooks receberam resposta 429 desde o início do servidor (\(sat) por saturação, \(rate) por limite de taxa); os clientes usam spool e tentam novamente.")
        case "hook_failed":
            return T("\(n(hooks, "failed")) hook delivery(ies) failed to store since the server started.",
                     "\(n(hooks, "failed")) entrega(s) de hooks falharam ao armazenar desde o início do servidor.")
        case "write_queue":
            return T("The write queue holds \(n(queue, "queued")) of \(n(queue, "capacity")) commands.",
                     "A fila de gravação contém \(n(queue, "queued")) de \(n(queue, "capacity")) comandos.")
        case "spool_evicting":
            return T("The hook spool is full (\(n(spool, "pending")) events): newly captured events are dropped until space is available.",
                     "O spool de hooks está cheio (\(n(spool, "pending")) eventos): novos eventos capturados são descartados até que haja espaço.")
        case "spool_pending":
            return T("\(n(spool, "pending")) hook event(s) wait in the local spool and delivery looks stuck (oldest \(age(spool?["oldest_age_ms"])), 0 failed attempt(s)).",
                     "\(n(spool, "pending")) evento(s) de hooks aguardam no spool local e a entrega parece travada (mais antigo \(age(spool?["oldest_age_ms"])), 0 tentativa(s) com falha).")
        case "journal_unreadable": return T("The recovery journal could not be read.", "Não foi possível ler o registro de recuperação.")
        case "journal_pending":
            return T("\(n(journal, "pending")) run(s) wait in the recovery journal (\(n(journal, "degraded")) degraded, \(n(journal, "finish_failed")) finish-failed).",
                     "\(n(journal, "pending")) execução(ões) aguardam no registro de recuperação (\(n(journal, "degraded")) degradadas, \(n(journal, "finish_failed")) com falha no encerramento).")
        case "stale_vectors":
            // The engine counts the triples unlike the running model's; its sentence starts with it.
            let stale = detail.prefix { $0.isNumber }
            return T("\(stale) stored vector(s) were made under another provider, model or dimension and are ignored.",
                     "\(stale) vetor(es) armazenado(s) foram gerados com outro provedor, modelo ou dimensão e são ignorados.")
        case "missing_vectors":
            let missing = n(derived, "latest_pages_missing_embeddings"), failed = n(derived, "embed_failures_unresolved")
            return T("\(missing) latest page(s) have no vector (\(failed) after a failed or skipped embed).",
                     "\(missing) página(s) mais recente(s) não têm vetor (\(failed) após falha ou omissão de geração de embeddings).")
        case "storage_unreadable":
            return T("The database storage figures could not be read; reclaim advice is unavailable.",
                     "Não foi possível ler os dados de armazenamento do banco de dados; a recomendação de recuperação de espaço não está disponível.")
        case "storage_reclaim":
            return T("\(n(storage, "reclaimable_bytes")) of the \(n(storage, "database_bytes"))-byte database is reclaimable; compacting blocks writes while it runs.",
                     "\(n(storage, "reclaimable_bytes")) do banco de \(n(storage, "database_bytes")) bytes são recuperáveis; a compactação bloqueia gravações durante a execução.")
        case "consolidation_failed":
            return T("\(n(consolidation, "failed")) session consolidation job(s) gave up after their retries.",
                     "\(n(consolidation, "failed")) tarefa(s) de consolidação de sessão esgotaram suas tentativas.")
        default: return nil
        }
    }
}
