import Checks
import Foundation
import Strings
@testable import Memory

// The project's screens' data and navigation (plan 40 D), from the engine's panel JSON recorded over
// the fake memory (examples/panel_seed, `cadex memory-agent panel --path` for each route; the engine
// started with its maintenance held back, so the seed's open session stays open). The seed's cadex:
// 4 sessions (one open, 3 by Claude Code, 1 by Codex), 5 pages (decisions/engine.md with 2 versions),
// 2 messages waiting.

let cadexRef = PanelProjectRef(name: "cadex")

/// The seed was written at 23:21:51Z; "now" is nine hours later.
let panelNowD = ISO8601DateFormatter().date(from: "2026-11-20T08:21:55Z")!

/// What a route answers in the tests: the recorded fixture for it, or nil.
func panelAnswer(_ path: String) -> Data? {
    let base = cadexRef.api, extra = cadexRef.extra
    let map: [String: String] = [
        "api/v1/projects": "projects", extra + "/summary": "summary", base + "/pages": "pages", extra + "/agents": "agents",
        extra + "/sessions": "sessions", extra + "/tokens": "tokens", base + "/pages/decisions/engine.md": "page",
        extra + "/evidence/decisions/engine.md": "evidence", base + "/history/decisions/engine.md": "history",
        extra + "/agents/claude-code": "agent",
        base + "/sessions/00000000-0000-4000-8000-000000000001/observations?offset=0&limit=50": "observations",
        extra + "/sessions/00000000-0000-4000-8000-000000000001/tokens": "session-tokens",
        extra + "/sessions/00000000-0000-4000-8000-000000000001/retrievals": "retrievals",
    ]
    return map[path].map(panelFixture)
}

func panelProjectSeed() -> PanelProjectData? {
    PanelProjectData.parse(cadexRef, PanelProjectData.paths(cadexRef).map(panelAnswer))
}

@MainActor func panelDetailTests() -> [(name: String, body: Checks.Body)] { [
    ("a place's arguments come back as the same place, and the trail names it", {
        let places: [PanelPlace] = [.section(.graph), .project(cadexRef, .knowledge), .page(cadexRef, "decisions/engine.md"),
                                    .history(cadexRef, "decisions/engine.md", from: "a", to: "b"), .session(cadexRef, "s-1", offset: 50),
                                    .retrievals(cadexRef, "s-1", offset: 0), .agent(PanelProjectRef(workspace: "acct", name: "cadex"), "codex")]
        for place in places { expect(PanelPlace(arguments: place.arguments) == place, "\(place.arguments)") }
        expect(PanelPlace(arguments: ["project": "cadex"]) == .project(cadexRef, .overview))
        expect(PanelPlace(arguments: ["section": "nope"]) == nil && PanelPlace(arguments: ["project": "cadex", "tab": "nope"]) == nil)
        inPortuguese {
            expect(PanelPlace.project(cadexRef, .overview).crumbs.map(\.title) == ["Projetos", "cadex"])
            let history = PanelPlace.history(cadexRef, "decisions/engine.md", from: nil, to: nil).crumbs
            expect(history.map(\.title) == ["Projetos", "cadex", "decisions/engine.md", "histórico"], "\(history.map(\.title))")
            expect(history[2].place == .page(cadexRef, "decisions/engine.md") && history[3].place == nil)
            expect(PanelPlace.session(cadexRef, "1301a3b0-bc1c", offset: 0).crumbs.last?.title == "sessão 1301a3b0…")
            expect(PanelPlace.agent(cadexRef, "claude-code").crumbs.last?.title == "Claude Code")
            expect(PanelPlace.agent(PanelProjectRef(workspace: "acct", name: "x"), "codex").crumbs.map(\.title) == ["Projetos", "acct", "x", "Codex"])
        }
    }),
    ("back and forward go through the places seen; a new place drops what was ahead", {
        var trail = PanelTrail()
        trail.go(.project(cadexRef, .overview))
        trail.go(.page(cadexRef, "a.md"))
        trail.go(.page(cadexRef, "a.md"))
        expect(trail.back.count == 2)
        expect(trail.goBack() == .project(cadexRef, .overview) && trail.goBack() == .section(.projects) && trail.goBack() == nil)
        expect(trail.goForward() == .project(cadexRef, .overview))
        trail.go(.agent(cadexRef, "codex"))
        expect(trail.forward.isEmpty && trail.goForward() == nil)
    }),
    ("each place reads its routes, the parts escaped", {
        expect(PanelLoads.paths(.page(cadexRef, "notes/a b.md")) == [cadexRef.api + "/pages/notes/a%20b.md", cadexRef.extra + "/evidence/notes/a%20b.md"])
        expect(PanelLoads.paths(.history(cadexRef, "a.md", from: "x", to: "y")) == [cadexRef.api + "/history/a.md?from=x&to=y"])
        expect(PanelLoads.paths(.session(cadexRef, "s", offset: 50)) == [cadexRef.api + "/sessions/s/observations?offset=50&limit=50", cadexRef.extra + "/sessions/s/tokens"])
        expect(PanelLoads.paths(.retrievals(cadexRef, "s", offset: 25)) == [cadexRef.extra + "/sessions/s/retrievals?offset=25"])
        expect(PanelProjectRef(workspace: "a b", name: "c/d").api == "api/v1/workspaces/a%20b/projects/c%2Fd")
        expect(PanelLoads.paths(.project(cadexRef, .sessions)).count == 6 && PanelLoads.paths(.section(.projects)).isEmpty)
    }),
    ("the project's data read: numbers, agents, mailbox, pages, sessions, agents' cards, tokens", {
        guard let d = panelProjectSeed() else { return expect(false, "the project's fixtures do not parse") }
        expect(d.project.sessions == 4 && d.project.events == 15 && d.project.pages == 5 && d.project.open == 1, "\(d.project)")
        expect(d.summary.tokens?.input == 14000 && d.summary.tokens?.output == 4000)
        expect(d.summary.agents.map(\.agent) == ["claude-code", "codex"] && d.summary.agents.map(\.sessions) == [3, 1])
        expect(d.summary.mailboxTotal == 2 && d.summary.messages.map(\.subject) == ["Panel question", "Site needs the engine doc"])
        expect(d.pages.count == 5 && d.sessions.count == 4 && d.sessions.filter(\.isOpen).map(\.id) == ["00000000-0000-4000-8000-000000000003"])
        expect(d.agents.first?.coverage == 66 && d.agents.first?.reported == 107_500, "\(String(describing: d.agents.first))")
        expect(d.tokens.callCount == 0 && d.tokens.calls.isEmpty)
        expect(PanelProjectSummary.parse(Data(#"{"error":"no"}"#.utf8)) == nil)
        let agent = PanelAgentData.parse(panelFixture("agent"))
        expect(agent?.card.open == 1 && agent?.sessions.count == 3 && agent?.more == false)
    }),
    ("Conhecimento: knowledge folders by name, machinery under Sistema, recent without machinery", {
        guard let d = panelProjectSeed() else { return expect(false) }
        let k = PanelKnowledge(pages: d.pages)
        expect(k.folders.map(\.name) == ["_rules", "decisions", "gotchas"], "\(k.folders.map(\.name))")
        expect(k.system.map(\.name) == ["(root)", "_slots"], "\(k.system.map(\.name))")
        expect(k.recent.map(\.path) == ["_rules/commit-style.md", "gotchas/socket.md", "decisions/engine.md"], "\(k.recent.map(\.path))")
        expect(PanelKnowledge.isSystem("log-2026-11.md") && !PanelKnowledge.isSystem("notes/log-1.md") && PanelKnowledge.isSystem("sessions/a.md"))
    }),
    ("the words: tokens, in / out, durations, short ids, the capture line", {
        inPortuguese {
            expect(PanelWords.tokens(14000) == "14,0k" && PanelWords.tokens(950) == "950" && PanelWords.tokens(1_250_000) == "1,2M")
            expect(PanelWords.inOut(PanelUsage(input: 14000, output: 4000)) == "14,0k / 4,0k" && PanelWords.inOut(nil) == "—")
            let start = panelNowD
            expect(PanelWords.duration(start, start.addingTimeInterval(40)) == "40s" && PanelWords.duration(start, start.addingTimeInterval(13 * 60)) == "13m")
            expect(PanelWords.duration(start, start.addingTimeInterval(5 * 3600 + 33 * 60)) == "5h 33m" && PanelWords.duration(start, start.addingTimeInterval(3 * 86400)) == "3d")
            expect(PanelWords.duration(start, nil) == "aberta")
            expect(PanelWords.projectCapture(panelNowD.addingTimeInterval(-9 * 3600), open: 0, now: panelNowD) == "Última captura: há 9 horas · nenhuma sessão aberta")
            expect(PanelWords.versions(1) == "1 versão, a mais recente primeiro" && PanelWords.chars(386) == "386 caracteres")
            expect(PanelWords.tokenLine(PanelTokenReport()) == "0–0 de 0 respostas · 0 capturadas · 0 tokens nas correspondências")
        }
        expect(PanelWords.shortID("00000000-0000-4000-8000-000000000001") == "00000001")
        expect(PanelHistory.short("01a1efac-d887-7582-a5ab-f87c5ef7d2d8") == "5ef7d2d8")
    }),
    ("the history: two versions, the diff's lines with their signs, one version with nothing before", {
        guard let h = PanelHistory.parse(panelFixture("history")) else { return expect(false) }
        expect(h.total == 2 && h.versions.map(\.isLatest) == [true, false] && h.versions[0].chars == 107 && h.from != nil)
        guard case .lines(let lines, let cut) = h.diff else { return expect(false, "\(h.diff)") }
        expect(!cut && lines.first == .hunk("@@ -1,3 +1,5 @@"), "\(lines)")
        expect(lines.contains(.del("The engine runs in its own process.")) && lines.contains(.add("It listens on a Unix socket.")))
        let view = PanelDiffView(h.diff)
        expect(view.linesDrawn == ["@@ -1,3 +1,5 @@", " # Engine process", " ", "−The engine runs in its own process.",
                                   "+The engine runs in its own process, one per memory folder.", "+", "+It listens on a Unix socket."], "\(view.linesDrawn)")
        let one = PanelHistory.parse(panelFixture("history-one"))
        expect(one?.from == nil && one?.versions.count == 1)
        expect(PanelDiffView(.same).linesDrawn.isEmpty)
    }),
    ("the page, its evidence, and its Markdown drawn natively with the page links", {
        guard let page = PanelPageDetail.parse(panelFixture("page")), let ev = PanelEvidence.parse(panelFixture("evidence")) else { return expect(false) }
        expect(page.title == "Engine process" && page.kind == "decision" && page.tier == "semantic" && page.backlinks.count == 3)
        expect(page.backlinks.last?.project == "site" && ev.sourceCount == 0 && ev.contradictionCount == 0 && !ev.expired && ev.version == page.id)
        let drawn = PanelMarkdown.render("# T\n\n## Why\n\n- **Icons:** Phosphor\n- see [the engine](decisions/engine.md) and [[gotchas/socket]]\n\n```\ncode\n```")
        expect(drawn.headings == [PanelMarkdown.Heading(level: 2, text: "Why")], "\(drawn.headings)")
        expect(drawn.text.string.contains("•\tIcons: Phosphor") && !drawn.text.string.contains("**") && !drawn.text.string.hasPrefix("T"), drawn.text.string)
        var links: [String] = []
        drawn.text.enumerateAttribute(.link, in: NSRange(location: 0, length: drawn.text.length)) { value, _, _ in
            if let url = value as? URL, let path = PanelMarkdown.pagePath(url) { links.append(path) }
        }
        expect(links == ["decisions/engine.md", "gotchas/socket.md"], "\(links)")
        expect(PanelMarkdown.target(URL(string: "https://x.dev")!).scheme == "https")
    }),
    ("the timeline and its page bar; the retrievals", {
        guard let t = PanelTimeline.parse(panelFixture("observations")) else { return expect(false) }
        expect(t.observations.count == 6 && t.total == 6 && t.observations[1].kind == "user-prompt" && !t.session.isOpen)
        inPortuguese { expect(t.pager.range == "1–6 de 6") }
        expect(t.pager.next == nil && t.pager.previous == nil)
        let big = PanelPager(offset: 50, limit: 50, total: 882)
        expect(big.first == 0 && big.previous == 0 && big.next == 100 && big.last == 850 && big.page == 2 && big.pages == 18)
        expect(big.offset(ofItem: 851) == 850 && big.offset(ofItem: 9999) == 850 && big.offset(ofItem: 0) == 0)
        expect(PanelTimeline.parse(panelFixture("observations-open"))?.session.isOpen == true)
        let r = PanelRetrievals.parse(panelFixture("retrievals"))
        expect(r?.total == 0 && r?.records.isEmpty == true && r?.limit == 25)
        var filter = PanelTokenFilter()
        expect(filter.query == "")
        filter.values = ["calls_q": "a b", "calls_sort": "recent", "calls_model": " "]
        expect(filter.query == "?calls_q=a%20b&calls_sort=recent", filter.query)
    }),
] }
