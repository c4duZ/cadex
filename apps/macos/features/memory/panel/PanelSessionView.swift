import AppKit
import Strings
import UILooks

/// What the session screens ask the app besides going somewhere.
@MainActor
struct PanelSessionScreenActions {
    /// Reads one route again (the token box's filter); nil data: it failed.
    var read: (String, @escaping @MainActor (Data?) -> Void) -> Void = { _, done in done(nil) }
    /// "Abrir no Cadex" (nil: no Cadex project has the folder and no terminal has the session).
    var openInCadex: ((PanelSession) -> Void)?
}

/// The session screen (MemorySession.dc.html, upstream's session timeline, print 12): the trail with
/// "← Sessões de claude-code" and "Recuperações", the title and "Abrir no Cadex", the agent and the
/// times with ⓘ, the token box, the page bar and the observations, a box each. j/k and the arrows
/// walk the observations.
@MainActor
final class PanelSessionView: PanelScreen {
    let ref: PanelProjectRef
    let timeline: PanelTimeline
    private(set) var tokens: PanelTokenReport
    private let actions: PanelSessionScreenActions
    private let tokensHost = PanelText.column([], gap: 0)
    private var filter = PanelTokenFilter()
    private(set) var cards: [FrameBox] = []
    private(set) var chosen: Int?
    let pagerBar: PanelPagerBar
    private let now: Date

    init(_ ref: PanelProjectRef, timeline: PanelTimeline, tokens: PanelTokenReport, now: Date = Date(), actions: PanelSessionScreenActions,
         go: @escaping (PanelPlace) -> Void) {
        (self.ref, self.timeline, self.tokens, self.actions, self.now) = (ref, timeline, tokens, actions, now)
        let id = timeline.session.id
        pagerBar = PanelPagerBar(timeline.pager) { offset in go(.session(ref, id, offset: offset)) }
        super.init(go: go)
        setAccessibilityLabel(T("Session timeline", "Linha do tempo da sessão"))
        let s = timeline.session
        let back = PanelLink("← " + T("Sessions of ", "Sessões de ") + s.agent, size: MP.Breadcrumb.fontSize) { go(.agent(ref, s.agent)) }
        let retrievals = PanelLink(T("Retrievals", "Recuperações"), size: MP.Breadcrumb.fontSize) { go(.retrievals(ref, id, offset: 0)) }
        var buttons: [NSView] = []
        if let open = actions.openInCadex { buttons.append(DesignButton.make(T("Open in Cadex", "Abrir no Cadex"), .secondary) { open(s) }) }
        drawTokens()
        cards = timeline.observations.enumerated().map { card(timeline.offset + $0.offset + 1, $0.element) }
        var views: [NSView] = [trail(PanelPlace.session(ref, id, offset: timeline.offset).crumbs, links: [back, retrievals]),
                               heading(T("Session timeline", "Linha do tempo da sessão"), buttons: buttons), times(), tokensHost, pagerBar]
        if cards.isEmpty { views.append(PanelScreen.note(T("No observation captured in this session.", "Nenhuma observação capturada nesta sessão."))) }
        let list = PanelText.column(cards, gap: MP.Event.listGap)
        for card in cards { card.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        fill(views + [list])
        column.setCustomSpacing(UILooks.pt(MP.Head.titleGap), after: views[0])
        column.setCustomSpacing(UILooks.pt(MP.Head.titleGap), after: views[1])
    }

    /// The agent's chip and "iniciada 18/11 21:13:34 · encerrada 19/11 02:46:59 ⓘ" (local time; the
    /// ISO in the tooltip).
    private func times() -> NSView {
        let s = timeline.session
        let meta = DesignTokens.FontSize.meta
        var words = s.started.map { T("started ", "iniciada ") + PanelWords.clock($0) } ?? ""
        words += s.ended.map { " · " + T("ended ", "encerrada ") + PanelWords.clock($0) } ?? (" · " + T("still open", "ainda aberta"))
        let line = PanelText.line(words, size: meta, color: MP.Head.meta)
        line.toolTip = [s.started, s.ended].compactMap { $0.map(PanelWords.iso) }.joined(separator: " → ")
        var help = T("Captured observations, in order. They were sanitized when captured and show as plain text.",
                     "Observações capturadas, em ordem. Foram sanitizadas na captura e são exibidas como texto simples.")
        if timeline.elsewhere > 0 {
            help += T(" This session also left \(timeline.elsewhere) in another project, not shown here.",
                      " Esta sessão também deixou \(timeline.elsewhere) em outro projeto, não exibidas aqui.")
        }
        return PanelText.row([PanelChip.make(s.agent, .agent), line, PanelHelpButton(help), PanelText.spring()], gap: MP.Chip.gap)
    }

    private func drawTokens() {
        let box = PanelTokensBox(tokens, filter: filter) { [weak self] next in
            guard let self else { return }
            self.filter = next
            self.actions.read(self.ref.extra + "/sessions/" + PanelPath.segment(self.timeline.session.id) + "/tokens" + next.query) { [weak self] answer in
                self?.tokens = PanelTokenReport.parse(answer) ?? PanelTokenReport()
                self?.drawTokens()
            }
        }
        tokensHost.setViews([box], in: .top)
        box.widthAnchor.constraint(equalTo: tokensHost.widthAnchor).isActive = true
    }

    private func card(_ n: Int, _ o: PanelObservation) -> FrameBox {
        typealias E = MP.Event
        let box = FrameBox()
        box.box(bg: E.bg, border: E.border, radius: E.radius)
        let number = PanelText.line("#\(n)", size: E.Number.fontSize, color: E.Number.color)
        let title = PanelText.line(o.title, size: DesignTokens.FontSize.panel, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        let when = PanelText.line(o.created.map { PanelWords.ago($0, now: now) } ?? "", size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        when.toolTip = o.created.map(PanelWords.iso)
        let head = PanelText.row([number, PanelChip.make(o.kind, .neutral), title, PanelText.spring(), when], gap: MP.Chip.gap)
        var parts: [NSView] = [head]
        if !o.body.isEmpty && o.body != o.title {
            let body = NSTextField(wrappingLabelWithString: o.body)
            body.font = UILooks.monospaced(E.Body.fontSize)
            body.textColor = E.Body.color
            body.isSelectable = true
            // Long bodies are cut, as the board's: the whole text stays selectable in the tooltip.
            body.maximumNumberOfLines = Self.bodyLines
            body.lineBreakMode = .byTruncatingTail
            body.cell?.truncatesLastVisibleLine = true
            body.toolTip = o.body.count > 400 ? String(o.body.prefix(400)) + "…" : o.body
            body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            parts.append(body)
        }
        let column = PanelText.column(parts, gap: E.gap)
        for part in parts { part.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        box.hold(column, padding: E.padding)
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.group)
        box.setAccessibilityLabel("#\(n) \(o.kind) \(o.title)")
        return box
    }

    /// An observation's body shows its first lines, as the board's (MemorySession.dc.html, four).
    static let bodyLines = 4

    // MARK: j/k and the arrows

    override func keyDown(with event: NSEvent) {
        switch (event.charactersIgnoringModifiers, event.keyCode) {
        case ("j", _), (_, 125): step(1)
        case ("k", _), (_, 126): step(-1)
        default: super.keyDown(with: event)
        }
    }

    func step(_ by: Int) {
        guard !cards.isEmpty else { return }
        let next = min(max((chosen ?? -by.signum()) + by, 0), cards.count - 1)
        if let chosen { cards[chosen].layer?.borderColor = MP.Event.border.cgColor }
        chosen = next
        cards[next].layer?.borderColor = MP.Field.Focus.border.cgColor
        cards[next].scrollToVisible(cards[next].bounds)
    }
}
