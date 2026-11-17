import AppKit
import Icons
import Menus
import StateGlyph
import Strings
import UILooks

/// The bell's popover (docs/spec/agents.md, Atenção and Quadro; docs/design/work-frame/screens.md,
/// Bell; components.popover and components.bell): "Needs you" with a card per open request, Allow
/// and Deny when its hook waits, "Go to tab" always, and the latest that finished or failed under
/// "EARLIER"; "Activity", the timeline. It grows with what it holds (no scroll): a few cards, then
/// "N more". Reads only while it shows. Nothing is answered without a click on a card.
@MainActor
public final class AgentAttentionView: NSView {
    typealias Look = DesignTokens.Bell
    /// "needs" or "feed": what the popover shows (Activity is the feed).
    public var subtab = "needs" { didSet { if subtab != oldValue { render() } } }
    /// The terminal a card or a feed line belongs to; nil key: none known.
    public var onGoTo: ((String?, Int32) -> Void)?
    public var onEnable: (() -> Void)?
    /// Drawn again (a request came or went, Activity switched): the popover sizes itself again.
    public var onRender: (() -> Void)?

    let attention = AgentAttention.shared
    /// The timeline's filter (docs/spec/agents.md, Atenção): a kind and a project.
    let kindFilter = NSPopUpButton()
    let projectFilter = NSPopUpButton()
    static let kinds: [(AgentFeedEntry.Kind?, String)] = [
        (nil, T("Everything", "Tudo")), (.finished, T("Finished", "Terminou")), (.permission, T("Permissions", "Permissões")),
        (.question, T("Questions", "Perguntas")), (.failed, T("Failures", "Falhas")), (.taskCreated, T("Tasks", "Tarefas")),
        (.note, T("Notes", "Avisos")),
    ]
    /// The most cards and lines it shows: past them, "N more" (the popover has no scroll).
    static let maxCards = 4
    static let maxEarlier = 3
    static let maxFeed = 12
    private let stack = NSStackView()
    private var token: UUID?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Reads only while it shows: in a window and not hidden.
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

    /// What the owner typed in each question's field, by card and question, kept across renders.
    private var drafts: [String: String] = [:]
    /// The field the owner was typing in, to give it the keyboard back after a render.
    private var typing: String?

    public func render() {
        defer { onRender?() }
        let live = Set(attention.cards.map { $0.id + "\u{1}" + $0.message })
        drafts = drafts.filter { live.contains($0.key) }
        if let field = window?.firstResponder as? NSTextView, field.isFieldEditor, field.delegate is AnswerField {} else { typing = nil }
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        add(header(), padding: DesignTokens.Popover.Header.padding, line: true)
        guard attention.isEnabled else {
            return note(T("Attention is off (agents.attention).", "A atenção está desligada (agents.attention)."), button: T("Turn On", "Ligar"))
        }
        if subtab == "feed" { return renderFeed() }
        let cards = attention.cards
        if cards.isEmpty { note(T("No agent needs you now.", "Nenhum agente precisa de você agora.")) }
        for request in cards.prefix(Self.maxCards) { add(card(request), padding: Look.Card.padding, line: true) }
        if cards.count > Self.maxCards {
            note(T("\(cards.count - Self.maxCards) more on the board", "Mais \(cards.count - Self.maxCards) no quadro"))
        }
        renderEarlier()
    }

    /// "Needs you" and its count; "Activity" switches to the timeline and back.
    private func header() -> NSView {
        typealias H = DesignTokens.Popover.Header
        let title = AgentBellParts.label(subtab == "feed" ? T("Activity", "Atividade") : T("Needs you", "Precisa de você"),
                                         size: H.Title.fontSize, weight: H.Title.weight, color: DesignTokens.Color.textPrimary)
        var views: [NSView] = [title]
        let count = attention.cards.count
        if subtab != "feed", count > 0 {
            let chip = AgentBellParts.label("\(count)", size: H.Count.fontSize, weight: H.Count.weight, color: H.Count.color)
            chip.wantsLayer = true
            chip.layer?.backgroundColor = H.Count.bg.cgColor
            chip.layer?.cornerRadius = UILooks.pt(H.Count.radius)
            chip.alignment = .center
            chip.widthAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(DesignTokens.Badge.minWidth + H.Count.padding.left * 2)).isActive = true
            views.append(chip)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        views.append(spacer)
        let other = subtab == "feed" ? T("Needs you", "Precisa de você") : T("Activity", "Atividade")
        views.append(AgentBellParts.button(other, .quiet) { [weak self] in
            guard let self else { return }
            self.subtab = self.subtab == "feed" ? "needs" : "feed"
        })
        let row = NSStackView(views: views)
        row.spacing = UILooks.pt(DesignTokens.Tab.gap)
        return row
    }

    private func card(_ request: AgentRequest) -> NSView {
        typealias C = Look.Card
        // An agent that said nothing more than "blocked" (a report with no text) left a card
        // with only its button (2026-11-16, plan 24 F).
        let title = request.title.trimmingCharacters(in: .whitespaces)
        let heading: String
        switch request.kind {
        case .permission: heading = title.isEmpty ? T("Waiting for a permission", "Esperando uma permissão") : T("Wants to run \(title)", "Quer rodar \(title)")
        case .question: heading = T("Asks a question", "Faz uma pergunta")
        }
        var views: [NSView] = [AgentBellParts.line(.needs, glyph: C.glyph,
                                                   AgentBellParts.label(heading, size: C.Title.fontSize, weight: C.Title.weight, color: DesignTokens.Color.textPrimary),
                                                   time: AgentTime.short(since: request.at))]
        if request.kind == .question, !title.isEmpty {
            views.append(AgentBellParts.label(title, size: Look.Question.fontSize, color: Look.Question.color, wraps: true))
        } else if !request.detail.isEmpty {
            views.append(command(request.detail))
        }
        views.append(AgentBellParts.label([request.project, request.session, request.account].filter { !$0.isEmpty }.joined(separator: " · "),
                                          size: Look.Meta.fontSize, color: Look.Meta.color))
        if request.kind == .question, !request.options.isEmpty {
            // Each option as a button, and words of one's own in the field (ADR 0036): typed in
            // the agent's terminal only if it still asks this.
            let asked = request.message
            let options = request.options.prefix(AgentAnswer.maxOptions - 1).enumerated().map { index, option in
                AgentBellParts.button(option, .secondary) { [weak self] in self?.attention.answerQuestion(request.id, asked: asked, .option(index)) }
            }
            let choices = NSStackView(views: Array(options))
            choices.spacing = UILooks.pt(Look.buttonGap)
            views.append(choices)
            // Every report re-renders the cards: what the owner is typing comes back, focus too.
            let draftKey = request.id + "\u{1}" + asked
            let field = AgentBellParts.answerField(draft: drafts[draftKey] ?? "", focused: typing == draftKey,
                                                   edit: { [weak self] words in self?.drafts[draftKey] = words; self?.typing = draftKey },
                                                   send: { [weak self] words in
                self?.drafts[draftKey] = nil
                self?.attention.answerQuestion(request.id, asked: asked, .text(words))
            })
            let go = AgentBellParts.button(T("Go to tab", "Ir à aba"), .quiet) { [weak self] in self?.onGoTo?(request.key, request.pid) }
            let row = NSStackView(views: [field, go])
            row.spacing = UILooks.pt(Look.buttonGap)
            views.append(row)
            let box = NSStackView(views: views)
            box.orientation = .vertical
            box.alignment = .leading
            box.spacing = UILooks.pt(C.gap)
            row.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
            return box
        }
        var buttons: [NSView] = []
        if request.canAnswer {
            buttons.append(AgentBellParts.button(T("Allow", "Permitir"), .primary) { [weak self] in self?.attention.approve(request.id) })
            buttons.append(AgentBellParts.button(T("Deny", "Negar"), .secondary) { [weak self] in self?.attention.deny(request.id) })
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.append(spacer)
        buttons.append(AgentBellParts.button(T("Go to tab", "Ir à aba"), .quiet) { [weak self] in self?.onGoTo?(request.key, request.pid) })
        let row = NSStackView(views: buttons)
        row.spacing = UILooks.pt(Look.buttonGap)
        views.append(row)
        let box = NSStackView(views: views)
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = UILooks.pt(C.gap)
        for view in [row] { view.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true }
        return box
    }

    /// The command or file of a permission, in its box.
    private func command(_ text: String) -> NSView {
        typealias K = Look.Command
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = UILooks.monospaced(K.fontSize)
        label.textColor = K.color
        label.maximumNumberOfLines = 4
        let box = NSStackView(views: [label])
        box.edgeInsets = NSEdgeInsets(top: UILooks.pt(K.padding.top), left: UILooks.pt(K.padding.left),
                                      bottom: UILooks.pt(K.padding.bottom), right: UILooks.pt(K.padding.right))
        box.wantsLayer = true
        box.layer?.backgroundColor = K.bg.cgColor
        box.layer?.borderColor = K.border.cgColor
        box.layer?.borderWidth = DesignTokens.Stroke.hairline
        box.layer?.cornerRadius = UILooks.pt(K.radius)
        return box
    }

    /// The latest that finished or failed, a line each.
    private func renderEarlier() {
        let done = attention.feed.filter { $0.kind == .finished || $0.kind == .failed }.prefix(Self.maxEarlier)
        guard !done.isEmpty else { return }
        typealias E = Look.Earlier
        let label = AgentBellParts.label(T("EARLIER", "ANTES"), size: E.Label.fontSize, weight: E.Label.weight, color: E.Label.color)
        add(label, padding: E.Label.padding, line: false)
        for entry in done { add(feedRow(entry), padding: Self.listed(E.Row.padding), line: false) }
    }

    private func renderFeed() {
        if attention.feed.isEmpty { return note(T("Nothing happened yet.", "Nada aconteceu ainda.")) }
        add(filters(), padding: Look.Earlier.Label.padding, line: false)
        let kind = Self.kinds[max(0, kindFilter.indexOfSelectedItem)].0
        let project = projectFilter.indexOfSelectedItem > 0 ? projectFilter.titleOfSelectedItem : nil
        let entries = attention.feed(kind: kind, project: project)
        if entries.isEmpty { return note(T("Nothing of this kind.", "Nada desse tipo.")) }
        for entry in entries.prefix(Self.maxFeed) { add(feedRow(entry), padding: Self.listed(Look.Earlier.Row.padding), line: false) }
    }

    @objc func filterChanged() { render() }

    /// A line of the list: its own padding inside the list's (components.bell.earlier), so its
    /// glyph lines up with the cards'.
    static func listed(_ row: NSEdgeInsets) -> NSEdgeInsets {
        let list = Look.Earlier.listPadding
        return NSEdgeInsets(top: row.top, left: row.left + list.left, bottom: row.bottom, right: row.right + list.right)
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
        row.spacing = UILooks.pt(Look.buttonGap)
        return row
    }

    /// "bell-cards finished · PR #41 ready" with its glyph and when; a click goes to its tab, the
    /// right click marks it unread.
    private func feedRow(_ entry: AgentFeedEntry) -> NSView {
        let state: GlyphState = switch entry.kind {
        case .finished: .done
        case .failed: .failed
        case .permission, .question: .needs
        case .taskCreated, .note: .idle
        }
        let what: String = switch entry.kind {
        case .finished: T("finished", "terminou")
        case .permission: T("asked permission", "pediu permissão")
        case .question: T("asked a question", "fez uma pergunta")
        case .failed: T("failed", "falhou")
        case .taskCreated: T("task created", "tarefa criada")
        case .note: T("said", "avisou")
        }
        let who = entry.session.isEmpty ? entry.project : entry.session
        let text = NSMutableAttributedString(string: "\(who) \(what)", attributes: [
            .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: DesignTokens.Color.textPrimary,
        ])
        if !entry.text.isEmpty {
            text.append(NSAttributedString(string: " · " + entry.text, attributes: [
                .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: Look.Earlier.Row.detail,
            ]))
        }
        let label = NSTextField(labelWithAttributedString: text)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let line = AgentBellParts.line(state, glyph: Look.Earlier.Row.glyph, label, time: AgentTime.short(since: entry.at))
        line.spacing = UILooks.pt(Look.Earlier.Row.gap)
        line.heightAnchor.constraint(equalToConstant: UILooks.pt(Look.Earlier.Row.height)).isActive = true
        let row = AgentRow(line, inset: 0)
        row.hoverFill = DesignTokens.Color.bgButton
        row.onClick = { [weak self] in self?.onGoTo?(entry.key, 0) }
        if let key = entry.key {
            row.onRightClick = { [weak self, weak row] in
                guard let self, let row else { return }
                PopupMenu.show([MenuEntry(T("Mark as Unread", "Marcar como não lido"), icon: .eye) { [weak self] in self?.attention.markUnread(key) }], below: row)
            }
        }
        return row
    }

    /// One block of the popover with its padding, the line under it when `line`.
    private func add(_ view: NSView, padding: NSEdgeInsets, line: Bool) {
        let box = NSStackView(views: [view])
        box.edgeInsets = NSEdgeInsets(top: UILooks.pt(padding.top), left: UILooks.pt(padding.left),
                                      bottom: UILooks.pt(padding.bottom), right: UILooks.pt(padding.right))
        view.widthAnchor.constraint(equalTo: box.widthAnchor, constant: -UILooks.pt(padding.left + padding.right)).isActive = true
        stack.addArrangedSubview(box)
        box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        guard line else { return }
        let rule = NSView()
        rule.wantsLayer = true
        rule.layer?.backgroundColor = Look.Card.borderBottom.cgColor
        rule.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline).isActive = true
        stack.addArrangedSubview(rule)
        rule.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func note(_ text: String, button title: String? = nil) {
        var views: [NSView] = [AgentBellParts.label(text, size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textSecondary, wraps: true)]
        if let title { views.append(AgentBellParts.button(title, .secondary) { [weak self] in self?.onEnable?() }) }
        let box = NSStackView(views: views)
        box.orientation = .vertical
        box.alignment = .leading
        box.spacing = UILooks.pt(Look.Card.gap)
        add(box, padding: Look.Card.padding, line: false)
    }
}
