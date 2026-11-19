import AppKit
import Checks
import Foundation
import Strings
import UILooks
@testable import Memory

// The project's screens drawn (plan 40 D) over the recorded seed: their clicks and keys, the page's
// navigation with a fake engine (the fixtures by path), and with CADEX_SNAPSHOT_DIR a PNG of each
// screen, to lay over its board (memory-project.png, memory-knowledge.png, memory-page.png,
// memory-history.png, memory-session.png, memory-agent.png, memory-retrievals.png).

/// A page over the fixtures: each read answers the recorded route, or the engine's error.
@MainActor func panelPage(_ reads: Box<[String]>? = nil) -> MemoryPanelDocument {
    var actions = MemoryPanelActions()
    actions.load = { $0(panelSeed().map { .data($0) } ?? .off) }
    actions.read = { path, done in
        reads?.value.append(path)
        done(panelAnswer(path).map { .success($0) } ?? .failure(PanelReadError(words: "no route \(path)")))
    }
    actions.project.inCadex = { $0.name == "cadex" }
    actions.project.openInCadex = { _, _ in }
    return MemoryPanelDocument(actions: actions)
}

final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

/// Draws `view` at the board's center size into `name` under CADEX_SNAPSHOT_DIR.
@MainActor func panelSnapshot(_ view: NSView, _ name: String) {
    guard let out = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
    view.frame = NSRect(x: 0, y: 0, width: 1192, height: 826)
    let host = NSView(frame: view.frame)
    host.wantsLayer = true
    host.layer?.backgroundColor = DesignTokens.Color.bgWindow.cgColor
    host.addSubview(view)
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/" + name))
}

@MainActor func panelScreenTests() -> [(name: String, body: Checks.Body)] { [
    ("the page goes to a project, a page, its history and back and forward, reading each place's routes", {
        let reads = Box<[String]>([])
        let page = panelPage(reads)
        page.go(.project(cadexRef, .overview))
        expect(page.screen is PanelProjectView && reads.value == PanelProjectData.paths(cadexRef), "\(reads.value)")
        page.go(.project(cadexRef, .knowledge))
        expect(reads.value.count == 6 && (page.screen as? PanelProjectView)?.tab == .knowledge, "another tab reads nothing")
        page.go(.page(cadexRef, "decisions/engine.md"))
        expect(page.screen is PanelPageView && page.section == .projects)
        page.go(.history(cadexRef, "decisions/engine.md", from: nil, to: nil))
        expect(page.screen is PanelHistoryView)
        expect(page.back() && page.screen is PanelPageView && page.back() && page.place == .project(cadexRef, .knowledge))
        expect(page.forward() && page.place == .page(cadexRef, "decisions/engine.md"))
        page.go(.page(cadexRef, "missing.md"))
        expect(page.screen == nil, "a route that fails says so in one line")
        page.go(.section(.projects))
        expect(page.screen == nil && page.overview.cards.count == 5)
        var gone: [PanelPlace] = []
        var routed = MemoryPanelActions()
        routed.go = { gone.append($0) }
        MemoryPanelDocument(actions: routed).navigate(.agent(cadexRef, "codex"))
        expect(gone == [.agent(cadexRef, "codex")], "a click runs the app's command")
    }),
    ("the project screen: a number opens its tab with upstream's filter; a tab and an agent's chip go", {
        guard let data = panelProjectSeed() else { return expect(false) }
        var gone: [PanelPlace] = []
        var reads: [String] = []
        var actions = PanelProjectActions()
        actions.read = { path, done in reads.append(path); done(panelFixture("sessions")) }
        let view = PanelProjectView(cadexRef, data: data, tab: .overview, now: panelNowD, actions: actions) { gone.append($0) }
        view.showSessions(open: true, events: false)
        expect(reads == [cadexRef.extra + "/sessions?state=open"] && gone == [.project(cadexRef, .sessions)], "\(reads) \(gone)")
        view.select(.sessions)
        expect(view.sessionList?.sessions.count == 4 && view.sessionsQuery == "?state=open")
        view.tabsView?.press(4)
        expect(gone.last == .project(cadexRef, .knowledge))
        expect(view.sessionList?.entries(data.sessions[0]).map(\.title) == ["Open Timeline"], "no Abrir no Cadex without a Cadex project")
    }),
    ("the tree opens a folder to its pages and a page goes to it; Sistema folds", {
        guard let data = panelProjectSeed() else { return expect(false) }
        var opened: [String] = []
        let tree = PanelPageTree(PanelKnowledge(pages: data.pages)) { opened.append($0) }
        expect(tree.lineTitles == ["_rules/", "decisions/", "gotchas/", "System", "(root)", "_slots/"], "\(tree.lineTitles)")
        tree.press("decisions/")
        expect(tree.lineTitles.contains("Engine process"))
        tree.press("Engine process")
        tree.press("System")
        expect(opened == ["decisions/engine.md"] && !tree.lineTitles.contains("_slots/"))
    }),
    ("the sessions' table: the arrows choose, Enter opens, ⌘O and the right click open in Cadex", {
        guard let data = panelProjectSeed() else { return expect(false) }
        var opened: [String] = []
        var inCadex: [String] = []
        var acts = PanelSessionActions()
        acts.open = { opened.append($0.id) }
        acts.openInCadex = { inCadex.append($0.id) }
        let list = PanelSessionList(data.sessions, withAgent: false, now: panelNowD, actions: acts)
        list.table.choose(by: 1)
        list.table.choose(by: 1)
        expect(list.chosenSession?.id == data.sessions[1].id && list.linksShown == 1)
        list.pressOpen(0)
        expect(opened == [data.sessions[0].id])
        expect(list.entries(data.sessions[2]).map(\.title) == ["Open Timeline", "Open in Cadex"])
        list.table.choose(by: 1)
        list.table.rows[2].accessory.map { ($0 as? PanelPress)?.onPress?() }
        expect(inCadex == [data.sessions[2].id], "\(inCadex)")
    }),
    ("the history: Comparar selecionadas goes with the pair; the session's page bar and ⓘ; the agent's band", {
        guard let h = PanelHistory.parse(panelFixture("history")) else { return expect(false) }
        var gone: [PanelPlace] = []
        let view = PanelHistoryView(cadexRef, history: h, now: panelNowD) { gone.append($0) }
        view.pick(from: 0, to: 1)
        view.compare()
        expect(gone == [.history(cadexRef, "decisions/engine.md", from: h.versions[0].id, to: h.versions[1].id)], "\(gone)")
        var offsets: [Int] = []
        let bar = PanelPagerBar(PanelPager(offset: 0, limit: 50, total: 882)) { offsets.append($0) }
        bar.press("previous")
        bar.press("next")
        bar.press("last")
        bar.type(120)
        expect(offsets == [50, 850, 100], "\(offsets)")
        guard let t = PanelTimeline.parse(panelFixture("observations")) else { return expect(false) }
        let session = PanelSessionView(cadexRef, timeline: t, tokens: PanelTokenReport(), now: panelNowD, actions: PanelSessionScreenActions()) { gone.append($0) }
        expect(session.cards.count == 6)
        session.step(1)
        session.step(1)
        expect(session.chosen == 1)
        guard let agent = PanelAgentData.parse(panelFixture("agent")) else { return expect(false) }
        let agentView = PanelAgentView(cadexRef, data: agent, now: panelNowD, actions: PanelProjectActions()) { gone.append($0) }
        expect(agentView.list?.sessions.count == 3)
    }),
    ("each screen drawn over the seed (CADEX_SNAPSHOT_DIR), to lay over its board", {
        guard ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] != nil, let data = panelProjectSeed() else { return }
        inPortuguese {
            var actions = PanelProjectActions()
            actions.openInCadex = { _, _ in }
            panelSnapshot(PanelProjectView(cadexRef, data: data, tab: .overview, now: panelNowD, actions: actions) { _ in }, "memory-project.png")
            panelSnapshot(PanelProjectView(cadexRef, data: data, tab: .knowledge, now: panelNowD, actions: actions) { _ in }, "memory-knowledge.png")
            panelSnapshot(PanelProjectView(cadexRef, data: data, tab: .agents, now: panelNowD, actions: actions) { _ in }, "memory-agents.png")
            panelSnapshot(PanelProjectView(cadexRef, data: data, tab: .sessions, now: panelNowD, actions: actions) { _ in }, "memory-sessions.png")
            if let page = PanelPageDetail.parse(panelFixture("page")), let ev = PanelEvidence.parse(panelFixture("evidence")) {
                panelSnapshot(PanelPageView(cadexRef, page: page, evidence: ev, now: panelNowD) { _ in }, "memory-page.png")
            }
            if let h = PanelHistory.parse(panelFixture("history")) { panelSnapshot(PanelHistoryView(cadexRef, history: h, now: panelNowD) { _ in }, "memory-history.png") }
            if let t = PanelTimeline.parse(panelFixture("observations")) {
                var acts = PanelSessionScreenActions()
                acts.openInCadex = { _ in }
                panelSnapshot(PanelSessionView(cadexRef, timeline: t, tokens: PanelTokenReport.parse(panelFixture("session-tokens")) ?? PanelTokenReport(),
                                               now: panelNowD, actions: acts) { _ in }, "memory-session.png")
            }
            if let a = PanelAgentData.parse(panelFixture("agent")) {
                panelSnapshot(PanelAgentView(cadexRef, data: a, now: panelNowD, actions: actions) { _ in }, "memory-agent.png")
            }
            if let r = PanelRetrievals.parse(panelFixture("retrievals")) {
                panelSnapshot(PanelRetrievalsView(cadexRef, session: "00000000-0000-4000-8000-000000000001", retrievals: r, now: panelNowD) { _ in },
                              "memory-retrievals.png")
            }
        }
    }),
] }
