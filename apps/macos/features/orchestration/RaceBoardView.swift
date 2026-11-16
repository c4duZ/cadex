import AppKit
import Strings

/// The colors of the board, from the app's theme.
public struct RaceBoardColors: Equatable {
    public var background: NSColor
    public var text: NSColor
    public var secondary: NSColor
    public var accent: NSColor
    public init(background: NSColor, text: NSColor, secondary: NSColor, accent: NSColor) {
        self.background = background
        self.text = text
        self.secondary = secondary
        self.accent = accent
    }
}

/// What the board's buttons do; each runs a command of the feature by its id
/// or a feature's entry point, given by the app (ADR 0005).
public struct RaceBoardActions {
    public var goToTerminal: (Contender) -> Void = { _ in }
    public var review: (Contender) -> Void = { _ in }
    public var pickWinner: (Contender) -> Void = { _ in }
    public var compare: () -> Void = {}
    public var discard: () -> Void = {}
    public init() {}
}

/// One column per contender (docs/spec/orchestration.md, "Corrida"): number
/// and worktree, model · account · machine, state and since when, cost,
/// diff; Go to Terminal, Review and Pick Winner. A header with the prompt
/// and Compare and Discard the Others.
final class RaceBoardView: NSView {
    var colors: RaceBoardColors { didSet { layer?.backgroundColor = colors.background.cgColor } }
    var actions = RaceBoardActions()
    private let header = NSStackView()
    private let columns = NSStackView()
    private let scroll = NSScrollView()

    init(colors: RaceBoardColors) {
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = colors.background.cgColor
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 6
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 24
        columns.distribution = .fillEqually
        let content = NSStackView(views: [header, columns])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 20
        content.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        content.translatesAutoresizingMaskIntoConstraints = false
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor), content.topAnchor.constraint(equalTo: document.topAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor), content.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            document.widthAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// Draws the race again (the board reads, then calls this).
    func show(race: Race, columns cols: [RaceColumn], contenders: [Contender]) {
        header.arrangedSubviews.forEach { $0.removeFromSuperview() }
        columns.arrangedSubviews.forEach { $0.removeFromSuperview() }
        header.addArrangedSubview(label(race.name, size: 18, weight: .semibold, color: colors.text))
        let firstLine = race.prompt.split(separator: "\n").first.map(String.init) ?? ""
        header.addArrangedSubview(label(firstLine, size: 12, color: colors.secondary, lines: 2))
        header.addArrangedSubview(label(T("From \(race.base) · cap US$ \(String(format: "%.2f", race.caps.budgetUsd)) and \(race.caps.maxMinutes) min each",
                                          "De \(race.base) · teto US$ \(String(format: "%.2f", race.caps.budgetUsd)) e \(race.caps.maxMinutes) min cada"),
                                        size: 11, color: colors.secondary))
        let buttons = NSStackView(views: [button(T("Compare…", "Comparar…")) { [weak self] in self?.actions.compare() }])
        if race.winner != nil && !race.discarded {
            buttons.addArrangedSubview(button(T("Discard the Others", "Descartar os outros")) { [weak self] in self?.actions.discard() })
        }
        header.addArrangedSubview(buttons)
        let byId = Dictionary(contenders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for column in cols {
            guard let contender = byId[column.contender] else { continue }
            columns.addArrangedSubview(columnView(column, contender: contender, race: race))
        }
    }

    private func columnView(_ column: RaceColumn, contender: Contender, race: Race) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let title = column.isWinner ? "★ " + column.title : column.title
        stack.addArrangedSubview(label(title, size: 13, weight: .semibold, color: column.isWinner ? colors.accent : colors.text))
        stack.addArrangedSubview(label(column.subtitle, size: 11, color: colors.secondary))
        let state = column.elapsed.isEmpty ? column.state : column.state + " · " + column.elapsed
        stack.addArrangedSubview(label(state, size: 12, color: column.isDiscarded ? colors.secondary : colors.text))
        stack.addArrangedSubview(label(column.cost, size: 12, color: colors.text))
        stack.addArrangedSubview(label(column.diff, size: 12, color: colors.text))
        guard !column.isDiscarded else { return stack }
        stack.addArrangedSubview(button(T("Go to Terminal", "Ir ao terminal")) { [weak self] in self?.actions.goToTerminal(contender) })
        if column.canCompare { stack.addArrangedSubview(button(T("Review", "Revisar")) { [weak self] in self?.actions.review(contender) }) }
        if race.winner == nil { stack.addArrangedSubview(button(T("Pick Winner", "Escolher vencedor")) { [weak self] in self?.actions.pickWinner(contender) }) }
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        return stack
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, lines: Int = 1) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }
}

/// A button that runs a closure: the board's actions are the app's.
final class ClosureButton: NSButton {
    private var run: () -> Void = {}
    convenience init(title: String, action: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        run = action
        target = self
        self.action = #selector(fire)
    }
    @objc private func fire() { run() }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
