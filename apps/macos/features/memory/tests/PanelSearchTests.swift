import AppKit
import Checks
import Foundation
import Strings
@testable import Memory

// Pesquisar na memória (plan 40 E) over the recorded seed (extra/search, fixtures/panel-search*.json):
// the reading, the query's route and arguments, the marks in snippets and titles, the screen's
// bar and keys, the page's "why" recomputed, and with CADEX_SNAPSHOT_DIR memory-search.png and
// memory-search-explain.png, to lay over MemorySearch.dc.html.

@MainActor func panelSearchTests() -> [(name: String, body: Checks.Body)] { [
    ("the search reads the seed: hits in the engine's order, marks, count; the recent pages with no words", {
        guard let r = PanelSearchResult.parse(panelFixture("search")) else { return expect(false) }
        expect(r.hits.map(\.path) == ["decisions/engine.md", "gotchas/socket.md", "deploy.md", "index.md"], "\(r.hits.map(\.path))")
        expect(r.hits[2].project == PanelProjectRef(name: "site") && r.scopes.count == 5 && r.kinds.count == 10 && r.tiers.count == 4)
        let first = r.hits[0].snippet
        expect(first.text.hasPrefix("# Engine process The engine runs") && !first.text.contains("  ") && !first.text.contains("\n"), "one line: \(first.text)")
        expect(first.marks.map { (first.text as NSString).substring(with: $0) } == ["Engine", "engine"])
        inPortuguese { expect(r.countLine == "4 resultados") }
        guard let recent = PanelSearchResult.parse(panelFixture("search-recent")), let none = PanelSearchResult.parse(panelFixture("search-none")) else { return expect(false) }
        expect(recent.isRecent && recent.hits.count == 7 && recent.hits.allSatisfy { $0.snippet.marks.isEmpty })
        expect(none.hits.isEmpty && none.filtered && none.query.kind == "decision")
        guard let explained = PanelSearchResult.parse(panelFixture("search-explain")) else { return expect(false) }
        let trace = explained.hits[0].trace
        expect(trace?.line == "#1 · rank -0.02049 · fused 0.01639 · authority 1.2500", trace?.line ?? "")
        expect(trace?.streams.map(\.stream) == ["fts", "entity", "vector", "graph"] && explained.streams == "fts, entity, graph, observation" && explained.embedder == "none")
    }),
    ("marks: the engine's <mark> read into ranges, escapes undone; the title marked by the words, accents ignored", {
        let m = PanelMarked(html: "a &lt;b&gt; <mark>mem&amp;ória</mark> c <mark>x</mark>")
        expect(m.text == "a <b> mem&ória c x" && m.marks == [NSRange(location: 6, length: 8), NSRange(location: 17, length: 1)], "\(m.marks)")
        let title = PanelMarked(text: "Sessão de auditoria da memória ai-memory", words: "memoria")
        expect(title.marks.map { (title.text as NSString).substring(with: $0) } == ["memória"], "\(title.marks)")
        expect(PanelMarked(text: "Engine engine", words: "ENGINE e").marks.count == 2, "a one-letter word marks nothing")
        expect(PanelMarked.merged([NSRange(location: 0, length: 3), NSRange(location: 2, length: 3)]) == [NSRange(location: 0, length: 5)])
    }),
    ("a search is a place: its route and arguments, the section opening the recent pages, the sidebar's scope", {
        let q = PanelSearchQuery(words: " memória x ", scope: cadexRef, kind: "decision", tier: "semantic", explain: true)
        expect(q.path == "extra/search?q=mem%C3%B3ria%20x&scope=default/cadex&kind=decision&tier=semantic&explain=1", q.path)
        expect(PanelPlace(arguments: PanelPlace.search(q).arguments) == .search(q))
        expect(PanelPlace(arguments: ["section": "search"]) == .search(PanelSearchQuery()) && PanelSearchQuery().path == "extra/search")
        expect(PanelPlace(arguments: ["section": "search", "query": "x", "scope": "cadex"]) == .search(PanelSearchQuery(words: "x", scope: cadexRef)))
        expect(PanelPlace.section(.search).normalized == .search(PanelSearchQuery()) && PanelPlace.search(q).section == .search)
        expect(PanelPlace.search(q).searchScope == cadexRef && PanelPlace.page(cadexRef, "a.md").searchScope == cadexRef && PanelPlace.search(q).project == nil)
        expect(PanelLoads.paths(.search(q)) == [q.path])
    }),
    ("the screen: Enter, a filter and Explicar each run a new search; the × leaves the project; ↓ and Enter open a hit", {
        guard let r = PanelSearchResult.parse(panelFixture("search-explain")) else { return expect(false) }
        var gone: [PanelPlace] = []
        var opened: [String] = []
        let view = PanelSearchView(r, open: { opened.append($0.path) }) { gone.append($0) }
        expect(view.popupsSaid[0] == "cadex", "\(view.popupsSaid)")
        view.type("socket")
        expect(gone.last == .search(PanelSearchQuery(words: "socket", scope: cadexRef, explain: true)), "\(gone)")
        view.pickKind(4)
        expect(gone.last == .search(PanelSearchQuery(words: "socket", scope: cadexRef, kind: "decision", explain: true)), "\(gone)")
        view.pickScope(0)
        expect(gone.last == .search(PanelSearchQuery(words: "socket", explain: true)))
        view.toggleExplain()
        expect(gone.last == .search(PanelSearchQuery(words: "socket", scope: cadexRef)))
        view.choose(by: 1)
        view.choose(by: 1)
        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        expect(opened == ["gotchas/socket.md"], "\(opened)")
        expect(view.rows[0].traceShown == 0)
        view.rows[0].toggleTrace()
        expect(view.rows[0].traceShown == 5, "the head and four streams: \(view.rows[0].traceShown)")
    }),
    ("the page goes to Pesquisar, a hit opens its page, and its 'why' recomputes the search with the trace", {
        let reads = Box<[String]>([])
        let page = panelPage(reads)
        page.show(.search)
        expect(page.place == .search(PanelSearchQuery()) && page.section == .search && page.screen is PanelSearchView && reads.value == ["extra/search"])
        page.go(.search(PanelSearchQuery(words: "engine", scope: cadexRef, explain: true)))
        guard let search = page.screen as? PanelSearchView else { return expect(false) }
        search.choose(by: 1)
        search.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                              characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        guard let shown = page.screen as? PanelPageView else { return expect(false, "\(String(describing: page.screen))") }
        expect(shown.whyRow.recall?.words == "engine")
        shown.whyRow.recompute()
        expect(shown.whyRow.why == .traced(PanelSearchResult.parse(panelFixture("search-explain"))!.hits[0].trace!), "\(String(describing: shown.whyRow.why))")
        expect(page.back() && page.screen is PanelSearchView)
        expect(PanelWhy.find(PanelHitKey(project: cadexRef, path: "nope.md"), in: PanelSearchResult.parse(panelFixture("search"))!) == .outside)
        expect(PanelWhy.find(PanelHitKey(project: PanelProjectRef(name: "site"), path: "deploy.md"), in: PanelSearchResult.parse(panelFixture("search"))!) == .position(3))
    }),
    ("the search drawn over the seed (CADEX_SNAPSHOT_DIR: memory-search.png, memory-search-explain.png)", {
        guard ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] != nil,
              let r = PanelSearchResult.parse(panelFixture("search")), let e = PanelSearchResult.parse(panelFixture("search-explain")) else { return }
        inPortuguese {
            panelSnapshot(PanelSearchView(r, open: { _ in }) { _ in }, "memory-search.png")
            let explained = PanelSearchView(e, open: { _ in }) { _ in }
            explained.rows.first?.toggleTrace()
            panelSnapshot(explained, "memory-search-explain.png")
            if let none = PanelSearchResult.parse(panelFixture("search-none")) { panelSnapshot(PanelSearchView(none, open: { _ in }) { _ in }, "memory-search-none.png") }
        }
    }),
] }
