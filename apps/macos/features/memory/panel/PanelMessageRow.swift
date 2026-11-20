import AppKit
import Icons
import Strings
import UILooks

/// A message of the mailbox (MemoryInbox.dc.html, upstream's mail row): the envelope, the subject,
/// "origem → destino", "agente · quando" and the state's chip; a click opens it: the id, the body,
/// upstream's note on collected mail and, in Recebidas, Editar for a queued one (Continuar editando
/// and Descartar alterações for a held one). Editing opens subject and body in place, with "Salvar e
/// recolocar na fila". Each write goes out through `write` (a command, ADR 0005); the screen tells
/// the row what came back.
@MainActor
final class PanelMessageRow: NSView {
    typealias R = MP.Inbox.Row
    let message: PanelMail
    let mailbox: PanelProjectRef
    private let editable: Bool
    private let write: (PanelMessageWrite) -> Void
    private let head = PanelPress()
    private let detail = PanelText.column([], gap: MP.Inbox.detailGap)
    private var chip: NSView?
    private var headRow: NSStackView?
    private(set) var isOpen = false
    private(set) var editing = false
    private(set) var state: String
    let subjectField = NSTextField()
    let bodyView = NSTextView()
    private let problem = PanelScreen.note("", color: MP.Inbox.error)
    private(set) var buttons: [String: NSButton] = [:]

    init(_ message: PanelMail, mailbox: PanelProjectRef, editable: Bool, now: Date, write: @escaping (PanelMessageWrite) -> Void) {
        (self.message, self.mailbox, self.editable, self.write, state) = (message, mailbox, editable, write, message.state)
        super.init(frame: .zero)
        let glyph = NSImageView(image: Icon.envelopeSimple.image(size: UILooks.pt(R.icon)))
        glyph.contentTintColor = R.iconColor
        let subject = PanelText.line(message.title, size: MP.Table.Row.fontSize, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        let route = PanelText.line(message.route, size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textBody)
        let when = message.created.map { PanelWords.ago($0, now: now) } ?? ""
        let meta = PanelText.line(message.agent + (when.isEmpty ? "" : " · " + when), size: DesignTokens.FontSize.meta, color: MP.Head.meta)
        let text = PanelText.column([subject, route, meta], gap: 2)
        for label in [subject, route, meta] { label.widthAnchor.constraint(lessThanOrEqualTo: text.widthAnchor).isActive = true }
        let row = PanelText.row([glyph, text, PanelText.spring()], gap: R.gap)
        headRow = row
        paintChip()
        head.hold(row, padding: R.padding)
        head.onHover = { [weak head] on in head?.box(bg: on ? R.hover : nil, border: nil, radius: R.radius) }
        head.onPress = { [weak self] in self?.toggle() }
        head.setAccessibilityElement(true)
        head.setAccessibilityRole(.disclosureTriangle)
        head.setAccessibilityLabel("\(message.title), \(message.route), \(message.agent), \(PanelMailboxQuery.chipTitle(message.state))")
        detail.isHidden = true
        let column = PanelText.column([head, detail], gap: 0)
        head.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        let inset = NSEdgeInsets(top: 0, left: R.padding.left + R.icon + R.gap, bottom: R.padding.bottom, right: R.padding.right)
        let holder = FrameBox()
        holder.hold(column, padding: NSEdgeInsets())
        detail.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(inset.left), bottom: UILooks.pt(inset.bottom), right: UILooks.pt(inset.right))
        detail.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        holder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(holder)
        NSLayoutConstraint.activate([
            holder.topAnchor.constraint(equalTo: topAnchor), holder.bottomAnchor.constraint(equalTo: bottomAnchor),
            holder.leadingAnchor.constraint(equalTo: leadingAnchor), holder.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelMessageRow is created in code") }

    private func paintChip() {
        let tone: PanelChip.Tone = switch state {
        case "pending": .amber
        case "claimed": .green
        case "editing": .agent
        default: .neutral
        }
        chip?.removeFromSuperview()
        let made = PanelChip.make(PanelMailboxQuery.chipTitle(state), tone, dot: tone != .neutral)
        headRow?.addArrangedSubview(made)
        chip = made
    }

    func toggle() {
        isOpen.toggle()
        head.setAccessibilityValue(isOpen ? 1 : 0)
        if isOpen && !editing { showDetail() }
        detail.isHidden = !isOpen
    }

    /// The opened message: id, body, the note, the actions its state allows.
    private func showDetail() {
        let id = PanelText.line(message.id, size: MP.Mono.fontSize, color: MP.Head.meta)
        id.font = UILooks.monospaced(MP.Mono.fontSize)
        id.isSelectable = true
        let body = PanelScreen.note(message.body, color: DesignTokens.Color.textBody)
        body.isSelectable = true
        var views: [NSView] = [id, body]
        if state == "claimed" {
            views.append(PanelScreen.note(T("Collected by an agent. This does not confirm the request was completed.",
                                            "Coletada por um agente. Isso não confirma que a solicitação tenha sido concluída.")))
        }
        buttons = [:]
        if editable && state == "pending" {
            views.append(actions([button("edit", T("Edit", "Editar"), .secondary) { [weak self] in self?.send(.hold) }]))
        } else if editable && state == "editing" {
            views.append(PanelScreen.note(T("Held while it is edited. Agents cannot collect it until it is saved or discarded.",
                                            "Retida durante a edição. Os agentes não podem coletá-la até que seja salva ou descartada.")))
            views.append(actions([button("resume", T("Continue editing", "Continuar editando"), .secondary) { [weak self] in
                guard let self else { return }
                self.openEditor(subject: self.message.subject ?? "", body: self.message.body)
            }, button("discard", T("Discard changes", "Descartar alterações"), .secondary) { [weak self] in self?.send(.discard) }]))
        }
        views.append(problem)
        problem.isHidden = true
        place(views)
    }

    enum Step { case hold, save, discard }

    private func send(_ step: Step) {
        problem.isHidden = true
        switch step {
        case .hold: write(.hold(id: message.id, mailbox: mailbox))
        case .discard: write(.discard(id: message.id, mailbox: mailbox))
        case .save:
            write(.save(id: message.id, mailbox: mailbox, subject: subjectField.stringValue, body: bodyView.string))
        }
    }

    /// The editor in place of the body: the held note, Assunto, Mensagem, Salvar e recolocar na fila.
    func openEditor(subject: String, body: String) {
        editing = true
        state = "editing"
        paintChip()
        if !isOpen { isOpen = true; detail.isHidden = false }
        subjectField.stringValue = subject
        bodyView.string = body
        let hint = PanelScreen.note(T("This message is held while you edit it. Agents cannot collect it until you save or discard the changes.",
                                      "Esta mensagem fica retida durante a edição. Os agentes não podem coletá-la até que você salve ou descarte as alterações."))
        let subjectBox = FrameField.field(subjectField)
        subjectBox.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(MP.Field.height)).isActive = true
        subjectField.setAccessibilityLabel(T("Subject", "Assunto"))
        bodyView.setAccessibilityLabel(T("Message", "Mensagem"))
        let views: [NSView] = [hint, FrameField.labeled(T("Subject", "Assunto"), subjectBox),
                               FrameField.labeled(T("Message", "Mensagem"), FrameField.area(bodyView, height: MP.Inbox.editHeight)), problem,
                               actions([button("save", T("Save and requeue", "Salvar e recolocar na fila"), .primary) { [weak self] in self?.send(.save) },
                                        button("discard", T("Discard changes", "Descartar alterações"), .secondary) { [weak self] in self?.send(.discard) }])]
        problem.isHidden = true
        place(views)
        window?.makeFirstResponder(bodyView)
    }

    /// The engine refused: its words under the message, the buttons usable again.
    func failed(_ words: String) {
        problem.stringValue = words
        problem.isHidden = false
        for button in buttons.values { button.isEnabled = true }
    }

    private func place(_ views: [NSView]) {
        detail.setViews(views, in: .top)
        for view in views { view.widthAnchor.constraint(lessThanOrEqualTo: detail.widthAnchor, constant: -detail.edgeInsets.left - detail.edgeInsets.right).isActive = true }
    }

    private func button(_ key: String, _ title: String, _ style: DesignButton.Style, _ run: @escaping @MainActor () -> Void) -> NSButton {
        let made = DesignButton.make(title, style) { [weak self] in
            self?.buttons.values.forEach { $0.isEnabled = false }
            run()
        }
        buttons[key] = made
        return made
    }

    private func actions(_ views: [NSView]) -> NSView { PanelText.row(views + [PanelText.spring()], gap: MP.Chip.gap) }

    /// For tests: a button of the opened message, as if clicked.
    func press(_ key: String) { buttons[key]?.performClick(nil) }
}
