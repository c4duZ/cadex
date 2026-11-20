import AppKit
import Strings
import UILooks

/// Nova mensagem (MemoryInbox.dc.html, upstream's composer): Do projeto, Para o projeto ⓘ (follows
/// Do projeto until changed), Para o agente ⓘ (only the agents registered in the destination;
/// none: the popup says so and the button stays off), Assunto ("opcional · até 200"), Mensagem with
/// "Texto simples · segredos são removidos" and the count, the note that sending never starts the
/// agent, and "Colocar mensagem na fila". The result takes the note's place: queued, with "Ver
/// enviadas", or the engine's words.
@MainActor
final class PanelComposeBox: NSView, NSTextViewDelegate, NSTextFieldDelegate {
    typealias I = MP.Inbox
    let box: PanelMailbox
    private let write: (PanelMessageWrite) -> Void
    private let viewSent: (PanelProjectRef) -> Void
    let fromPopup = PanelPopup(prefix: nil, value: "")
    let toPopup = PanelPopup(prefix: nil, value: "")
    let agentPopup = PanelPopup(prefix: nil, value: "")
    let subjectField = NSTextField()
    let bodyView = NSTextView()
    private let count = PanelText.line("", size: DesignTokens.FontSize.meta, color: MP.Head.meta)
    private let result = PanelText.row([], gap: MP.Chip.gap)
    private(set) var queueButton: NSButton!
    private(set) var from: PanelProjectRef?
    private(set) var to: PanelProjectRef?
    private(set) var agent: String?
    private var sending = false

    init(_ box: PanelMailbox, write: @escaping (PanelMessageWrite) -> Void, viewSent: @escaping (PanelProjectRef) -> Void) {
        (self.box, self.write, self.viewSent) = (box, write, viewSent)
        from = box.project ?? box.scopes.first?.project
        to = from
        super.init(frame: .zero)
        let title = PanelText.line(T("New message", "Nova mensagem"), size: MP.Section.fontSize, color: DesignTokens.Color.textPrimary,
                                   weight: MP.Section.weight)
        subjectField.placeholderString = T("What needs to happen?", "O que precisa ser feito?")
        subjectField.delegate = self
        let subjectBox = FrameField.field(subjectField)
        subjectBox.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(MP.Field.height)).isActive = true
        subjectField.setAccessibilityLabel(T("Subject", "Assunto"))
        bodyView.delegate = self
        bodyView.setAccessibilityLabel(T("Message", "Mensagem"))
        bodyView.setAccessibilityHelp(T("Describe the request, the context and what a good result looks like.",
                                        "Descreva o pedido, o contexto e o resultado esperado."))
        let area = FrameField.area(bodyView, height: I.bodyHeight)
        let meta = PanelText.row([PanelText.line(T("Plain text · secrets are scrubbed", "Texto simples · segredos são removidos"),
                                                 size: DesignTokens.FontSize.meta, color: MP.Head.meta), PanelText.spring(), count], gap: MP.Chip.gap)
        let message = PanelText.column([area, meta], gap: I.fieldGap)
        for view in [area, meta] { view.widthAnchor.constraint(equalTo: message.widthAnchor).isActive = true }
        queueButton = DesignButton.make(T("Queue message", "Colocar mensagem na fila"), .primary, fill: true) { [weak self] in self?.queue() }
        let views: [NSView] = [
            title,
            field(T("From project", "Do projeto"), side: nil, fromPopup),
            field(T("To project", "Para o projeto"), side: PanelHelpButton(T("Defaults to the source project. Choose another project for a cross-project message.",
                                                                              "Por padrão, o projeto de origem. Escolha outro projeto para enviar uma mensagem entre projetos.")), toPopup),
            field(T("To agent", "Para o agente"), side: PanelHelpButton(T("Only agents registered in the destination project are shown.",
                                                                           "Somente agentes registrados no projeto de destino são exibidos.")), agentPopup),
            field(T("Subject", "Assunto"), side: PanelText.line(T("optional · up to 200", "opcional · até 200"), size: DesignTokens.FontSize.meta,
                                                                  color: MP.Head.meta), subjectBox),
            field(T("Message", "Mensagem"), side: nil, message),
            result, queueButton,
        ]
        let column = PanelText.column(views, gap: I.gap)
        for view in views.dropFirst() { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        let frame = PanelScreen.box(column)
        frame.translatesAutoresizingMaskIntoConstraints = false
        addSubview(frame)
        NSLayoutConstraint.activate([
            frame.topAnchor.constraint(equalTo: topAnchor), frame.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            frame.leadingAnchor.constraint(equalTo: leadingAnchor), frame.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(T("New message", "Nova mensagem"))
        offerProjects()
        note()
        counted()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelComposeBox is created in code") }

    private func field(_ label: String, side: NSView?, _ control: NSView) -> NSView {
        let name = PanelText.line(label, size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        let top = PanelText.row([name, PanelText.spring()] + (side.map { [$0] } ?? []), gap: MP.Chip.gap)
        let column = PanelText.column([top, control], gap: I.fieldGap)
        for view in [top, control] { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        return column
    }

    private var projects: [PanelProjectRef] { box.scopes.map(\.project) }

    private func offerProjects() {
        let names = projects.map(PanelGraph.name)
        let fromIndex = projects.firstIndex { $0 == from } ?? 0
        let toIndex = projects.firstIndex { $0 == to } ?? 0
        fromPopup.say(from.map(PanelGraph.name) ?? "—")
        toPopup.say(to.map(PanelGraph.name) ?? "—")
        fromPopup.offer(names, chosen: fromIndex) { [weak self] i in
            guard let self else { return }
            // Upstream: picking the source moves the destination with it.
            self.from = self.projects[i]
            self.to = self.projects[i]
            self.offerProjects()
        }
        toPopup.offer(names, chosen: toIndex) { [weak self] i in
            guard let self else { return }
            self.to = self.projects[i]
            self.offerProjects()
        }
        offerAgents()
    }

    private func offerAgents() {
        let agents = to.map(box.agents(in:)) ?? []
        if let agent, !agents.contains(agent) { self.agent = nil }
        if agents.isEmpty {
            agentPopup.say(T("No registered agents in this project", "Nenhum agente registrado neste projeto"))
            agentPopup.offer([], chosen: -1) { _ in }
        } else {
            agentPopup.say(agent.map { PanelWords.agents([$0]) } ?? T("Select a registered agent…", "Selecione um agente registrado…"))
            agentPopup.offer(agents.map { PanelWords.agents([$0]) }, chosen: agents.firstIndex { $0 == agent } ?? -1) { [weak self] i in
                self?.agent = agents[i]
                self?.offerAgents()
            }
        }
        agentPopup.setAccessibilityHelp(agents.isEmpty ? T("No agents registered in this project yet. Capture a session or choose another destination.",
                                                           "Nenhum agente registrado neste projeto ainda. Capture uma sessão ou escolha outro projeto de destino.") : nil)
        enable()
    }

    private func enable() {
        let length = bodyView.string.count
        queueButton.isEnabled = !sending && agent != nil && from != nil && to != nil
            && !bodyView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && length <= PanelMessageWrite.bodyLimit
            && subjectField.stringValue.count <= PanelMessageWrite.subjectLimit
        // The primary button's disabled title vanished on its light fill: the whole button dims instead.
        queueButton.alphaValue = queueButton.isEnabled ? 1 : 0.45
    }

    func textDidChange(_ notification: Notification) { counted() }
    func controlTextDidChange(_ obj: Notification) { enable() }

    private func counted() {
        let n = bodyView.string.count
        count.stringValue = PanelWords.number(n) + " / " + PanelWords.number(PanelMessageWrite.bodyLimit)
        count.textColor = n > PanelMessageWrite.bodyLimit ? I.error : MP.Head.meta
        enable()
    }

    /// "Fica na fila até a próxima verificação · Não inicia o agente ⓘ", where the result goes after.
    private func note() {
        let words = NSMutableAttributedString(string: T("Waits for the agent's next check · ", "Fica na fila até a próxima verificação · "), attributes: [
            .font: UILooks.font(DesignTokens.FontSize.meta), .foregroundColor: MP.Head.meta,
        ])
        words.append(NSAttributedString(string: T("Does not start the agent", "Não inicia o agente"), attributes: [
            .font: UILooks.font(DesignTokens.FontSize.meta, weight: DesignTokens.FontWeight.semibold), .foregroundColor: DesignTokens.Color.textPrimary,
        ]))
        let label = NSTextField(labelWithAttributedString: words)
        let help = PanelHelpButton(T("Queued for this agent's next inbox check. Sending a message does not start an agent or run its contents.",
                                     "Na fila para a próxima verificação da caixa de entrada deste agente. Enviar uma mensagem não inicia um agente nem executa seu conteúdo."))
        result.setViews([label, help, PanelText.spring()], in: .leading)
    }

    private func queue() {
        guard let from, let to, let agent else { return }
        sending = true
        enable()
        write(.send(from: from, to: to, agent: agent, subject: subjectField.stringValue, body: bodyView.string))
    }

    /// The engine's answer to the send: queued (the form empties) or its words.
    func finished(_ outcome: Result<Void, PanelReadError>) {
        sending = false
        switch outcome {
        case .success:
            let sentFrom = from
            let words = T("Message queued for \(PanelWords.agents([agent ?? ""])).", "Mensagem na fila para \(PanelWords.agents([agent ?? ""])).")
            let label = PanelText.line(words, size: DesignTokens.FontSize.meta, color: I.sent)
            let link = PanelLink(T("View sent →", "Ver enviadas →"), size: DesignTokens.FontSize.meta) { [weak self] in
                if let sentFrom { self?.viewSent(sentFrom) }
            }
            result.setViews([label, link, PanelText.spring()], in: .leading)
            subjectField.stringValue = ""
            bodyView.string = ""
            counted()
        case .failure(let error):
            let label = PanelScreen.note(error.words, color: I.error)
            result.setViews([label], in: .leading)
            label.widthAnchor.constraint(lessThanOrEqualTo: result.widthAnchor).isActive = true
        }
        enable()
    }

    /// The result line, for tests.
    var resultSaid: String { result.views.compactMap { ($0 as? NSTextField)?.stringValue }.joined() }
    /// For tests.
    func type(subject: String, body: String) {
        subjectField.stringValue = subject
        bodyView.string = body
        counted()
    }
}
