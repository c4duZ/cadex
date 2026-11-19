import AppKit
import Menus
import Icons
import Strings
import UILooks

/// The four ways to start (docs/spec/home.md): each runs a command the app gives.
public enum HomeCard: CaseIterable, Sendable {
    case terminal, agent, task, race

    var icon: Icon {
        switch self {
        case .terminal: .terminal
        case .agent: .diamond
        case .task: .gitFork
        case .race: .flag
        }
    }

    var title: String {
        switch self {
        case .terminal: T("Terminal", "Terminal")
        case .agent: T("Agent", "Agente")
        case .task: T("Task", "Tarefa")
        case .race: T("Race", "Corrida")
        }
    }

    var text: String {
        switch self {
        case .terminal: T("A shell in the project's folder. Nothing else.", "Um shell na pasta do projeto. Nada mais.")
        case .agent: T("A terminal already running Claude or Codex, in the account you pick.",
                       "Um terminal já rodando o Claude ou o Codex, na conta que você escolher.")
        case .task: T("A separate copy on a new branch, so it works in parallel with you.",
                      "Uma cópia separada num branch novo, para trabalhar em paralelo com você.")
        case .race: T("The same task given to 2–3 agents; you keep the best.", "A mesma tarefa para 2 ou 3 agentes; você fica com a melhor.")
        }
    }
}

/// What the screen asks the app to do.
@MainActor
public struct HomeActions {
    /// Enter in the prompt, with its text.
    public var submit: (String) -> Void = { _ in }
    /// The project's name (or "@"), the agent chip, the place chip: a menu below the view.
    public var pickProject: (NSView) -> Void = { _ in }
    public var pickAgent: (NSView) -> Void = { _ in }
    public var pickPlace: (NSView) -> Void = { _ in }
    public var card: (HomeCard) -> Void = { _ in }
    public var openRecent: (String) -> Void = { _ in }
    public var removeRecent: (String) -> Void = { _ in }
    /// A recent's right click: the app's menu for that folder.
    public var recentMenu: (String) -> [MenuEntry] = { _ in [] }
    public var openFolder: () -> Void = {}
    public var clone: () -> Void = {}
    /// The shortcut each card shows ("⌘T"), from the keymap.
    public var shortcut: (HomeCard) -> String = { _ in "" }
    /// Open folder's shortcut, from the keymap (it said ⌘O, which ran another command; plan 38 G).
    public var openShortcut: () -> String = { "" }

    public init() {}
}

/// The home screen (docs/spec/home.md; the Home mockup): the greeting, the prompt with its
/// choices, the four cards and the recent projects, in a 760 pt column centered in the window's
/// middle. Only built while shown.
@MainActor
public final class HomeView: NSView, NSTextFieldDelegate {
    public let actions: HomeActions
    let field = NSTextField()
    private let projectButton = HomeClickable()
    private let agentChip = HomeChip()
    private let placeChip = HomeChip()
    private let hint = NSTextField(labelWithString: "")
    private let cards: [HomeCardView]
    private let cardsBox = HomeCardGrid()
    private let recentsBox = NSStackView()
    private let column = NSStackView()
    private var state = HomeState(project: nil, agent: nil)

    public init(actions: HomeActions) {
        self.actions = actions
        cards = HomeCard.allCases.map { HomeCardView($0) }
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HomeView is created in code") }

    public override var isFlipped: Bool { true }

    public func show(_ state: HomeState) {
        self.state = state
        let ask = state.project.map { T("What do you want to do in ", "O que você quer fazer em ") + $0 + "?" } ?? T("What do you want to do?", "O que você quer fazer?")
        let placeholder = NSMutableAttributedString(string: ask, attributes: [.font: UILooks.font(H.Prompt.fontSize), .foregroundColor: H.Prompt.color])
        if let project = state.project, let range = ask.range(of: project, options: .backwards) {
            placeholder.addAttributes([.foregroundColor: H.Prompt.Name.color, .font: UILooks.font(H.Prompt.fontSize, weight: H.Prompt.Name.weight)],
                                      range: NSRange(range, in: ask))
        }
        field.placeholderAttributedString = placeholder
        agentChip.text = state.agent.map { "◆ " + $0 } ?? T("Add an account", "Adicionar uma conta")
        placeChip.text = state.separateCopy ? T("In a separate copy", "Numa cópia separada") : T("In this folder", "Nesta pasta")
        let agent = state.agent?.components(separatedBy: " · ").first ?? "Claude"
        hint.stringValue = state.separateCopy ? T("↩ opens New Task", "↩ abre Nova tarefa") : T("↩ opens a terminal with \(agent)", "↩ abre um terminal com o \(agent)")
        for (card, view) in zip(HomeCard.allCases, cards) { view.setShortcut(actions.shortcut(card)) }
        cardsBox.needsLayout = true
        recentsBox.arrangedSubviews.forEach { $0.removeFromSuperview() }
        recentsBox.addArrangedSubview(recentsHeader())
        for recent in state.recents {
            let row = HomeRecentRow(recent) { [weak self] in self?.actions.removeRecent(recent.folder) }
            row.onPress = { [weak self] in if recent.state != .missing { self?.actions.openRecent(recent.folder) } }
            row.rightMenu = { [weak self] in self?.actions.recentMenu(recent.folder) ?? [] }
            recentsBox.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: recentsBox.widthAnchor).isActive = true
        }
        // Always shown: it holds the only Open folder and Clone…; a first run had no way to open a
        // project but ⌘O (UX audit, 2026-11-18).
        if state.recents.isEmpty {
            typealias R = H.Recent.Header
            recentsBox.addArrangedSubview(homeLabel(T("Open a folder to start a project: its terminals, tasks and memory live there.",
                                                      "Abra uma pasta para começar um projeto: os terminais, as tarefas e a memória dele moram lá."),
                                                    size: DesignTokens.FontSize.body, color: R.color))
        }
        needsLayout = true
    }

    public func focusPrompt() { window?.makeFirstResponder(field) }

    // MARK: Building

    private func build() {
        let greeting = homeLabel(HomeWords.greeting(hour: Calendar.current.component(.hour, from: Date())),
                                 size: H.Greeting.fontSize, color: DesignTokens.Color.textPrimary, weight: H.Greeting.weight, tracking: H.Greeting.tracking)
        let subtitle = homeLabel(T("Pick up where you were, or start something.", "Continue de onde parou, ou comece algo."),
                                 size: H.Greeting.Subtitle.fontSize, color: H.Greeting.Subtitle.color)
        let top = NSStackView(views: [greeting, subtitle])
        top.orientation = .vertical
        top.alignment = .leading
        top.spacing = UILooks.pt(H.Greeting.gap)
        for (index, card) in cards.enumerated() {
            card.onPress = { [weak self] in self?.actions.card(HomeCard.allCases[index]) }
        }
        cardsBox.cards = cards
        recentsBox.orientation = .vertical
        recentsBox.alignment = .leading
        recentsBox.spacing = UILooks.pt(H.Recent.listGap)
        let prompt = promptBox()
        for view in [top, prompt, cardsBox, recentsBox] as [NSView] { column.addArrangedSubview(view) }
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = UILooks.pt(H.Column.gap)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        let width = column.widthAnchor.constraint(equalToConstant: UILooks.pt(H.Column.width))
        width.priority = .defaultHigh
        let side = UILooks.pt(H.Card.padding)
        NSLayoutConstraint.activate([
            width,
            column.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * side),
            column.centerXAnchor.constraint(equalTo: centerXAnchor),
            column.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(H.Column.paddingTop)),
            prompt.widthAnchor.constraint(equalTo: column.widthAnchor),
            cardsBox.widthAnchor.constraint(equalTo: column.widthAnchor),
            recentsBox.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
    }

    /// The prompt, the line, then the choices and what Enter does.
    private func promptBox() -> NSView {
        let box = HomePromptBox()
        box.box(bg: H.Prompt.bg, border: H.Prompt.border, radius: H.Prompt.radius)
        box.onPress = { [weak self] in self?.focusPrompt() }
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = UILooks.font(H.Prompt.fontSize)
        field.textColor = DesignTokens.Color.textPrimary
        field.delegate = self
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        projectButton.onPress = { [weak self] in self.map { $0.actions.pickProject($0.field) } }
        agentChip.onPress = { [weak self] in self.map { $0.actions.pickAgent($0.agentChip) } }
        placeChip.onPress = { [weak self] in self.map { $0.actions.pickPlace($0.placeChip) } }
        hint.font = UILooks.font(H.Choices.Hint.fontSize)
        hint.textColor = H.Choices.Hint.color
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let choices = NSStackView(views: [agentChip, placeChip, spacer, hint])
        choices.spacing = UILooks.pt(H.Choices.gap)
        let pad = H.Choices.padding
        choices.edgeInsets = NSEdgeInsets(top: UILooks.pt(pad.top), left: UILooks.pt(pad.left), bottom: UILooks.pt(pad.bottom), right: UILooks.pt(pad.right))
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = H.Choices.borderTop.cgColor
        for view in [field, line, choices, projectButton] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        let p = H.Prompt.padding
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: UILooks.pt(p.left)),
            field.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -UILooks.pt(p.right)),
            field.topAnchor.constraint(equalTo: box.topAnchor, constant: UILooks.pt(p.top)),
            line.topAnchor.constraint(equalTo: field.bottomAnchor, constant: UILooks.pt(p.bottom)),
            line.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            choices.topAnchor.constraint(equalTo: line.bottomAnchor),
            choices.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            choices.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            choices.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    private func recentsHeader() -> NSView {
        typealias R = H.Recent.Header
        let words = !state.recents.isEmpty ? T("RECENT PROJECTS", "PROJETOS RECENTES") : T("START A PROJECT", "COMECE UM PROJETO")
        let title = homeLabel(words, size: R.fontSize, color: R.color, weight: R.weight, tracking: R.tracking)
        let key = actions.openShortcut()
        let open = link(T("Open folder", "Abrir pasta") + (key.isEmpty ? "" : " " + key)) { [weak self] in self?.actions.openFolder() }
        let dot = homeLabel("·", size: R.fontSize, color: R.color)
        let clone = link(T("Clone…", "Clonar…")) { [weak self] in self?.actions.clone() }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [title, spacer, open, dot, clone])
        row.spacing = UILooks.pt(H.Card.gap)
        row.widthAnchor.constraint(equalToConstant: UILooks.pt(H.Column.width)).priority = .defaultLow
        return row
    }

    private func link(_ text: String, _ run: @escaping () -> Void) -> NSView {
        let button = NSButton(title: text, target: nil, action: nil)
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: UILooks.font(H.Recent.Header.fontSize, weight: DesignTokens.FontWeight.medium), .foregroundColor: H.Recent.Header.color,
        ])
        return HomeAction(button, run)
    }

    // MARK: Layout

    /// The project's name in the placeholder is a button over it.
    public override func layout() {
        super.layout()
        placeProjectButton()
    }

    private func placeProjectButton() {
        guard let project = state.project, field.stringValue.isEmpty, let text = field.placeholderAttributedString?.string,
              let range = text.range(of: project, options: .backwards) else { return projectButton.isHidden = true }
        let font = UILooks.font(H.Prompt.fontSize)
        let before = (String(text[..<range.lowerBound]) as NSString).size(withAttributes: [.font: font]).width
        let name = (project as NSString).size(withAttributes: [.font: UILooks.font(H.Prompt.fontSize, weight: H.Prompt.Name.weight)]).width
        let origin = field.convert(NSPoint(x: before + DesignTokens.Stroke.glyph, y: 0), to: projectButton.superview)
        projectButton.frame = CGRect(x: origin.x, y: origin.y, width: name, height: field.bounds.height)
        projectButton.isHidden = false
    }

    // MARK: The prompt

    public func controlTextDidChange(_ notification: Notification) {
        // "@" opens the project's menu, as the name does (the spec).
        if field.stringValue.hasSuffix("@") {
            field.stringValue.removeLast()
            actions.pickProject(field)
        }
        needsLayout = true
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        actions.submit(text)
        return true
    }
}

/// The four cards in four columns, then two, then one as the column narrows (the spec's narrow
/// window). Flipped, with its height as its intrinsic size from the width it gets: placing the
/// cards and setting a height constraint inside the column's layout left it 0 pt tall and the
/// cards drawn over the greeting (2026-11-17).
@MainActor
final class HomeCardGrid: NSView {
    var cards: [HomeCardView] = [] {
        didSet {
            oldValue.forEach { $0.removeFromSuperview() }
            cards.forEach(addSubview)
        }
    }
    private var height: CGFloat = 0
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }

    override func layout() {
        super.layout()
        let width = bounds.width
        guard width > 0, !cards.isEmpty else { return }
        let gap = UILooks.pt(H.Cards.gap)
        let minimum = UILooks.pt(H.Column.width) / H.Cards.columns - gap
        let columns = width >= minimum * 4 ? 4 : width >= minimum * 2 ? 2 : 1
        let cardWidth = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        var y: CGFloat = 0
        for start in stride(from: 0, to: cards.count, by: columns) {
            let row = Array(cards[start..<min(start + columns, cards.count)])
            let rowHeight = row.map { $0.height(at: cardWidth) }.max() ?? 0
            for (column, card) in row.enumerated() {
                card.frame = CGRect(x: CGFloat(column) * (cardWidth + gap), y: y, width: cardWidth, height: rowHeight)
            }
            y += rowHeight + gap
        }
        let total = max(y - gap, 0)
        if total != height {
            height = total
            invalidateIntrinsicContentSize()
        }
    }
}
