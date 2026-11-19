import AppKit
import Strings
import UILooks

/// What a project's screens read, put together (the document reads the routes in `paths`).
public struct PanelProjectData: Sendable {
    public var project: PanelProject
    public var summary: PanelProjectSummary
    public var pages: [PanelPageRow]
    public var agents: [PanelAgentCard]
    public var sessions: [PanelSession]
    public var tokens: PanelTokenReport

    /// The routes, in the order `parse` takes them: the projects list (the numbers), the summary,
    /// the pages, the agents, the sessions (with the tab's filters) and the token usage.
    public static func paths(_ p: PanelProjectRef, sessions query: String = "", tokens filter: String = "") -> [String] {
        ["api/v1/projects", p.extra + "/summary", p.api + "/pages", p.extra + "/agents", p.extra + "/sessions" + query, p.extra + "/tokens" + filter]
    }

    public static func parse(_ ref: PanelProjectRef, _ answers: [Data?]) -> PanelProjectData? {
        guard answers.count == 6, let summary = PanelProjectSummary.parse(answers[1]) else { return nil }
        let row = PanelOverviewData.parse(projects: answers[0] ?? Data(), home: nil, notifications: nil)?.projects
            .first { $0.workspace == ref.workspace && $0.name == ref.name } ?? PanelProject(workspace: ref.workspace, name: ref.name)
        return PanelProjectData(project: row, summary: summary, pages: PanelPageRow.list(answers[2]) ?? [], agents: PanelAgentCard.list(answers[3]) ?? [],
                                sessions: PanelSession.list(answers[4]) ?? [], tokens: PanelTokenReport.parse(answers[5]) ?? PanelTokenReport())
    }
}

/// What a project's screens ask the app beyond going somewhere; each is a command's work.
@MainActor
public struct PanelProjectActions {
    /// Reads one route again (a tab's filter changed); nil data: it failed.
    public var read: (String, @escaping @MainActor (Data?) -> Void) -> Void = { _, done in done(nil) }
    /// "Abrir no Cadex": the project, or a session's terminal (nil: no Cadex project has the folder).
    public var openInCadex: ((PanelProjectRef, PanelSession?) -> Void)?
    /// A Cadex project has this one's folder: the screens offer "Abrir no Cadex".
    public var inCadex: (PanelProjectRef) -> Bool = { _ in false }
    /// "Enviar mensagem a um agente", "Caixa de entrada ↗".
    public var openInbox: (PanelProjectRef) -> Void = { _ in }
    public init() {}
}

/// The project screen (MemoryProject.dc.html, upstream's /w/{ws}/{project}, print 09): the trail,
/// the title with "Abrir no Cadex" and "Enviar mensagem a um agente", the five tabs with "Caixa de
/// entrada ↗" and "Grafo de links ↗", and the chosen tab under them.
@MainActor
final class PanelProjectView: PanelScreen {
    let ref: PanelProjectRef
    private(set) var data: PanelProjectData
    let actions: PanelProjectActions
    let now: Date
    private(set) var tab: PanelProjectTab
    private let body = PanelText.column([], gap: MP.Page.gap)
    /// The Sessões tab's filters (upstream's `state=open`, `sort=events`).
    var openOnly = false
    var byEvents = false
    var tokenFilter = PanelTokenFilter()
    var sessionList: PanelSessionList?

    init(_ ref: PanelProjectRef, data: PanelProjectData, tab: PanelProjectTab, now: Date = Date(), actions: PanelProjectActions,
         go: @escaping (PanelPlace) -> Void) {
        (self.ref, self.data, self.tab, self.now, self.actions) = (ref, data, tab, now, actions)
        super.init(go: go)
        setAccessibilityLabel(ref.name)
        var buttons: [NSView] = []
        if let open = actions.openInCadex {
            buttons.append(DesignButton.make(T("Open in Cadex", "Abrir no Cadex"), .secondary) { [ref] in open(ref, nil) })
        }
        buttons.append(DesignButton.make(T("Message an agent", "Enviar mensagem a um agente"), .primary) { [actions, ref] in actions.openInbox(ref) })
        let tabs = PanelTabsView(PanelProjectTab.allCases.map(\.title), chosen: PanelProjectTab.allCases.firstIndex(of: tab) ?? 0) { [weak self] index in
            guard let self else { return }
            self.go(.project(ref, PanelProjectTab.allCases[index]))
        }
        let links = [PanelLink(T("Inbox ↗", "Caixa de entrada ↗"), size: DesignTokens.FontSize.panel) { [actions, ref] in actions.openInbox(ref) },
                     PanelLink(T("Link graph ↗", "Grafo de links ↗"), size: DesignTokens.FontSize.panel) { [weak self] in self?.go(.section(.graph)) }]
        let tabRow = PanelText.row([tabs, PanelText.spring()] + links, gap: MP.Head.gap)
        fill([trail(PanelPlace.project(ref, tab).crumbs), heading(ref.name, buttons: buttons), tabRow, body])
        column.setCustomSpacing(UILooks.pt(MP.Head.titleGap), after: column.arrangedSubviews[0])
        tabsView = tabs
        select(tab)
    }

    private(set) var tabsView: PanelTabsView?

    /// The tab's content in place (the same project, another tab: no new read).
    func select(_ next: PanelProjectTab) {
        tab = next
        if let tabsView, let row = tabsView.superview as? NSStackView, let index = row.arrangedSubviews.firstIndex(of: tabsView) {
            let fresh = PanelTabsView(PanelProjectTab.allCases.map(\.title), chosen: PanelProjectTab.allCases.firstIndex(of: next) ?? 0) { [weak self] i in
                guard let self else { return }
                self.go(.project(self.ref, PanelProjectTab.allCases[i]))
            }
            row.removeArrangedSubview(tabsView)
            tabsView.removeFromSuperview()
            row.insertArrangedSubview(fresh, at: index)
            self.tabsView = fresh
        }
        let views: [NSView] = switch next {
        case .overview: overviewTab()
        case .agents: agentsTab()
        case .tokens: tokensTab()
        case .sessions: sessionsTab()
        case .knowledge: knowledgeTab()
        }
        body.setViews(views, in: .top)
        for view in views { view.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
    }

    /// New data for the same screen (a filter read again).
    func replace(sessions: [PanelSession]? = nil, tokens: PanelTokenReport? = nil) {
        if let sessions { data.sessions = sessions }
        if let tokens { data.tokens = tokens }
        select(tab)
    }

    // MARK: Visão geral

    private func overviewTab() -> [NSView] {
        let p = data.project
        let items: [(String, String, Bool, String, () -> Void)] = [
            (T("Sessions", "Sessões"), PanelWords.number(p.sessions), false, T("Registered activity", "Atividade registrada"), { [weak self] in self?.showSessions(open: false, events: false) }),
            (T("Captured events", "Eventos capturados"), PanelWords.number(p.events), false, T("Busiest sessions first", "Sessões mais movimentadas primeiro"), { [weak self] in self?.showSessions(open: false, events: true) }),
            (T("Compiled pages", "Páginas compiladas"), PanelWords.number(p.pages), false, T("Knowledge for recall", "Conhecimento para consulta"), { [weak self] in self?.goTab(.knowledge) }),
            (T("Open sessions", "Sessões abertas"), PanelWords.number(p.open), true, T("Only sessions not ended", "Somente sessões não encerradas"), { [weak self] in self?.showSessions(open: true, events: false) }),
            (T("Tokens (in / out)", "Tokens (entrada / saída)"), PanelWords.inOut(data.summary.tokens), false, T("Reported session totals", "Totais de sessões informados"), { [weak self] in self?.goTab(.tokens) }),
        ]
        let stats = items.map { title, value, amber, note, press -> NSView in
            let stat = PanelStat(title, value: value, amber: amber, note: note)
            stat.onPress = press
            return stat
        }
        let row = NSStackView(views: stats)
        row.distribution = .fillEqually
        row.spacing = UILooks.pt(MP.Stat.gridGap)
        let capture = PanelText.line(PanelWords.projectCapture(p.lastActivity, open: p.open, now: now), size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        var line: [NSView] = [capture, PanelText.spring()]
        if !data.summary.agents.isEmpty {
            line.append(PanelText.line(T("Agents", "Agentes"), size: DesignTokens.FontSize.meta, color: MP.Head.meta))
            for agent in data.summary.agents {
                let chip = PanelPress()
                chip.hold(PanelChip.make(PanelWords.agents([agent.agent]) + " · " + PanelWords.number(agent.sessions), .agent, dot: true), padding: NSEdgeInsets())
                chip.onPress = { [weak self] in guard let self else { return }; self.go(.agent(self.ref, agent.agent)) }
                chip.setAccessibilityElement(true)
                chip.setAccessibilityRole(.link)
                chip.setAccessibilityLabel(PanelWords.agents([agent.agent]))
                line.append(chip)
            }
        }
        return [row, PanelText.row(line, gap: MP.Chip.gap), mailbox()]
    }

    private func mailbox() -> NSView {
        let title = PanelText.line(T("Mailbox", "Caixa de mensagens"), size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary,
                                   weight: DesignTokens.FontWeight.semibold)
        let open = DesignButton.make(T("Open inbox", "Abrir caixa de entrada"), .secondary) { [actions, ref] in actions.openInbox(ref) }
        var head: [NSView] = [title]
        if data.summary.mailboxTotal > 0 { head.append(PanelChip.make(T("\(data.summary.mailboxTotal) pending", "\(data.summary.mailboxTotal) pendentes"), .amber)) }
        var rows: [NSView] = []
        if data.summary.messages.isEmpty {
            rows.append(PanelText.line(T("No pending message.", "Nenhuma mensagem pendente."), size: DesignTokens.FontSize.meta, color: MP.Head.meta))
        }
        for m in data.summary.messages {
            let subject = PanelText.line(m.subject ?? m.snippet, size: DesignTokens.FontSize.panel, color: DesignTokens.Color.textPrimary,
                                         weight: DesignTokens.FontWeight.medium)
            var tags: [NSView] = []
            if let sender = m.sender { tags.append(PanelChip.make(T("from ", "de ") + sender.replacingOccurrences(of: "default/", with: ""), .neutral)) }
            tags.append(PanelText.line(m.snippet, size: DesignTokens.FontSize.meta, color: MP.Head.meta))
            let when = PanelText.line(m.created.map { PanelWords.ago($0, now: now) } ?? "", size: DesignTokens.FontSize.meta, color: MP.Head.meta)
            rows.append(PanelText.row([PanelText.column([subject, PanelText.row(tags, gap: MP.Chip.gap)], gap: MP.Chip.padding.top), PanelText.spring(), when],
                                      gap: MP.Head.gap))
        }
        let left = PanelText.column([PanelText.row(head, gap: MP.Chip.gap)] + rows, gap: MP.Chip.gap)
        for row in rows { row.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true }
        let row = PanelText.row([left, open], gap: MP.Head.gap)
        row.alignment = .top
        // The messages take the row; the button keeps its size at the right (the board).
        left.setHuggingPriority(.defaultLow, for: .horizontal)
        open.setContentHuggingPriority(.required, for: .horizontal)
        let box = PanelScreen.box(row)
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.group)
        box.setAccessibilityLabel(title.stringValue)
        return box
    }

    func goTab(_ next: PanelProjectTab) { go(.project(ref, next)) }

    /// A number clicked: the Sessões tab with upstream's filters for it, read again.
    func showSessions(open: Bool, events: Bool) {
        (openOnly, byEvents) = (open, events)
        reloadSessions()
        goTab(.sessions)
    }
}
