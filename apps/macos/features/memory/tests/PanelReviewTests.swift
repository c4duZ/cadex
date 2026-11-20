import AppKit
import Checks
import Foundation
import Strings
@testable import Memory

// The review, the health and the docs (plan 40 G) over the recorded seed (extra/review in two
// selections, extra/health; panel-health-warn.json is that answer with four failing checks written
// by hand, the seed's engine being healthy): the reading, upstream's words, the places, the writes as
// commands and POSTs, the screens' choices and buttons with a fake engine, the guides' catalog, and
// with CADEX_SNAPSHOT_DIR memory-review.png, memory-health.png, memory-health-warn.png and
// memory-docs.png, to lay over MemoryReview, MemoryHealth and MemoryDocs (.dc.html).

@MainActor func panelReviewTests() -> [(name: String, body: Checks.Body)] { [
    ("the review reads the seed: three proposals in two projects, upstream's order and words", {
        guard let r = PanelReview.parse(panelFixture("review"), query: PanelReviewQuery()) else { return expect(false) }
        expect(r.total == 3 && r.projectCount == 2 && !r.truncated && r.proposals.map(\.path) == ["proposals/retry-policy.md", "proposals/socket-mode.md", "proposals/deploy.md"],
               "\(r.proposals.map(\.path))")
        let p = r.proposals[0]
        expect(p.project == cadexRef && p.operation == "create" && !p.isRule && !p.rewrites && p.editMode == "full_page" && p.body.hasPrefix("# Proposal"))
        guard let site = PanelReview.parse(panelFixture("review-site"), query: PanelReviewQuery(project: siteRef, sort: "confidence-desc")) else { return expect(false) }
        expect(site.proposals.map(\.project) == [siteRef] && site.total == 3)
        inPortuguese {
            expect(p.confidenceLine == "confiança 80%" && r.countLine == "3 exibidas · 3 pendentes em 2 projetos", r.countLine)
            expect(r.projectTitles == ["Todos os projetos (3)", "cadex (2)", "site (1)"], "\(r.projectTitles)")
            expect(PanelReviewQuery.sorts.map(PanelReviewQuery.sortTitle) == ["Projeto e depois data de envio", "Confiança, menor primeiro",
                                                                             "Confiança, maior primeiro", "Envio, mais recentes primeiro"])
        }
    }),
    ("the review, the health and the docs are places; decisions and fixes are commands and POSTs", {
        let q = PanelReviewQuery(project: siteRef, sort: "confidence-desc")
        expect(q.path == "extra/review?project=default/site&sort=confidence-desc", q.path)
        for place: PanelPlace in [.review(q), .review(PanelReviewQuery()), .health, .docs(words: "", history: false), .docs(words: "inbox", history: false),
                                  .docs(words: "", history: true)] {
            expect(PanelPlace(arguments: place.arguments) == place, "\(place.arguments)")
        }
        expect(PanelPlace.section(.review).normalized == .review(PanelReviewQuery()) && PanelPlace.section(.health).normalized == .health)
        expect(PanelPlace.section(.changelog).normalized == .docs(words: "", history: true) && PanelPlace.docs(words: "", history: true).section == .changelog)
        expect(PanelLoads.paths(.health) == ["extra/health"] && PanelLoads.paths(.docs(words: "", history: false)).isEmpty)
        expect(PanelReviewQuery(sort: "sideways").sort == "project")
        let writes: [PanelWrite] = [.approve(id: "p-1"), .reject(id: "p-1", reason: "too broad"), .reject(id: "p-2", reason: ""), .fix("compact")]
        for w in writes { expect(PanelWrite(command: w.command, arguments: w.arguments) == w, "\(w.arguments)") }
        expect(writes.map(\.path) == ["extra/review/approve", "extra/review/reject", "extra/review/reject", "extra/fix"])
        expect(writes[1].body == #"{"id":"p-1","reason":"too broad"}"# && writes[3].body == #"{"what":"compact"}"#, writes[1].body)
        expect(PanelWrite(command: "memory.fix-health", arguments: ["what": "vacuum"]) == nil && PanelWrite(command: "memory.approve", arguments: [:]) == nil)
    }),
    ("the review screen: filters go to new places; Rejeitar sends the reason; done, the row leaves and the line says it", {
        guard let r = PanelReview.parse(panelFixture("review"), query: PanelReviewQuery()) else { return expect(false) }
        var gone: [PanelPlace] = []
        var sent: [PanelWrite] = []
        let view = PanelReviewView(r, now: panelNowF, write: { sent.append($0) }, reload: {}) { gone.append($0) }
        view.projectPopup.pick(2)
        expect(gone.last == .review(PanelReviewQuery(project: siteRef)), "\(gone)")
        view.sortPopup.pick(3)
        expect(gone.last == .review(PanelReviewQuery(sort: "staged-desc")))
        let row = view.rows[1]
        row.toggle()
        row.reason.stringValue = "  not this one  "
        row.press(1)
        expect(sent == [.reject(id: row.proposal.id, reason: "not this one")], "\(sent)")
        view.finished(sent[0], .success(Data(#"{"ok":true}"#.utf8)))
        expect(row.isHidden && view.statusSaid.hasSuffix("proposals/socket-mode.md."), view.statusSaid)
        expect(view.countSaid.hasPrefix("2 "), view.countSaid)
        view.rows[0].toggle()
        view.rows[0].press(0)
        view.finished(sent.last!, .failure(PanelReadError(words: "the page changed since the proposal was made")))
        expect(!view.rows[0].isHidden && view.statusSaid.contains("proposals/retry-policy.md"), view.statusSaid)
    }),
    ("the health reads the engine: all checks pass on the seed; with failing ones, upstream's words and the Cadex fix", {
        guard let ok = PanelHealth.parse(panelFixture("health")), let warn = PanelHealth.parse(panelFixture("health-warn")) else { return expect(false) }
        expect(ok.checks.isEmpty && ok.sections.map(\.rows.count) == [5, 3, 3, 3, 2], "\(ok.sections.map(\.rows.count))")
        expect(warn.checks.map(\.id) == ["hook_failed", "spool_pending", "missing_vectors", "storage_reclaim"] && warn.checks[0].error)
        expect(warn.checks.map(\.fix) == [nil, "spool", "embed", "compact"], "\(warn.checks.map(\.fix))")
        inPortuguese {
            guard let pt = PanelHealth.parse(panelFixture("health-warn")) else { return expect(false) }
            expect(pt.checks[1].words == "3 evento(s) de hooks aguardam no spool local e a entrega parece travada (mais antigo 21 min, 0 tentativa(s) com falha).", pt.checks[1].words)
            expect(pt.sections.map(\.title) == ["Hooks (desde o início do servidor)", "Gravação, spool e recuperação", "Consolidação", "Embeddings e modelos", "Índice e armazenamento"])
            let models = pt.sections[3].rows
            expect(models.first?.value == "local/all-MiniLM-L6-v2 (dimensão 384)" && models.last?.value == "local/all-MiniLM-L6-v2 dimensão 384: 1 registros", "\(models)")
            expect(pt.sections[4].rows[1].value == "966656 bytes, 400000 recuperáveis" && PanelHealth.fixTitle("spool") == "Reenviar a fila")
        }
    }),
    ("the health screen: a fix button sends memory.fix-health; done, the page reads again and says what it did", {
        guard let warn = PanelHealth.parse(panelFixture("health-warn")) else { return expect(false) }
        var sent: [PanelWrite] = []
        var reloaded: [String?] = []
        let view = PanelHealthView(warn, write: { sent.append($0) }, reload: { reloaded.append($0) }) { _ in }
        expect(Set(view.fixButtons.keys) == ["spool", "embed", "compact"], "\(view.fixButtons.keys)")
        view.fixButtons["spool"]?.performClick(nil)
        expect(sent == [.fix("spool")] && view.fixButtons["spool"]?.isEnabled == false)
        view.finished(.fix("spool"), .success(Data(#"{"delivered":3,"pending":0}"#.utf8)))
        expect(reloaded.count == 1 && reloaded[0]?.hasPrefix("3 ") == true, "\(reloaded)")
        view.finished(.fix("embed"), .failure(PanelReadError(words: "embedder not configured on server")))
        expect(view.statusSaid == "embedder not configured on server" && view.fixButtons["embed"]?.isEnabled == true)
        view.fixButtons["compact"]?.performClick(nil)
        view.cancelled("compact")
        expect(view.fixButtons["compact"]?.isEnabled == true)
        let page = panelPage()
        page.go(.health)
        expect(page.screen is PanelHealthView)
    }),
    ("the guides: upstream's 28, the changelogs apart, the filter by title and description, a click opens on GitHub", {
        expect(PanelGuide.all.count == 28 && PanelGuide.all.filter(\.isChangelog).count == 4)
        expect(PanelGuide.all.allSatisfy { $0.url.absoluteString.hasPrefix("https://github.com/akitaonrails/ai-memory/blob/411d90d") })
        inPortuguese {
            let features = PanelGuide.all[0]
            expect(features.title == "Recursos e ativação" && features.category == "Comece aqui" && features.url.absoluteString.hasSuffix("docs/pt-BR/features.md"))
            expect(PanelDocsView.matching("caixa", history: false).map(\.id) == ["usage", "agent-messaging"], "\(PanelDocsView.matching("caixa", history: false).map(\.id))")
        }
        expect(PanelGuide.all[0].url.absoluteString.hasSuffix("docs/features.md") || Strings.language == .pt)
        var opened: [String] = []
        var gone: [PanelPlace] = []
        let view = PanelDocsView(words: "", history: false, open: { opened.append($0.id) }) { gone.append($0) }
        expect(view.shown.count == 24)
        view.type("zzzz")
        expect(view.shown.isEmpty)
        let changes = PanelDocsView(words: "", history: true, open: { opened.append($0.id) }) { gone.append($0) }
        expect(changes.shown.map(\.id) == ["changelog", "changelog-2x", "changelog-1x", "changelog-0x"])
        let page = panelPage()
        page.go(.docs(words: "", history: false))
        expect(page.screen is PanelDocsView && page.place.section == .docs)
    }),
    ("snapshots: the review with one opened, the health passing and failing, the docs", {
        inPortuguese {
            guard let r = PanelReview.parse(panelFixture("review"), query: PanelReviewQuery()),
                  let ok = PanelHealth.parse(panelFixture("health")), let warn = PanelHealth.parse(panelFixture("health-warn")) else { return expect(false) }
            let review = PanelReviewView(r, now: panelNowF, write: { _ in }, reload: {}) { _ in }
            review.rows[0].toggle()
            panelSnapshot(review, "memory-review.png")
            panelSnapshot(PanelHealthView(ok, write: { _ in }, reload: { _ in }) { _ in }, "memory-health.png")
            panelSnapshot(PanelHealthView(warn, write: { _ in }, reload: { _ in }) { _ in }, "memory-health-warn.png")
            panelSnapshot(PanelDocsView(words: "", history: false, open: { _ in }) { _ in }, "memory-docs.png")
        }
    }),
] }
