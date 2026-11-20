import AppKit
import Icons
import Strings
import UILooks

/// Caixa de entrada dos agentes (MemoryInbox.dc.html, upstream's inbox, print 02): the title and the
/// queue across projects under it (a link per project with mail waiting), "Nova mensagem" at the
/// right; CAIXA DE MENSAGENS DO PROJETO at the left (the project with "· n" waiting, Recebidas |
/// Enviadas, Estado da mensagem, the held banner, the messages, Mais novas / Mais antigas) and Nova
/// mensagem at the right (PanelComposeBox). Each choice is a new place (memory.show-panel); each
/// write a command (`write`); `reload` reads the place again after a save or a discard, as upstream
/// reloads its page.
@MainActor
final class PanelInboxView: PanelScreen {
    typealias I = MP.Inbox
    let box: PanelMailbox
    private let write: (PanelMessageWrite) -> Void
    private let reload: () -> Void
    private(set) var rows: [PanelMessageRow] = []
    private(set) var compose: PanelComposeBox!
    let projectPopup = PanelPopup(prefix: nil, value: "")
    let statePopup = PanelPopup(prefix: nil, value: "")
    private(set) var boxTabs: PanelTabsView!

    init(_ box: PanelMailbox, now: Date = Date(), write: @escaping (PanelMessageWrite) -> Void, reload: @escaping () -> Void,
         go: @escaping (PanelPlace) -> Void) {
        (self.box, self.write, self.reload) = (box, write, reload)
        super.init(go: go)
        setAccessibilityLabel(T("Agents' inbox", "Caixa de entrada dos agentes"))
        compose = PanelComposeBox(box, write: write) { [weak self] from in
            self?.go(.mailbox(PanelMailboxQuery(project: from, outbox: true)))
        }
        let newMessage = DesignButton.make(T("New message", "Nova mensagem"), .primary) { [weak self] in self?.focusCompose() }
        let head = heading(T("Agents' inbox", "Caixa de entrada dos agentes"), buttons: [newMessage])
        let mailbox = PanelScreen.box(mailboxColumn(now: now))
        compose.widthAnchor.constraint(equalToConstant: UILooks.pt(I.composeWidth)).isActive = true
        let columns = PanelText.row([mailbox, compose], gap: I.columnGap)
        columns.alignment = .top
        columns.distribution = .fill
        mailbox.setContentHuggingPriority(.init(1), for: .horizontal)
        fill([head, queueLine(), columns])
        column.setCustomSpacing(UILooks.pt(MP.Empty.gap), after: head)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelInboxView is created in code") }

    override var firstFocus: NSView { box.query.compose ? compose.bodyView : self }

    func focusCompose() { window?.makeFirstResponder(compose.bodyView) }

    /// "Nenhuma mensagem aguardando agentes", or "2 na fila · 1 projeto" and a link per project.
    private func queueLine() -> NSView {
        var views: [NSView] = [PanelText.line(box.queueLine, size: DesignTokens.FontSize.panel, color: MP.Head.meta)]
        for (project, pending) in box.waiting {
            views.append(PanelLink("\(PanelGraph.name(project)) · \(pending)", size: DesignTokens.FontSize.panel) { [weak self] in
                self?.go(.mailbox(PanelMailboxQuery(project: project, state: "pending")))
            })
        }
        return PanelText.row(views + [PanelText.spring()], gap: MP.Chip.gap)
    }

    private var query: PanelMailboxQuery { box.query }

    /// The place with one thing changed; a new mailbox or filter starts at the first page.
    private func with(_ change: (inout PanelMailboxQuery) -> Void) -> PanelPlace {
        var next = query
        next.project = next.project ?? box.project
        next.compose = false
        change(&next)
        return .mailbox(next)
    }

    private func mailboxColumn(now: Date) -> NSView {
        var views: [NSView] = [PanelScreen.label(T("Project mailbox", "Caixa de mensagens do projeto")), controls()]
        if !query.outbox && box.editing > 0 {
            let show = PanelLink(box.editing == 1 ? T("Show message", "Mostrar mensagem") : T("Show messages", "Mostrar mensagens"),
                                 size: DesignTokens.FontSize.meta) { [weak self] in
                guard let self else { return }
                self.go(self.with { $0.state = "editing"; $0.offset = 0 })
            }
            let held = PanelText.line(box.heldLine, size: DesignTokens.FontSize.meta, color: MP.Notice.title, weight: DesignTokens.FontWeight.semibold)
            held.toolTip = box.editing == 1 ? T("Agents cannot collect it until it is saved or discarded.", "Os agentes não podem coletá-la até que seja salva ou descartada.")
                : T("Agents cannot collect them until they are saved or discarded.", "Os agentes não podem coletá-las até que sejam salvas ou descartadas.")
            views.append(PanelText.row([held, show, PanelText.spring()], gap: MP.Chip.gap))
        }
        if box.messages.isEmpty {
            views.append(empty())
        } else if let mailbox = box.project {
            rows = box.messages.map { PanelMessageRow($0, mailbox: mailbox, editable: !query.outbox, now: now, write: write) }
            var list: [NSView] = []
            for (index, row) in rows.enumerated() {
                if index > 0 { list.append(PanelScreen.rule()) }
                list.append(row)
            }
            let stack = PanelText.column(list, gap: 0)
            for view in list { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
            views.append(stack)
        }
        if query.offset > 0 || box.more { views.append(pager()) }
        let column = PanelText.column(views, gap: I.gap)
        for view in views.dropFirst() { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        return column
    }

    /// The project (with "· n" waiting), Recebidas | Enviadas, Estado da mensagem.
    private func controls() -> NSView {
        let projects = box.scopes
        let names = projects.map { PanelGraph.name($0.project) + ($0.pending > 0 ? " · \($0.pending)" : "") }
        let chosen = projects.firstIndex { $0.project == box.project } ?? 0
        projectPopup.say(names.isEmpty ? "—" : names[chosen])
        projectPopup.setAccessibilityHelp(T("Project mailbox", "Caixa de mensagens do projeto"))
        projectPopup.offer(names, chosen: chosen) { [weak self] i in
            guard let self else { return }
            self.go(self.with { $0.project = projects[i].project; $0.offset = 0 })
        }
        boxTabs = PanelTabsView([T("Received", "Recebidas"), T("Sent", "Enviadas")], chosen: query.outbox ? 1 : 0) { [weak self] i in
            guard let self, (i == 1) != self.query.outbox else { return }
            self.go(self.with { $0.outbox = i == 1; $0.offset = 0 })
        }
        let states = PanelMailboxQuery.states
        let current = box.state ?? ""
        let stateIndex = states.firstIndex(of: current) ?? 0
        statePopup.say(PanelMailboxQuery.stateTitle(states[stateIndex]))
        statePopup.offer(states.map(PanelMailboxQuery.stateTitle), chosen: stateIndex) { [weak self] i in
            guard let self else { return }
            self.go(self.with { $0.state = states[i]; $0.offset = 0 })
        }
        let label = PanelText.line(T("Message state", "Estado da mensagem"), size: DesignTokens.FontSize.meta,
                                   color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        return PanelText.row([projectPopup, boxTabs, PanelText.spring(), label, statePopup], gap: MP.Chip.gap)
    }

    /// The envelope, "Um pouco de tranquilidade" and upstream's line for this filter.
    private func empty() -> NSView {
        let glyph = NSImageView(image: Icon.envelopeSimple.image(size: UILooks.pt(I.emptyIcon)))
        glyph.contentTintColor = I.Row.iconColor
        let title = PanelText.line(T("A little breathing room", "Um pouco de tranquilidade"), size: MP.Empty.Title.fontSize,
                                   color: DesignTokens.Color.textPrimary, weight: MP.Empty.Title.weight)
        let line = PanelText.line(box.emptyLine, size: MP.Empty.Text.fontSize, color: MP.Empty.Text.color)
        let stack = PanelText.column([glyph, title, line], gap: MP.Empty.gap)
        stack.alignment = .centerX
        stack.edgeInsets = NSEdgeInsets(top: UILooks.pt(I.columnGap * 2), left: 0, bottom: UILooks.pt(I.columnGap * 2), right: 0)
        return stack
    }

    private func pager() -> NSView {
        var views: [NSView] = []
        let size = PanelMailboxQuery.pageSize
        if query.offset > 0 {
            views.append(PanelLink(T("Newer", "Mais novas"), size: DesignTokens.FontSize.panel) { [weak self] in
                guard let self else { return }
                self.go(self.with { $0.offset = max(0, $0.offset - size) })
            })
        }
        views.append(PanelText.spring())
        if box.more {
            views.append(PanelLink(T("Older", "Mais antigas"), size: DesignTokens.FontSize.panel) { [weak self] in
                guard let self else { return }
                self.go(self.with { $0.offset += size })
            })
        }
        return PanelText.row(views, gap: MP.Chip.gap)
    }

    /// What the engine said to a write this screen sent.
    func finished(_ done: PanelMessageWrite, _ answer: Result<Data, PanelReadError>) {
        switch done {
        case .send:
            compose.finished(answer.map { _ in () })
        case .hold(let id, _):
            guard let row = rows.first(where: { $0.message.id == id }) else { return }
            switch answer {
            case .success(let data):
                let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                row.openEditor(subject: o["subject"] as? String ?? "", body: o["body"] as? String ?? row.message.body)
            case .failure(let e): row.failed(e.words)
            }
        case .save(let id, _, _, _), .discard(let id, _):
            switch answer {
            case .success: reload()
            case .failure(let e): rows.first { $0.message.id == id }?.failed(e.words)
            }
        }
    }
}
