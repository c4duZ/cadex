import AppKit
import Strings
import UILooks

/// The agent screen (MemoryAgent.dc.html, upstream's agent page, print 13): the trail, the agent's
/// name and "Enviar mensagem ao agente"; four numbers with their short notes; the amber band while
/// some sessions report no usage; SESSÕES, the table (Enter opens, ⌘O and the right click open in
/// Cadex), and "Mais novas / Mais antigas", 50 a page.
@MainActor
final class PanelAgentView: PanelScreen {
    let ref: PanelProjectRef
    private(set) var data: PanelAgentData
    private(set) var offset = 0
    private let sessionsHost = PanelText.column([], gap: MP.Page.gap)
    private let projectActions: PanelProjectActions
    private(set) var list: PanelSessionList?
    private let now: Date

    static let pageSize = 50

    init(_ ref: PanelProjectRef, data: PanelAgentData, now: Date = Date(), actions: PanelProjectActions, go: @escaping (PanelPlace) -> Void) {
        (self.ref, self.data, self.now, projectActions) = (ref, data, now, actions)
        super.init(go: go)
        let name = PanelWords.agents([data.card.agent])
        setAccessibilityLabel(name)
        let message = DesignButton.make(T("Message the agent", "Enviar mensagem ao agente"), .primary) { actions.openInbox(ref) }
        var views: [NSView] = [trail(PanelPlace.agent(ref, data.card.agent).crumbs), heading(name, buttons: [message]), numbers()]
        if data.card.coverage < 100 { views.append(gapBand()) }
        views += [PanelScreen.label(T("Sessions", "Sessões")), sessionsHost]
        fill(views)
        column.setCustomSpacing(UILooks.pt(MP.Head.titleGap), after: views[0])
        drawSessions()
    }

    private func numbers() -> NSView {
        let c = data.card
        let items = [(T("Recorded sessions", "Sessões registradas"), PanelWords.number(c.sessions),
                      T("\(c.open) without an end event", "\(c.open) sem evento de encerramento")),
                     (T("Reported tokens", "Tokens informados"), c.reported > 0 ? PanelWords.tokens(c.reported) : "—",
                      T("input + output + cache", "entrada + saída + cache")),
                     (T("Measured calls", "Chamadas medidas"), PanelWords.number(c.calls), T("responses of this agent", "respostas deste agente")),
                     (T("Usage coverage", "Cobertura de uso"), "\(c.coverage)%", T("\(c.measured) of \(c.sessions) sessions", "\(c.measured) de \(c.sessions) sessões"))]
        let cells = items.map { title, value, note -> NSView in
            let box = FrameBox()
            box.box(bg: MP.Stat.bg, border: MP.Stat.border, radius: MP.Stat.radius)
            box.hold(PanelText.column([PanelText.line(title, size: MP.Stat.Label.fontSize, color: MP.Stat.Label.color),
                                       PanelText.line(value, size: MP.Stat.Value.fontSize, color: MP.Stat.Value.color, weight: MP.Stat.Value.weight),
                                       PanelText.line(note, size: MP.Stat.Note.fontSize, color: MP.Stat.Note.color)], gap: MP.Stat.gap),
                     padding: MP.Stat.padding)
            box.setAccessibilityElement(true)
            box.setAccessibilityLabel("\(title) \(value), \(note)")
            return box
        }
        let row = NSStackView(views: cells)
        row.distribution = .fillEqually
        row.spacing = UILooks.pt(MP.Stat.gridGap)
        return row
    }

    /// "Há uma lacuna de visibilidade · 44 sessões sem uso informado ⓘ".
    private func gapBand() -> NSView {
        let missing = data.card.sessions - data.card.measured
        let dot = FrameBox()
        dot.box(bg: MP.Notice.dot, border: nil, radius: MP.Chip.dot / 2)
        dot.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Chip.dot)).isActive = true
        dot.heightAnchor.constraint(equalToConstant: UILooks.pt(MP.Chip.dot)).isActive = true
        let title = PanelText.line(T("There is a visibility gap", "Há uma lacuna de visibilidade"), size: DesignTokens.FontSize.panel, color: MP.Notice.title,
                                   weight: DesignTokens.FontWeight.semibold)
        let words = PanelText.line(missing == 1 ? T("1 session without reported usage", "1 sessão sem uso informado")
                                       : T("\(missing) sessions without reported usage", "\(missing) sessões sem uso informado"),
                                   size: DesignTokens.FontSize.panel, color: MP.Notice.text)
        let help = PanelHelpButton(T("Update this agent's client and hooks to capture the model's responses while it works.",
                                     "Atualize o cliente e os hooks deste agente para capturar as respostas do modelo durante o trabalho."))
        let box = FrameBox()
        box.box(bg: MP.Notice.bg, border: MP.Notice.border, radius: MP.Notice.radius)
        box.hold(PanelText.row([dot, title, words, PanelText.spring(), help], gap: MP.Section.gap), padding: MP.Notice.padding)
        box.setAccessibilityElement(true)
        box.setAccessibilityLabel(title.stringValue + ", " + words.stringValue)
        return box
    }

    private func drawSessions() {
        var acts = PanelSessionActions()
        acts.open = { [weak self] s in guard let self else { return }; self.go(.session(self.ref, s.id, offset: 0)) }
        if let inCadex = projectActions.openInCadex { acts.openInCadex = { [ref] s in inCadex(ref, s) } }
        var views: [NSView] = []
        if data.sessions.isEmpty {
            views.append(PanelScreen.note(T("No session of this agent.", "Nenhuma sessão deste agente.")))
        } else {
            let made = PanelSessionList(data.sessions, withAgent: false, now: now, actions: acts)
            list = made
            views.append(made)
        }
        var pages: [NSView] = []
        if offset > 0 { pages.append(PanelLink(T("Newer", "Mais novas"), size: DesignTokens.FontSize.meta) { [weak self] in self?.page(-1) }) }
        if data.more { pages.append(PanelLink(T("Older", "Mais antigas"), size: DesignTokens.FontSize.meta) { [weak self] in self?.page(1) }) }
        if !pages.isEmpty { views.append(PanelText.row(pages + [PanelText.spring()], gap: MP.Pager.gap)) }
        sessionsHost.setViews(views, in: .top)
        for view in views { view.widthAnchor.constraint(equalTo: sessionsHost.widthAnchor).isActive = true }
    }

    /// The next or previous 50, read in place.
    func page(_ step: Int) {
        let next = max(0, offset + step * Self.pageSize)
        projectActions.read(ref.extra + "/agents/" + PanelPath.segment(data.card.agent) + (next > 0 ? "?offset=\(next)" : "")) { [weak self] answer in
            guard let self, let read = PanelAgentData.parse(answer) else { return }
            self.offset = next
            self.data = read
            self.drawSessions()
        }
    }

    /// The agent screen's ⌘O with no row chosen: nothing; with one, the list takes it.
    override func becomeFirstResponder() -> Bool {
        if let list { return window?.makeFirstResponder(list) ?? false }
        return super.becomeFirstResponder()
    }
}
