import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The bell's page (docs/spec/agents.md, Atenção and Quadro): "Needs You",
/// a card per open request, with Allow and Deny when its hook waits and
/// "Go to Terminal" otherwise; and "Feed", the timeline. Reads only while it
/// shows. Nothing is answered without a click on a card.
@MainActor
public final class AgentAttentionView: NSView {
    public var colors = AgentColors() { didSet { render() } }
    /// "needs" or "feed", the sidebar's sub-tab.
    public var subtab = "needs" { didSet { if subtab != oldValue { render() } } }
    /// The terminal a card or a feed line belongs to; nil key: none known.
    public var onGoTo: ((String?, Int32) -> Void)?
    public var onEnable: (() -> Void)?

    let attention = AgentAttention.shared
    /// The feed's filter (docs/spec/agents.md, Atenção): a kind and a project.
    let kindFilter = NSPopUpButton()
    let projectFilter = NSPopUpButton()
    static let kinds: [(AgentFeedEntry.Kind?, String)] = [
        (nil, T("Everything", "Tudo")), (.finished, T("Finished", "Terminou")), (.permission, T("Permissions", "Permissões")),
        (.question, T("Questions", "Perguntas")), (.failed, T("Failures", "Falhas")), (.taskCreated, T("Tasks", "Tarefas")),
    ]
    private let stack = NSStackView()
    private let scroll = NSScrollView()
    private var token: UUID?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        let document = TopLeft()
        document.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor), stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.bottomAnchor.constraint(equalTo: stack.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reads only while it shows: in a window and not hidden (the sidebar
    /// keeps every page in the window and hides the others).
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWatching()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        updateWatching()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updateWatching()
    }

    func updateWatching() {
        let shows = window != nil && !isHiddenOrHasHiddenAncestor
        if shows, token == nil { token = attention.watch { [weak self] in self?.render() } }
        else if !shows, let id = token { attention.stop(id); token = nil }
    }

    var isWatching: Bool { token != nil }

    @objc func filterChanged() { render() }

    func render() {
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        guard attention.isEnabled else {
            return note(T("Attention is off (agents.attention).", "A atenção está desligada (agents.attention)."), button: T("Turn On", "Ligar"))
        }
        if subtab == "feed" { return renderFeed() }
        let cards = attention.cards
        if cards.isEmpty { return note(T("No agent needs you now.", "Nenhum agente precisa de você agora.")) }
        for card in cards { add(self.card(card)) }
    }

    private func card(_ request: AgentRequest) -> NSView {
        let heading: String
        switch request.kind {
        case .permission: heading = T("Wants to use \(request.title)", "Quer usar \(request.title)")
        case .question: heading = request.title
        }
        var views: [NSView] = [AgentText.label(heading, size: 12, weight: .semibold, color: colors.text)]
        if !request.detail.isEmpty {
            let detail = NSTextField(wrappingLabelWithString: request.detail)
            detail.font = .monospacedSystemFont(ofSize: UILooks.pt(11), weight: .regular)
            detail.textColor = colors.text
            detail.maximumNumberOfLines = 4
            views.append(detail)
        }
        views.append(AgentText.label([request.project, request.session, request.account].filter { !$0.isEmpty }.joined(separator: " · "),
                                     size: 11, color: colors.secondary))
        var buttons: [NSView] = []
        if request.canAnswer {
            buttons.append(button(T("Allow", "Permitir")) { [weak self] in self?.attention.approve(request.id) })
            buttons.append(button(T("Deny", "Negar")) { [weak self] in self?.attention.deny(request.id) })
        }
        buttons.append(button(T("Go to Terminal", "Ir ao terminal")) { [weak self] in self?.onGoTo?(request.key, request.pid) })
        let row = NSStackView(views: buttons)
        row.spacing = 6
        views.append(row)
        let box = NSStackView(views: views)
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = 4
        box.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        box.wantsLayer = true
        box.layer?.cornerRadius = 8
        box.layer?.backgroundColor = colors.fill.withAlphaComponent(0.4).cgColor
        return box
    }

    private func renderFeed() {
        if attention.feed.isEmpty { return note(T("Nothing happened yet.", "Nada aconteceu ainda.")) }
        add(filters())
        let kind = Self.kinds[max(0, kindFilter.indexOfSelectedItem)].0
        let project = projectFilter.indexOfSelectedItem > 0 ? projectFilter.titleOfSelectedItem : nil
        let entries = attention.feed(kind: kind, project: project)
        if entries.isEmpty { return note(T("Nothing of this kind.", "Nada desse tipo.")) }
        for entry in entries.prefix(100) {
            let what: String
            switch entry.kind {
            case .finished: what = T("Finished", "Terminou")
            case .permission: what = T("Asked permission", "Pediu permissão")
            case .question: what = T("Asked a question", "Fez uma pergunta")
            case .failed: what = T("Failed", "Falhou")
            case .taskCreated: what = T("Task created", "Tarefa criada")
            }
            let top = AgentText.label(what + (entry.text.isEmpty ? "" : ": " + entry.text), size: 12, color: colors.text)
            let bottom = AgentText.label(([entry.project, entry.session, entry.account].filter { !$0.isEmpty } + [AgentTime.short(since: entry.at)])
                .joined(separator: " · "), size: 11, color: colors.secondary)
            let content = NSStackView(views: [top, bottom])
            content.orientation = .vertical
            content.alignment = .leading
            content.spacing = 1
            let row = AgentRow(content, inset: 6)
            row.hoverFill = colors.fill.withAlphaComponent(0.5)
            row.onClick = { [weak self] in self?.onGoTo?(entry.key, 0) }
            if let key = entry.key {
                row.onRightClick = { [weak self, weak row] in
                    guard let self, let row else { return }
                    PopupMenu.show([MenuEntry(T("Mark as Unread", "Marcar como não lido"), icon: .eye) { [weak self] in self?.attention.markUnread(key) }], below: row)
                }
            }
            add(row)
        }
    }

    /// The kind and project pop-ups, keeping what was picked.
    private func filters() -> NSView {
        let kind = max(0, kindFilter.indexOfSelectedItem)
        let project = projectFilter.titleOfSelectedItem
        kindFilter.removeAllItems()
        kindFilter.addItems(withTitles: Self.kinds.map(\.1))
        kindFilter.selectItem(at: kind)
        projectFilter.removeAllItems()
        projectFilter.addItems(withTitles: [T("All Projects", "Todos os projetos")] + attention.feedProjects)
        if let project, projectFilter.itemTitles.contains(project) { projectFilter.selectItem(withTitle: project) }
        for popup in [kindFilter, projectFilter] {
            popup.controlSize = .small
            popup.target = self
            popup.action = #selector(filterChanged)
        }
        let row = NSStackView(views: [kindFilter, projectFilter])
        row.spacing = 6
        return row
    }

    private func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
    }

    private func note(_ text: String, button title: String? = nil) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = UILooks.font(12)
        label.textColor = colors.secondary
        var views: [NSView] = [label]
        if let title { views.append(button(title) { [weak self] in self?.onEnable?() }) }
        let box = NSStackView(views: views)
        box.orientation = .vertical
        box.alignment = .leading
        box.edgeInsets = NSEdgeInsets(top: 12, left: 6, bottom: 4, right: 6)
        add(box)
    }

    private func button(_ title: String, _ action: @escaping @MainActor () -> Void) -> NSButton {
        let button = AttentionButton(title: title, target: nil, action: nil)
        button.handler = action
        button.target = button
        button.action = #selector(AttentionButton.clicked)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }
}

/// A button that runs a closure.
private final class AttentionButton: NSButton {
    var handler: (@MainActor () -> Void)?
    @objc func clicked() { handler?() }
}

/// A view whose origin is the top left, so the list starts at the top.
private final class TopLeft: NSView {
    override var isFlipped: Bool { true }
}
