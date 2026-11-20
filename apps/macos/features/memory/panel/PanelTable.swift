import AppKit
import Menus
import Strings
import UILooks

/// A column of a page's table: its title and its share of the width (nil: what the others leave).
struct PanelColumn {
    var title: String
    var share: CGFloat?
}

/// A table of the page (components.memoryPanel.table): the header, then one row per item, a line
/// between them, the row under the pointer lit. Rows may be chosen by the keys; the screen says what
/// a click, Enter, ⌘O and the right click do.
@MainActor
final class PanelTable: NSView {
    typealias TH = MP.Table.Header
    typealias TR = MP.Table.Row
    let columns: [PanelColumn]
    private let stack = PanelText.column([], gap: 0)
    private(set) var rows: [PanelTableRow] = []
    var chosen: Int? { didSet { for (index, row) in rows.enumerated() { row.chosen = index == chosen } } }

    init(_ columns: [PanelColumn]) {
        self.columns = columns
        super.init(frame: .zero)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.table)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelTable is created in code") }

    /// The rows, each a list of cells in the columns' order.
    func show(_ cells: [[NSView]]) {
        let header = line(columns.map { column -> NSView in
            PanelText.line(column.title, size: TH.fontSize, color: TH.color, weight: TH.weight)
        }, padding: TH.padding).holder
        rows = cells.map { row in
            let press = PanelTableRow()
            let (holder, stack) = line(row, padding: TR.padding)
            press.hold(holder, padding: NSEdgeInsets())
            press.cells = stack
            return press
        }
        var views: [NSView] = [header, PanelScreen.rule(TH.border)]
        for row in rows { views += [row, PanelScreen.rule(TR.border)] }
        stack.setViews(views, in: .top)
        for view in views { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        setAccessibilityRowCount(rows.count)
    }

    /// One line of cells, each column as wide as its share.
    private func line(_ cells: [NSView], padding: NSEdgeInsets) -> (holder: NSView, row: NSStackView) {
        let row = PanelText.row(cells, gap: MP.Table.columnGap)
        row.distribution = .fill
        let holder = FrameBox()
        holder.hold(row, padding: padding)
        for (cell, column) in zip(cells, columns) {
            guard let share = column.share else { continue }
            cell.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: share).isActive = true
            cell.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        return (holder, row)
    }

    /// The arrows move the chosen row; nil when the step goes nowhere.
    func choose(by step: Int) {
        guard !rows.isEmpty else { return }
        chosen = min(max((chosen ?? -step.signum()) + step, 0), rows.count - 1)
        if let chosen { rows[chosen].scrollToVisible(rows[chosen].bounds) }
    }
}

/// A table's row: lit under the pointer or chosen; it shows its `accessory` (the row's
/// "Abrir no Cadex") only then, as the board's hovered row.
@MainActor
final class PanelTableRow: PanelPress {
    var accessory: NSView? { didSet { paint() } }
    /// The row's cells; an accessory joins them at the end.
    var cells: NSStackView?
    var chosen = false { didSet { paint() } }
    private var hovering = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        onHover = { [weak self] on in
            self?.hovering = on
            self?.paint()
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelTableRow is created in code") }

    private func paint() {
        let lit = hovering || chosen
        box(bg: lit ? MP.Table.Row.hover : nil, border: nil, radius: 0)
        accessory?.isHidden = !lit
    }
}

/// A selection chip with a dot (components.memoryPanel.chip): "● Encerrada", "● Aberta",
/// "● semantic"; or a plain one ("decision", "mais recente").
@MainActor
enum PanelChip {
    enum Tone { case neutral, green, amber, agent, closed, open }

    static func make(_ text: String, _ tone: Tone, dot: Bool = false) -> NSView {
        typealias C = MP.Chip
        let (bg, color, dotColor): (NSColor, NSColor, NSColor?) = switch tone {
        case .neutral: (C.Neutral.bg, C.Neutral.color, nil)
        case .green: (C.Green.bg, C.Green.color, C.Green.dot)
        case .amber: (C.Amber.bg, C.Amber.color, C.Amber.dot)
        case .agent: (C.Agent.bg, C.Agent.color, C.Agent.color)
        case .closed: (C.Neutral.bg, C.Neutral.color, C.Closed.dot)
        case .open: (C.Neutral.bg, C.Neutral.color, MP.Radio.on)
        }
        let box = FrameBox()
        box.box(bg: bg, border: nil, radius: C.radius)
        let label = PanelText.line(text, size: C.fontSize, color: color, weight: C.weight)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        var views: [NSView] = [label]
        if dot, let dotColor {
            let spot = FrameBox()
            spot.box(bg: dotColor, border: nil, radius: C.dot / 2)
            spot.widthAnchor.constraint(equalToConstant: UILooks.pt(C.dot)).isActive = true
            spot.heightAnchor.constraint(equalToConstant: UILooks.pt(C.dot)).isActive = true
            views.insert(spot, at: 0)
        }
        let inner = PanelText.row(views, gap: C.gap)
        // A row taller than the chip (a button beside it) stretched the chip to its height.
        // Just under required: at required it tied with the words' own height and the dot's 6 pt
        // won, squeezing "● semantic" and "● pendente" to a sliver (plan 40 F's prints).
        inner.setHuggingPriority(.init(999), for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        box.hold(inner, padding: C.padding)
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.staticText)
        box.setAccessibilityLabel(text)
        return box
    }

    /// A chip in a table's cell: its own size at the cell's start, the rest of the cell empty.
    static func cell(_ text: String, _ tone: Tone, dot: Bool = false) -> NSView {
        PanelText.row([make(text, tone, dot: dot), PanelText.spring()], gap: 0)
    }
}
