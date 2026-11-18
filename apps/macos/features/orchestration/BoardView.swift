import AppKit
import StateGlyph
import Strings
import Tabs
import UILooks

typealias BD = DesignTokens.Board

/// What the board asks the app to do.
@MainActor
public struct BoardActions {
    public var open: (String) -> Void = { _ in }
    public var newRace: () -> Void = {}
    public var newTask: () -> Void = {}
    public var load: (@escaping @MainActor ([BoardCard]) -> Void) -> Void = { _ in }
    public init() {}
}

/// The board in the center (plan 30 B; the Board mockup): the filters' pills (All, each race and
/// run, Automations), New race and New task, and the cards in four columns by state. A page
/// (isPage) of the window, "cadex:board"; the columns go to two, then one, on a narrow window.
@MainActor
public final class BoardDocument: TabDocument {
    public static let identity = "cadex:board"
    private let actions: BoardActions
    private let page = BoardPage()
    private var cards: [BoardCard] = []
    private var filter: String?
    public var view: NSView { page }
    public var title: String { T("Board", "Quadro") }
    public var identity: String { Self.identity }
    public var hasUnsavedChanges: Bool { false }
    public var onChange: (() -> Void)?
    public var isPage: Bool { true }

    public init(actions: BoardActions) {
        self.actions = actions
        page.wantsLayer = true
        page.layer?.backgroundColor = DesignTokens.Color.bgWindow.cgColor
        reload()
    }

    public func focus() { reload() }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    /// Reads the cards again (the tab shows, a task changed).
    public func reload() {
        actions.load { [weak self] cards in
            guard let self else { return }
            self.cards = cards
            if let filter = self.filter, !cards.contains(where: { $0.filter == filter }) { self.filter = nil }
            self.show()
        }
    }

    private func show() {
        let pills = [pill(T("All", "Tudo"), on: filter == nil) { [weak self] in self?.filter = nil; self?.show() }]
            + BoardColumns.filters(cards).map { item in
                pill("\(item.name)" + (item.name == T("Automations", "Automações") ? "" : " (\(item.count))"), on: filter == item.name) { [weak self] in
                    self?.filter = item.name
                    self?.show()
                }
            }
        let height = BD.Actions.height
        let race = DesignButton.make(T("New race", "Nova corrida"), .secondary, height: height) { [weak self] in self?.actions.newRace() }
        let task = DesignButton.make(T("New task", "Nova tarefa"), .primary, height: height) { [weak self] in self?.actions.newTask() }
        let columns = BoardColumns.sort(cards, filter: filter).map { column, cards in self.column(column, cards) }
        page.show(pills: pills, buttons: [race, task], columns: columns)
    }

    private func pill(_ title: String, on: Bool, run: @escaping () -> Void) -> NSView {
        typealias P = BD.Filters.Pill
        let pill = BoardBox()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = UILooks.pt(P.height) / 2
        pill.layer?.backgroundColor = on ? P.Active.bg.cgColor : nil
        pill.layer?.borderColor = on ? nil : P.Inactive.border.cgColor
        pill.layer?.borderWidth = on ? 0 : DesignTokens.Stroke.hairline
        let label = NSTextField(labelWithString: title)
        label.font = UILooks.font(P.fontSize, weight: on ? P.Active.weight : .regular)
        label.textColor = on ? P.Active.color : P.Inactive.color
        // Centered in the pill's height (pinned to the top it sat high, 2026-11-17).
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: UILooks.pt(P.padding.left)),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -UILooks.pt(P.padding.right)),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            pill.heightAnchor.constraint(equalToConstant: UILooks.pt(P.height)),
        ])
        pill.onPress = run
        pill.setAccessibilityElement(true)
        pill.setAccessibilityRole(.button)
        pill.setAccessibilityLabel(title)
        return pill
    }

    private func column(_ column: BoardColumns.Column, _ cards: [BoardCard]) -> NSView {
        typealias H = BD.Column.Header
        let glyph = boardGlyph(column.state)
        let title = NSTextField(labelWithString: column.title)
        title.font = UILooks.font(DesignTokens.FontSize.body, weight: DesignTokens.FontWeight.semibold)
        title.textColor = DesignTokens.Color.textPrimary
        let count = NSTextField(labelWithString: "\(cards.count)")
        count.font = UILooks.font(DesignTokens.FontSize.body)
        count.textColor = H.count
        let head = NSStackView(views: [glyph, title, count])
        head.spacing = UILooks.pt(H.gap)
        head.edgeInsets = NSEdgeInsets(top: UILooks.pt(H.padding.top), left: UILooks.pt(H.padding.left),
                                       bottom: UILooks.pt(H.padding.bottom), right: UILooks.pt(H.padding.right))
        let views = [head] + cards.map { card in self.card(card, column: column) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILooks.pt(BD.Column.gap)
        for view in views.dropFirst() { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private func card(_ card: BoardCard, column: BoardColumns.Column) -> NSView {
        typealias C = BD.Card
        let box = BoardBox()
        box.wantsLayer = true
        box.layer?.cornerRadius = UILooks.pt(C.radius)
        box.layer?.backgroundColor = (column == .needsYou ? C.tintNeeds : column == .done ? C.tintDone : C.bg).cgColor
        box.layer?.borderColor = C.border.cgColor
        box.layer?.borderWidth = DesignTokens.Stroke.hairline
        let name = boardLabel(card.name, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        name.setContentHuggingPriority(.init(1), for: .horizontal)
        let age = boardLabel(card.age, size: C.Head.Age.fontSize, color: C.Head.Age.color)
        age.setContentCompressionResistancePriority(.required, for: .horizontal)
        let head = NSStackView(views: [boardGlyph(card.state), name, age])
        head.spacing = UILooks.pt(C.Head.gap)
        var views: [NSView] = [head]
        if !card.text.isEmpty {
            let text = NSTextField(wrappingLabelWithString: "")
            let style = NSMutableParagraphStyle()
            style.lineHeightMultiple = C.Text.lineHeight
            text.attributedStringValue = NSAttributedString(string: card.text, attributes: [
                .font: UILooks.font(C.Text.fontSize), .foregroundColor: C.Text.color, .paragraphStyle: style,
            ])
            text.maximumNumberOfLines = 3
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            views.append(text)
        }
        views.append(meta(card))
        if let group = card.group { views.append(groupChip(group)) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILooks.pt(C.gap)
        for view in views where view !== views.last || card.group == nil { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        box.hold(stack, padding: NSEdgeInsets(top: C.padding, left: C.padding, bottom: C.padding, right: C.padding))
        box.onPress = { [weak self] in self?.actions.open(card.id) }
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.button)
        box.setAccessibilityLabel(card.name + ", " + card.text)
        return box
    }

    /// "cadex · Claude          +214 −38".
    private func meta(_ card: BoardCard) -> NSView {
        typealias M = BD.Card.Meta
        var views: [NSView] = [boardLabel(card.project, size: M.fontSize, color: M.color)]
        if !card.agent.isEmpty {
            views += [boardLabel("·", size: M.fontSize, color: DesignTokens.Color.textSeparator), boardLabel(card.agent, size: M.fontSize, color: M.color)]
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        views.append(spacer)
        if let added = card.added, let removed = card.removed {
            views += [boardLabel("+\(added)", size: M.fontSize, color: DesignTokens.Color.accentGreenText),
                      boardLabel("−\(removed)", size: M.fontSize, color: DesignTokens.Color.accentRedText)]
        }
        let row = NSStackView(views: views)
        row.spacing = UILooks.pt(M.gap)
        return row
    }

    private func groupChip(_ text: String) -> NSView {
        typealias G = BD.GroupChip
        let chip = BoardBox()
        chip.wantsLayer = true
        chip.layer?.backgroundColor = G.bg.cgColor
        chip.layer?.cornerRadius = UILooks.pt(G.radius)
        chip.hold(boardLabel(text, size: G.fontSize, color: G.color, weight: G.weight), padding: G.padding)
        return chip
    }
}

@MainActor
func boardLabel(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = UILooks.font(size, weight: weight)
    label.textColor = color
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.cell?.wraps = false
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

@MainActor
func boardGlyph(_ state: GlyphState) -> NSView {
    let side = DesignTokens.Pane.Header.glyph
    let glyph = StateGlyphView(size: side, state: state)
    glyph.widthAnchor.constraint(equalToConstant: UILooks.pt(side)).isActive = true
    glyph.heightAnchor.constraint(equalToConstant: UILooks.pt(side)).isActive = true
    return glyph
}
