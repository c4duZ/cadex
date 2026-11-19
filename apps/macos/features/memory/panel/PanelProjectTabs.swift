import AppKit
import Strings
import UILooks

/// The project screen's other tabs (MemoryProject.dc.html, "Abas sem desenho" and ABA CONHECIMENTO):
/// Agentes (a card per agent), Uso de tokens (the box of the session screen, for the project),
/// Sessões (the agent screen's table with the Agente column, "só abertas" and the order) and
/// Conhecimento (the page tree and the recent activity).
extension PanelProjectView {
    // MARK: Agentes

    func agentsTab() -> [NSView] {
        let head = PanelText.row([PanelScreen.label(T("Agents", "Agentes")), PanelChip.make(T("\(data.agents.count) registered", data.agents.count == 1 ? "1 registrado" : "\(data.agents.count) registrados"), .neutral), PanelText.spring()], gap: MP.Chip.gap)
        guard !data.agents.isEmpty else {
            return [head, PanelEmpty.view(T("Your agents will appear here", "Seus agentes aparecerão aqui"),
                                          T("A captured session registers its agent in this project.", "Uma sessão capturada registra o agente neste projeto."))]
        }
        let cards = data.agents.map(agentCard)
        let rows = PanelGrid.rows(cards, columns: Int(MP.ProjectCard.columns), gap: MP.ProjectCard.gridGap)
        return [head] + rows
    }

    private func agentCard(_ a: PanelAgentCard) -> NSView {
        typealias C = MP.ProjectCard
        let card = PanelPress()
        card.box(bg: C.bg, border: C.border, radius: C.radius)
        let name = PanelText.line(PanelWords.agents([a.agent]), size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary,
                                  weight: DesignTokens.FontWeight.semibold)
        let count = PanelText.line(a.sessions == 1 ? T("1 session recorded", "1 sessão registrada") : T("\(a.sessions) sessions recorded", "\(a.sessions) sessões registradas"), size: C.Foot.fontSize, color: C.Foot.color)
        let state = PanelChip.make(a.open > 0 ? T("\(a.open) open", a.open == 1 ? "1 aberta" : "\(a.open) abertas") : T("no open sessions", "nenhuma sessão aberta"),
                                   a.open > 0 ? .open : .closed, dot: true)
        let top = PanelText.row([PanelText.column([name, count], gap: MP.Chip.padding.top), PanelText.spring(), state], gap: MP.Chip.gap)
        let numbers = PanelText.row([number(T("Reported tokens", "Tokens informados"), a.reported > 0 ? PanelWords.tokens(a.reported) : "—"),
                                     number(T("Measured calls", "Chamadas medidas"), PanelWords.number(a.calls)),
                                     number(T("Usage coverage", "Cobertura de uso"), "\(a.measured)/\(a.sessions)")], gap: C.Number.columnGap)
        numbers.distribution = .fillEqually
        let hint = a.measured == 0 ? T("Usage not reported yet: check the agent's capture setup.", "Uso ainda não informado: confira a captura do agente.")
            : T("\(PanelWords.tokens(a.input)) input · \(PanelWords.tokens(a.output)) output · \(PanelWords.tokens(a.cacheRead + a.cacheWrite)) cache",
                "\(PanelWords.tokens(a.input)) entrada · \(PanelWords.tokens(a.output)) saída · \(PanelWords.tokens(a.cacheRead + a.cacheWrite)) cache")
        let note = PanelText.line(hint, size: C.Foot.fontSize, color: a.measured == 0 ? MP.Notice.title : C.Foot.color)
        let explore = PanelLink(T("Explore sessions ↗", "Explorar sessões ↗"), size: C.Foot.fontSize) { [weak self] in
            guard let self else { return }
            self.go(.agent(self.ref, a.agent))
        }
        let column = PanelText.column([top, numbers, note, explore], gap: C.gap)
        for part in [top, numbers] { part.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        card.hold(column, padding: C.padding)
        card.onPress = { [weak self] in guard let self else { return }; self.go(.agent(self.ref, a.agent)) }
        card.setAccessibilityElement(true)
        card.setAccessibilityRole(.button)
        card.setAccessibilityLabel(name.stringValue)
        return card
    }

    private func number(_ title: String, _ value: String) -> NSView {
        typealias N = MP.ProjectCard.Number
        return PanelText.column([PanelText.line(title, size: N.Label.fontSize, color: N.Label.color),
                                 PanelText.line(value, size: N.Value.fontSize, color: DesignTokens.Color.textPrimary, weight: N.Value.weight)],
                                gap: MP.Chip.padding.top)
    }

    // MARK: Uso de tokens

    func tokensTab() -> [NSView] {
        [PanelTokensBox(data.tokens, filter: tokenFilter) { [weak self] filter in
            guard let self else { return }
            self.tokenFilter = filter
            self.actions.read(self.ref.extra + "/tokens" + filter.query) { [weak self] answer in
                self?.replace(tokens: PanelTokenReport.parse(answer) ?? PanelTokenReport())
            }
        }]
    }

    // MARK: Sessões

    /// The sessions route's query for the tab's filters.
    var sessionsQuery: String {
        let pairs = (openOnly ? ["state=open"] : []) + (byEvents ? ["sort=events"] : [])
        return pairs.isEmpty ? "" : "?" + pairs.joined(separator: "&")
    }

    func reloadSessions() {
        actions.read(ref.extra + "/sessions" + sessionsQuery) { [weak self] answer in
            self?.replace(sessions: PanelSession.list(answer) ?? [])
        }
    }

    func sessionsTab() -> [NSView] {
        let open = NSButton(checkboxWithTitle: T("Open only", "Só abertas"), target: nil, action: nil)
        open.state = openOnly ? .on : .off
        open.font = UILooks.font(MP.Popup.fontSize)
        let toggle = PanelToggle(open) { [weak self] on in
            self?.openOnly = on
            self?.reloadSessions()
        }
        let sort = PanelPopup(prefix: T("Sort:", "Ordenar:"), value: byEvents ? T("Events", "Eventos") : T("Recent", "Recentes"))
        sort.offer([T("Recent", "Recentes"), T("Events", "Eventos")], chosen: byEvents ? 1 : 0) { [weak self] index in
            self?.byEvents = index == 1
            self?.reloadSessions()
        }
        let bar = PanelText.row([PanelScreen.label(T("Sessions", "Sessões")), PanelText.spring(), toggle, sort], gap: MP.Section.gap)
        guard !data.sessions.isEmpty else {
            return [bar, PanelText.line(openOnly ? T("No open session.", "Nenhuma sessão aberta.") : T("No session yet.", "Nenhuma sessão ainda."),
                                        size: MP.Empty.Text.fontSize, color: MP.Empty.Text.color)]
        }
        var acts = PanelSessionActions()
        acts.open = { [weak self] s in guard let self else { return }; self.go(.session(self.ref, s.id, offset: 0)) }
        if let inCadex = actions.openInCadex { acts.openInCadex = { [ref] s in inCadex(ref, s) } }
        let list = PanelSessionList(data.sessions, withAgent: true, now: now, actions: acts)
        sessionList = list
        return [bar, list]
    }

    // MARK: Conhecimento

    func knowledgeTab() -> [NSView] {
        let knowledge = PanelKnowledge(pages: data.pages)
        let tree = PanelPageTree(knowledge) { [weak self] path in guard let self else { return }; self.go(.page(self.ref, path)) }
        var recent: [NSView] = [PanelScreen.label(T("Recent activity", "Atividade recente"))]
        if knowledge.recent.isEmpty {
            recent.append(PanelText.line(T("No compiled memory page yet.", "Nenhuma página de memória compilada ainda."), size: MP.Empty.Text.fontSize,
                                         color: MP.Empty.Text.color))
        }
        for page in knowledge.recent { recent.append(recentRow(page)) }
        let right = PanelText.column(recent, gap: MP.Event.listGap)
        for view in recent.dropFirst() { view.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true }
        let row = PanelText.row([tree, right], gap: MP.Page.padding.left)
        row.alignment = .top
        tree.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.38).isActive = true
        return [row]
    }

    private func recentRow(_ page: PanelPageRow) -> NSView {
        let press = PanelPress()
        press.box(bg: MP.Event.bg, border: MP.Event.border, radius: MP.Event.radius)
        let title = PanelText.line(page.title, size: DesignTokens.FontSize.panel, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        let agent = data.summary.pageAgents[page.path].map { " · " + PanelWords.agents([$0]) } ?? ""
        let path = PanelText.line(page.path + agent, size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        let when = PanelText.line(page.updated.map { PanelWords.ago($0, now: now) } ?? "", size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        press.hold(PanelText.row([PanelText.column([title, path], gap: MP.Chip.padding.top), PanelText.spring(), PanelChip.make(page.kind, .neutral), when],
                                 gap: MP.Chip.gap), padding: MP.Event.padding)
        press.onPress = { [weak self] in guard let self else { return }; self.go(.page(self.ref, page.path)) }
        press.onHover = { [weak press] on in press?.layer?.borderColor = (on ? MP.Field.Focus.border : MP.Event.border).cgColor }
        press.setAccessibilityElement(true)
        press.setAccessibilityRole(.link)
        press.setAccessibilityLabel(page.title)
        return press
    }
}

/// A checkbox of the page that says its state through `changed`.
@MainActor
final class PanelToggle: NSView {
    let button: NSButton
    private let changed: (Bool) -> Void

    init(_ button: NSButton, changed: @escaping (Bool) -> Void) {
        self.button = button
        self.changed = changed
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(toggled)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor), button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor), button.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelToggle is created in code") }

    @objc private func toggled() { changed(button.state == .on) }
}
