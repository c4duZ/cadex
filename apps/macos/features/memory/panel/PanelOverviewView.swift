import AppKit
import Strings
import UILooks

/// What the overview asks the app; each is a command's work (ADR 0005).
@MainActor
public struct MemoryOverviewActions {
    public var openInbox: () -> Void = {}
    public var openProject: (PanelProject) -> Void = { _ in }
    public var openAgents: (PanelProject) -> Void = { _ in }
    public var openInCadex: (PanelProject) -> Void = { _ in }
    /// A Cadex project has this one's folder: the card offers "Abrir no Cadex".
    public var inCadex: (PanelProject) -> Bool = { _ in false }
    public init() {}
}

/// Visão geral (MemoryOverview.dc.html, upstream's "Painel de memória", print 01): the title and
/// "Abrir caixa de entrada", the five numbers (a click orders the cards), the capture lines, the
/// inbox notice, "Seus projetos" with the filter, the scope and the order, and the cards. The keys:
/// the arrows choose a card, Enter opens its memory, ⌘O opens it in Cadex.
@MainActor
public final class MemoryOverviewView: NSView {
    private let actions: MemoryOverviewActions
    private let scroll = NSScrollView()
    private let page = PanelFlipped()
    private let column = PanelText.column([], gap: MP.Page.gap)
    private let cardsHost = PanelText.column([], gap: MP.ProjectCard.gridGap)
    private let filterField = NSTextField()
    private let countChip = NSStackView()
    private let scopePopup = PanelPopup(prefix: nil, value: PanelScope.all.title)
    private let sortPopup = PanelPopup(prefix: T("Sort:", "Ordenar:"), value: PanelSort.standard.title)
    private var projectsHead = NSView()
    private(set) var model: PanelOverviewModel?
    private var now = Date()
    private(set) var cards: [PanelCard] = []
    private(set) var stats: [PanelStat] = []
    private var chosen: Int? { didSet { for (index, card) in cards.enumerated() { card.chosen = index == chosen } } }

    public init(actions: MemoryOverviewActions) {
        self.actions = actions
        super.init(frame: .zero)
        scroll.documentView = page
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        page.translatesAutoresizingMaskIntoConstraints = false
        page.hold(column, padding: MP.Page.padding)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            page.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            page.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            page.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        filterField.placeholderString = T("Filter projects…", "Filtrar projetos…")
        filterField.target = self
        filterField.action = #selector(filterChanged)
        (filterField.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
        NotificationCenter.default.addObserver(self, selector: #selector(filterChanged), name: NSControl.textDidChangeNotification, object: filterField)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(T("Memory panel", "Painel de memória"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MemoryOverviewView is created in code") }

    /// The data read; the owner's filter, scope and order are kept across reloads.
    public func show(_ data: PanelOverviewData, now: Date = Date()) {
        self.now = now
        var next = PanelOverviewModel(data: data)
        if let model { (next.sort, next.scope, next.filter) = (model.sort, model.scope, model.filter) }
        model = next
        column.setViews(build(next), in: .top)
        for view in column.arrangedSubviews { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        // "Seus projetos" sits a little further down than the page's gap (the board's margin-top).
        if let index = column.arrangedSubviews.firstIndex(of: projectsHead), index > 0 {
            column.setCustomSpacing(UILooks.pt(MP.Page.gap) + UILooks.pt(MP.Section.marginTop), after: column.arrangedSubviews[index - 1])
        }
        drawCards()
    }

    private func build(_ model: PanelOverviewModel) -> [NSView] {
        let title = PanelText.line(T("Memory panel", "Painel de memória"), size: MP.Head.Title.fontSize, color: DesignTokens.Color.textPrimary,
                                   weight: MP.Head.Title.weight)
        let inbox = DesignButton.make(T("Open inbox", "Abrir caixa de entrada"), .secondary) { [weak self] in self?.actions.openInbox() }
        var views: [NSView] = [PanelText.row([title, PanelText.spring(), inbox], gap: MP.Head.gap), statsRow(model), captureLine(model)]
        if model.data.inbox.pending > 0 { views.append(notice(model.data.inbox)) }
        guard !model.data.projects.isEmpty else {
            return views + [PanelEmpty.view(T("Your workspace starts here", "Seu espaço de trabalho começa aqui"),
                                            T("Projects show up after an agent's first session.", "Os projetos aparecem depois da primeira sessão de um agente."))]
        }
        projectsHead = projectsBar(model)
        return views + [projectsHead, cardsHost]
    }

    private func statsRow(_ model: PanelOverviewModel) -> NSView {
        let items: [(String, Int, PanelSort?, String)] = [
            (T("Projects", "Projetos"), model.data.projects.count, nil, T("Visible in your workspace", "Visíveis no seu espaço de trabalho")),
            (T("Sessions", "Sessões"), model.totalSessions, .sessions, T("Projects with most sessions first", "Projetos com mais sessões primeiro")),
            (T("Captured events", "Eventos capturados"), model.totalEvents, .events, T("Projects with most events first", "Projetos com mais eventos primeiro")),
            (T("Compiled pages", "Páginas compiladas"), model.totalPages, .pages, T("Projects with most pages first", "Projetos com mais páginas primeiro")),
            (T("Open sessions", "Sessões abertas"), model.totalOpen, .open, T("Only sessions not ended", "Somente sessões não encerradas")),
        ]
        stats = items.map { title, value, sort, note in
            let stat = PanelStat(title, value: PanelWords.number(value), amber: sort == .open, note: note)
            stat.onPress = { [weak self] in sort.map { self?.pick($0) } ?? self?.scrollToProjects() }
            return stat
        }
        let row = NSStackView(views: stats)
        row.distribution = .fillEqually
        row.spacing = UILooks.pt(MP.Stat.gridGap)
        return row
    }

    private func captureLine(_ model: PanelOverviewModel) -> NSView {
        let meta = MP.Head.meta
        let last = PanelText.line(PanelWords.lastCapture(model.lastCapture, now: now), size: DesignTokens.FontSize.meta, color: meta)
        let help = PanelHelpButton(PanelWords.captureHelp)
        let dot = PanelText.line("·", size: DesignTokens.FontSize.meta, color: MP.Breadcrumb.separator)
        let capture = PanelText.line(PanelWords.capture(model.data.capture), size: DesignTokens.FontSize.meta, color: meta)
        return PanelText.row([PanelText.row([last, help], gap: MP.Chip.gap), dot, capture, PanelText.spring()], gap: MP.Head.gap)
    }

    private func notice(_ inbox: PanelInbox) -> NSView {
        let box = PanelPress()
        box.box(bg: MP.Notice.bg, border: MP.Notice.border, radius: MP.Notice.radius)
        let words = PanelText.line(PanelWords.inboxNotice(inbox), size: DesignTokens.FontSize.meta, color: MP.Notice.title, weight: DesignTokens.FontWeight.medium)
        box.hold(PanelText.row([words, PanelText.spring()], gap: MP.Chip.gap), padding: MP.Notice.padding)
        box.onPress = { [weak self] in self?.actions.openInbox() }
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.button)
        box.setAccessibilityLabel(words.stringValue)
        return box
    }

    private func projectsBar(_ model: PanelOverviewModel) -> NSView {
        let title = PanelText.line(T("Your projects", "Seus projetos"), size: MP.Section.fontSize, color: DesignTokens.Color.textPrimary,
                                   weight: MP.Section.weight)
        let field = FrameField.field(filterField)
        filterField.font = UILooks.font(MP.Field.fontSize)
        filterField.placeholderAttributedString = NSAttributedString(string: T("Filter projects…", "Filtrar projetos…"), attributes: [
            .font: UILooks.font(MP.Field.fontSize), .foregroundColor: MP.Field.placeholder,
        ])
        field.widthAnchor.constraint(equalToConstant: UILooks.pt(MP.Field.width)).isActive = true
        field.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(MP.Field.height)).isActive = true
        filterField.stringValue = model.filter
        return PanelText.row([title, countChip, PanelText.spring(), field, scopePopup, sortPopup], gap: MP.Section.gap)
    }

    /// The cards again, with the count, the selectors and the empty line, from the model.
    private func drawCards() {
        guard let model else { return }
        countChip.setViews([PanelText.chip(model.shownOfTotal ?? String(model.data.projects.count))], in: .leading)
        scopePopup.say(model.scope.title)
        scopePopup.offer(PanelScope.allCases.map(\.title), chosen: PanelScope.allCases.firstIndex(of: model.scope) ?? 0) { [weak self] index in
            self?.update { $0.scope = PanelScope.allCases[index] }
        }
        sortPopup.say(model.sort.title)
        sortPopup.offer(PanelSort.allCases.map(\.title), chosen: PanelSort.allCases.firstIndex(of: model.sort) ?? 0) { [weak self] index in
            self?.update { $0.sort = PanelSort.allCases[index] }
        }
        let visible = model.visible
        var cardActions = PanelCardActions()
        cardActions.open = { [weak self] in self?.actions.openProject($0) }
        cardActions.agents = { [weak self] in self?.actions.openAgents($0) }
        cards = visible.map { project in
            var own = cardActions
            if actions.inCadex(project) { own.openInCadex = { [weak self] in self?.actions.openInCadex($0) } }
            return PanelCard(project, now: now, actions: own)
        }
        chosen = chosen.flatMap { $0 < cards.count ? $0 : nil }
        guard !cards.isEmpty else {
            return cardsHost.setViews([PanelText.line(T("No project matches these filters", "Nenhum projeto corresponde a estes filtros"),
                                                      size: MP.Empty.Text.fontSize, color: MP.Empty.Text.color)], in: .top)
        }
        cardsHost.setViews(PanelGrid.rows(cards, columns: Int(MP.ProjectCard.columns), gap: MP.ProjectCard.gridGap), in: .top)
        for row in cardsHost.arrangedSubviews { row.widthAnchor.constraint(equalTo: cardsHost.widthAnchor).isActive = true }
    }

    private func update(_ change: (inout PanelOverviewModel) -> Void) {
        guard var next = model else { return }
        change(&next)
        model = next
        drawCards()
    }

    /// A number clicked: its order, shown in the selector.
    func pick(_ sort: PanelSort) { update { $0.pick(sort) } }

    @objc private func filterChanged() {
        guard model?.filter != filterField.stringValue else { return }
        update { $0.filter = filterField.stringValue }
    }

    private func scrollToProjects() { projectsHead.scrollToVisible(projectsHead.bounds) }

    // MARK: The keys

    public override var acceptsFirstResponder: Bool { true }

    public override func keyDown(with event: NSEvent) {
        guard !cards.isEmpty else { return super.keyDown(with: event) }
        let columns = Int(MP.ProjectCard.columns)
        let step: Int? = switch event.keyCode {
        case 123: -1  // ←
        case 124: 1  // →
        case 125: columns  // ↓
        case 126: -columns  // ↑
        default: nil
        }
        if let step { return choose(by: step) }
        if event.keyCode == 36 || event.keyCode == 76, let chosen { return cards[chosen].openMemory() }  // Return, Enter
        super.keyDown(with: event)
    }

    /// ⌘O with a card chosen: Abrir no Cadex (screens-memory.md, the access rules). Before the menu's
    /// ⌘O (open a folder): the window asks the views first.
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers == "o", let chosen, cards[chosen].canOpenInCadex else { return super.performKeyEquivalent(with: event) }
        cards[chosen].openInCadex()
        return true
    }

    func choose(by step: Int) {
        let next = chosen.map { $0 + step } ?? 0
        chosen = min(max(next, 0), cards.count - 1)
        if let chosen { cards[chosen].scrollToVisible(cards[chosen].bounds) }
    }

    /// The card chosen by the keys (memory.open-in-cadex from ⌘K acts on it).
    public var chosenProject: PanelProject? { chosen.map { cards[$0].project } }

    /// For tests.
    var chosenName: String? { chosen.map { cards[$0].project.name } }
    var sortSaid: String { sortPopup.said }
    var scopeSaid: String { scopePopup.said }
    func filter(_ text: String) {
        filterField.stringValue = text
        filterChanged()
    }
}

/// A flipped box: the page reads from the top.
@MainActor
final class PanelFlipped: FrameBox {}
