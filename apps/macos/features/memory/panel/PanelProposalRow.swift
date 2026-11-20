import AppKit
import Strings
import UILooks

/// A pending proposal (MemoryReview.dc.html, upstream's pending row): the title, the operation's chip
/// (amber when it rewrites a page), "regra" for _rules/, the kind; the project, the path in mono,
/// "confiança N%", "preparada há X". Opened: upstream's warnings (a rule every session loads; a page
/// replaced, with the current page a click away), Justificativa, Conteúdo proposto, the id, and
/// Aprovar, Rejeitar with the optional reason (500 at most, upstream's field).
@MainActor
final class PanelProposalRow: FrameBox, NSTextFieldDelegate {
    let proposal: PanelProposal
    private let write: (PanelWrite) -> Void
    private let openPage: () -> Void
    private let head = PanelPress()
    private let detail = PanelText.column([], gap: MP.Inbox.gap)
    let reason = NSTextField()
    private(set) var buttons: [NSButton] = []
    private(set) var isOpen = false

    static let reasonLimit = 500

    init(_ proposal: PanelProposal, now: Date, write: @escaping (PanelWrite) -> Void, openPage: @escaping () -> Void) {
        (self.proposal, self.write, self.openPage) = (proposal, write, openPage)
        super.init(frame: .zero)
        box(bg: MP.Box.bg, border: MP.Box.border, radius: MP.Box.radius)
        let title = PanelText.line(proposal.title, size: MP.Table.Row.fontSize, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        var chips: [NSView] = [title, PanelChip.make(proposal.operation, proposal.rewrites ? .amber : .neutral)]
        if proposal.isRule { chips.append(PanelChip.make(T("rule", "regra"), .amber)) }
        if !proposal.kind.isEmpty { chips.append(PanelChip.make(proposal.kind, .neutral)) }
        let path = PanelText.line(proposal.path, size: MP.Mono.fontSize, color: MP.Head.meta)
        path.font = UILooks.monospaced(MP.Mono.fontSize)
        let staged = proposal.staged.map { T("staged ", "preparada ") + PanelWords.ago($0, now: now) } ?? ""
        let meta = PanelText.row([PanelText.line(PanelGraph.name(proposal.project), size: DesignTokens.FontSize.meta, color: MP.Head.meta), path,
                                  PanelText.line(proposal.confidenceLine, size: DesignTokens.FontSize.meta, color: MP.Head.meta),
                                  PanelText.line(staged, size: DesignTokens.FontSize.meta, color: MP.Head.meta), PanelText.spring()], gap: MP.Page.gap / 2)
        let top = PanelText.column([PanelText.row(chips + [PanelText.spring()], gap: MP.Chip.gap), meta], gap: 4)
        head.hold(top, padding: MP.Box.padding)
        head.onPress = { [weak self] in self?.toggle() }
        head.setAccessibilityElement(true)
        head.setAccessibilityRole(.disclosureTriangle)
        head.setAccessibilityLabel("\(proposal.title), \(proposal.operation), \(proposal.path), \(proposal.confidenceLine)")
        detail.isHidden = true
        detail.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(MP.Box.padding.left), bottom: UILooks.pt(MP.Box.padding.bottom),
                                         right: UILooks.pt(MP.Box.padding.right))
        let column = PanelText.column([head, detail], gap: 0)
        for view in [head, detail] { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        hold(column, padding: NSEdgeInsets())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelProposalRow is created in code") }

    func toggle() {
        isOpen.toggle()
        head.setAccessibilityValue(isOpen ? 1 : 0)
        if isOpen && detail.views.isEmpty { fillDetail() }
        detail.isHidden = !isOpen
    }

    private func fillDetail() {
        var views: [NSView] = []
        if proposal.isRule {
            views.append(warning(T("This proposal writes under _rules/. Every agent session loads those pages as instructions. Read the full body before you approve it.",
                                   "Esta proposta grava em _rules/. Toda sessão de agente carrega essas páginas como instruções. Leia o conteúdo completo antes de aprovar.")))
        }
        if proposal.rewrites {
            let link = PanelLink(T("Open the current page", "Abrir a página atual"), size: DesignTokens.FontSize.meta) { [weak self] in self?.openPage() }
            views.append(PanelText.column([warning(T("This proposal replaces an existing page. Compare it with the current page before you approve it.",
                                                     "Esta proposta substitui uma página existente. Compare-a com a página atual antes de aprovar.")), link], gap: 4))
        }
        views.append(block(T("Rationale", "Justificativa"), proposal.rationale, mono: false))
        views.append(block(T("Proposed body", "Conteúdo proposto") + " (\(proposal.editMode))", proposal.body, mono: true))
        let id = PanelText.line("id " + proposal.id, size: MP.Mono.fontSize, color: MP.Head.meta)
        id.font = UILooks.monospaced(MP.Mono.fontSize)
        id.isSelectable = true
        views.append(id)
        reason.placeholderString = T("Reason to reject (optional)", "Motivo da rejeição (opcional)")
        reason.delegate = self
        reason.setAccessibilityLabel(T("Reason to reject", "Motivo da rejeição"))
        let field = FrameField.field(reason)
        field.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(MP.Field.height)).isActive = true
        field.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Inbox.composeWidth)).isActive = true
        buttons = [DesignButton.make(T("Approve", "Aprovar"), .primary) { [weak self] in self?.decide(approve: true) },
                   DesignButton.make(T("Reject", "Rejeitar"), .secondary) { [weak self] in self?.decide(approve: false) }]
        views.append(PanelText.row(buttons + [field, PanelText.spring()], gap: MP.Chip.gap))
        detail.setViews(views, in: .top)
        let inset = detail.edgeInsets.left + detail.edgeInsets.right
        for view in views { view.widthAnchor.constraint(lessThanOrEqualTo: detail.widthAnchor, constant: -inset).isActive = true }
    }

    private func warning(_ text: String) -> NSView {
        let note = PanelScreen.note(text, color: MP.Notice.text)
        let box = FrameBox()
        box.box(bg: MP.Notice.bg, border: MP.Notice.border, radius: MP.Notice.radius)
        box.hold(note, padding: MP.Notice.padding)
        return box
    }

    /// "JUSTIFICATIVA" over the words in a box, whole (the body in mono, as upstream's <pre>).
    private func block(_ title: String, _ text: String, mono: Bool) -> NSView {
        let words = PanelScreen.note(text, color: DesignTokens.Color.textBody)
        if mono { words.font = UILooks.monospaced(MP.Mono.fontSize) }
        words.isSelectable = true
        let inner = FrameBox()
        inner.box(bg: MP.Field.bg, border: nil, radius: MP.Field.radius)
        inner.hold(words, padding: MP.Notice.padding)
        let column = PanelText.column([PanelScreen.label(title), inner], gap: MP.Inbox.fieldGap)
        inner.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    /// Upstream's reason field takes 500 characters.
    func controlTextDidChange(_ obj: Notification) {
        if reason.stringValue.count > Self.reasonLimit { reason.stringValue = String(reason.stringValue.prefix(Self.reasonLimit)) }
    }

    private func decide(approve: Bool) {
        buttons.forEach { $0.isEnabled = false }
        let why = reason.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        write(approve ? .approve(id: proposal.id) : .reject(id: proposal.id, reason: why))
    }

    /// The engine refused: the buttons back.
    func failed() { buttons.forEach { $0.isEnabled = true } }

    /// For tests: Aprovar (0) or Rejeitar (1).
    func press(_ index: Int) { buttons[index].performClick(nil) }
}
