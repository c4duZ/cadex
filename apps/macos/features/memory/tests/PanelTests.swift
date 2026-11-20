import AppKit
import Checks
import Foundation
import Strings
import UILooks
@testable import Memory

// The Memória page (plan 40 C): the overview read from the engine's panel JSON recorded over the
// fake memory (core/features/memory/server examples/panel_seed, `cadex memory-agent panel --path`
// for api/v1/projects, extra/home and extra/inbox/notifications), its numbers, sorting and
// filtering, the cards' keys and the sections' list. The seed's projects, in upstream's order:
// _global, site, cadex (4 sessions, 15 events, 5 pages, 1 open, 2 messages waiting), empty, scratch.

/// A recorded answer, next to this file.
func panelFixture(_ name: String) -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/panel-\(name).json")
    return (try? Data(contentsOf: url)) ?? Data()
}

func panelSeed() -> PanelOverviewData? {
    PanelOverviewData.parse(projects: panelFixture("projects"), home: panelFixture("home"), notifications: panelFixture("notifications"))
}

/// The seed was written at 22:43:36Z; "now" is nine hours later, as the board's "há 9 horas".
let panelNow = ISO8601DateFormatter().date(from: "2026-11-20T07:43:40Z")!

/// Runs `body` with the interface in Portuguese (the board's language), then back.
@MainActor func inPortuguese(_ body: () -> Void) {
    let before = Strings.language
    Strings.language = .pt
    body()
    Strings.language = before
}

@MainActor func panelTests() -> [(name: String, body: Checks.Body)] { [
    ("the overview's JSON read: projects in upstream's order, agents and inbox from extra/home", {
        guard let data = panelSeed() else { return expect(false, "the fixtures do not parse") }
        expect(data.projects.map(\.name) == ["_global", "site", "cadex", "empty", "scratch"], "\(data.projects.map(\.name))")
        let cadex = data.projects[2]
        expect(cadex.sessions == 4 && cadex.events == 15 && cadex.pages == 5 && cadex.open == 1, "\(cadex)")
        expect(cadex.agents == ["claude-code", "codex"] && cadex.inbox == 2, "\(cadex)")
        expect(data.projects[3].lastActivity == nil && data.projects[0].lastActivity != nil)
        expect(data.inbox.pending == 2 && data.inbox.projects.map(\.name) == ["cadex"])
        expect(data.capture == PanelCapture())
        expect(PanelOverviewData.parse(projects: Data(#"{"error":"the memory engine did not answer"}"#.utf8), home: nil, notifications: nil) == nil)
        expect(PanelOverviewData.errorText(Data(#"{"error":"down"}"#.utf8)) == "down")
        let alone = PanelOverviewData.parse(projects: panelFixture("projects"), home: nil, notifications: nil)
        expect(alone?.projects.count == 5 && alone?.projects[2].agents == [], "the projects alone still read")
    }),
    ("the five numbers are the sums, and the last capture is the list's first", {
        guard let data = panelSeed() else { return expect(false) }
        let model = PanelOverviewModel(data: data)
        expect(model.data.projects.count == 5 && model.totalSessions == 5 && model.totalEvents == 17 && model.totalPages == 7 && model.totalOpen == 1,
               "\(model.totalSessions) \(model.totalEvents) \(model.totalPages) \(model.totalOpen)")
        expect(model.lastCapture == data.projects[0].lastActivity)
    }),
    ("sorting is most first and keeps upstream's order on a tie; Sessões abertas also filters", {
        guard let data = panelSeed() else { return expect(false) }
        var model = PanelOverviewModel(data: data)
        expect(model.visible.map(\.name) == ["_global", "site", "cadex", "empty", "scratch"])
        model.sort = .sessions
        expect(model.visible.map(\.name) == ["cadex", "site", "_global", "empty", "scratch"], "\(model.visible.map(\.name))")
        model.sort = .pages
        expect(model.visible.map(\.name) == ["cadex", "_global", "site", "empty", "scratch"], "\(model.visible.map(\.name))")
        model.pick(.open)
        expect(model.sort == .open && model.scope == .withOpen && model.visible.map(\.name) == ["cadex"])
        expect(model.shownOfTotal == "1 of 5")
    }),
    ("the scope and the filter: with messages, by name, nothing", {
        guard let data = panelSeed() else { return expect(false) }
        var model = PanelOverviewModel(data: data)
        model.scope = .withInbox
        expect(model.visible.map(\.name) == ["cadex"])
        model.scope = .all
        model.filter = "  SC "
        expect(model.visible.map(\.name) == ["scratch"])
        model.filter = "zzz"
        expect(model.visible.isEmpty && model.shownOfTotal == "0 of 5")
        model.filter = ""
        expect(model.shownOfTotal == nil)
    }),
    ("the words as the board writes them, in Portuguese", {
        inPortuguese {
            expect(PanelWords.number(86023) == "86.023", PanelWords.number(86023))
            expect(PanelWords.ago(panelNow.addingTimeInterval(-9 * 3600 - 30), now: panelNow) == "há 9 horas")
            expect(PanelWords.ago(panelNow.addingTimeInterval(-86400), now: panelNow) == "há 1 dia")
            expect(PanelWords.ago(panelNow.addingTimeInterval(-90 * 86400), now: panelNow) == "há 3 meses")
            expect(PanelWords.lastCapture(nil) == "Nenhuma captura ainda")
            expect(PanelWords.agents(["claude-code"]) == "Claude Code" && PanelWords.agents([]) == "Nenhuma sessão de agente ainda")
            expect(PanelWords.capture(PanelCapture()) == "Captura: 0 aceitos · 0 descartados pela política · 0 por capacidade · 0 limitados por taxa")
            expect(PanelWords.inboxNotice(PanelInbox(pending: 2, projects: [("cadex", 2)])) == "2 mensagens aguardando agentes em cadex (2)")
            expect(PanelSort.standard.title == "Padrão" && PanelScope.all.title == "Todos os projetos")
        }
        expect(PanelWords.number(86023) == "86,023")
        expect(PanelWords.mark("bkdg-center") == "BC" && PanelWords.mark("_global") == "GL" && PanelWords.mark("cadex") == "CA")
    }),
    ("the overview drawn: a number sorts and the selector says it; the filter; the keys and ⌘O", {
        guard let data = panelSeed() else { return expect(false) }
        var opened: [String] = []
        var inCadex: [String] = []
        var actions = MemoryOverviewActions()
        actions.openProject = { opened.append($0.name) }
        actions.openInCadex = { inCadex.append($0.name) }
        actions.inCadex = { $0.name == "cadex" }
        let view = MemoryOverviewView(actions: actions)
        view.frame = NSRect(x: 0, y: 0, width: 1192, height: 826)
        view.show(data, now: panelNow)
        expect(view.cards.map(\.project.name) == ["_global", "site", "cadex", "empty", "scratch"])
        expect(view.cards[2].footLinks == ["Agents ↗", "Open in Cadex"] && view.cards[0].footLinks == ["Agents ↗"], "\(view.cards[2].footLinks)")
        expect(view.stats.map { $0.value.stringValue } == ["5", "5", "17", "7", "1"])
        view.stats[1].onPress?()
        expect(view.sortSaid == "Sessions" && view.cards.first?.project.name == "cadex")
        view.stats[4].onPress?()
        expect(view.sortSaid == "Open sessions" && view.scopeSaid == "With open sessions" && view.cards.count == 1)
        view.pick(.standard)
        view.filter("")
        expect(view.cards.count == 1, "the scope stays until changed")
        view.filter("cad")
        expect(view.cards.map(\.project.name) == ["cadex"])
        view.choose(by: 1)
        expect(view.chosenName == "cadex" && view.chosenProject?.name == "cadex")
        view.cards[0].openMemory()
        view.cards[0].openInCadex()
        expect(opened == ["cadex"] && inCadex == ["cadex"])
        expect(view.cards[0].entries().map(\.title) == ["Open Memory", "Agents", "Open in Cadex"])
        view.show(data, now: panelNow)
        expect(view.cards.map(\.project.name) == ["cadex"], "a reload keeps the filter and the scope")
    }),
    ("the ⓘ: its sentence is the help, and the click opens it", {
        let help = PanelHelpButton(PanelWords.captureHelp)
        expect(help.accessibilityHelp() == PanelWords.captureHelp && help.accessibilityRole() == .button)
    }),
    ("the sections: three groups, nine lines, Projetos lit, the inbox count, a pick and a search", {
        let nav = MemoryPanelNav()
        expect(nav.lineTitles == ["Projects", "Inbox", "Workstreams", "Search Memory", "Knowledge Graph", "Learning Review", "Server Health",
                                  "Documentation", "Changelog"], "\(nav.lineTitles)")
        expect(MemoryPanelSection.groups.map(\.sections.count) == [5, 2, 2])
        expect(nav.litSection == .projects && nav.inboxSaid == "")
        nav.setInbox(2)
        expect(nav.inboxSaid == "2")
        var picked: [MemoryPanelSection] = []
        var searched: [String] = []
        nav.onPick = { picked.append($0) }
        nav.onSearch = { searched.append($0) }
        nav.press(.health)
        nav.search("  ")
        nav.search("tenant")
        expect(picked == [.health] && searched == ["tenant"])
        nav.select(.inbox)
        expect(nav.litSection == .inbox)
        expect(MemoryPanelSection.allCases.filter(\.isBuilt) == [.projects, .inbox, .workstreams, .search, .graph])
    }),
    ("the page: the overview with data, one line for a section still to come, the off state", {
        var actions = MemoryPanelActions()
        var reads = 0
        actions.load = { done in reads += 1; done(panelSeed().map { .data($0) } ?? .off) }
        var closed = false
        actions.closed = { closed = true }
        let page = MemoryPanelDocument(actions: actions)
        expect(page.loaded && page.isPage && page.identity == "memory:panel" && reads == 1)
        page.show(.graph)
        expect(page.section == .graph && reads == 1, "a section to come reads nothing")
        page.show(.projects)
        expect(reads == 2 && page.overview.cards.count == 5)
        page.close()
        expect(closed)
        var off = MemoryPanelActions()
        off.load = { $0(.off) }
        expect(!MemoryPanelDocument(actions: off).loaded)
    }),
    ("the overview drawn over the seed (CADEX_SNAPSHOT_DIR: memory-overview.png), to lay over the board", {
        guard let out = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let data = panelSeed() else { return }
        inPortuguese {
            var actions = MemoryOverviewActions()
            actions.inCadex = { ["cadex", "site"].contains($0.name) }
            let view = MemoryOverviewView(actions: actions)
            view.frame = NSRect(x: 0, y: 0, width: 1192, height: 826)
            view.show(data, now: panelNow)
            let host = NSView(frame: view.frame)
            host.wantsLayer = true
            host.layer?.backgroundColor = DesignTokens.Color.bgWindow.cgColor
            host.addSubview(view)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/memory-overview.png"))
        }
    }),
] }
