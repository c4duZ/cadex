import AppKit
import Themes

/// The themes page's grid of cards, two per row, for hundreds of themes:
/// only the rows on screen have card views, reused as the page scrolls
/// (plan 15: a page with every card built at once would weigh on the app).
@MainActor
final class ThemeGrid: NSView {
    static let rowHeight: CGFloat = 62, gap: CGFloat = 10
    var families: [ThemeFamily] = [] { didSet { reloadCards() } }
    var selected: Set<String> = [] { didSet { visible.values.forEach { $0.selected = selected.contains($0.family.id) } } }
    private let onPick: (ThemeFamily) -> Void
    private var visible: [Int: ThemeCard] = [:]
    private var spare: [ThemeCard] = []

    init(onPick: @escaping (ThemeFamily) -> Void) {
        self.onPick = onPick
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ThemeGrid is created in code") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let rows = CGFloat((families.count + 1) / 2)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(rows * (Self.rowHeight + Self.gap) - Self.gap, 0))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        guard let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: clip)
    }

    override func layout() {
        super.layout()
        placeCards()
    }

    @objc private func scrolled() {
        placeCards()
    }

    private func reloadCards() {
        visible.values.forEach { $0.removeFromSuperview(); spare.append($0) }
        visible = [:]
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    /// Cards for the rows in view and one row around them; the rest go back
    /// to the spare pile.
    private func placeCards() {
        let width = (bounds.width - Self.gap) / 2
        let shown = visibleRect.insetBy(dx: 0, dy: -(Self.rowHeight + Self.gap))
        let step = Self.rowHeight + Self.gap
        let first = max(Int(shown.minY / step), 0) * 2
        let last = min(Int(shown.maxY / step) * 2 + 1, families.count - 1)
        let wanted = first <= last ? Set(first...last) : []
        for (index, card) in visible where !wanted.contains(index) {
            card.removeFromSuperview()
            spare.append(card)
            visible[index] = nil
        }
        for index in wanted.sorted() {
            let card = visible[index] ?? takeCard()
            if visible[index] == nil || card.family.id != families[index].id {
                card.show(families[index], selected: selected.contains(families[index].id))
            }
            visible[index] = card
            card.frame = NSRect(x: CGFloat(index % 2) * (width + Self.gap), y: CGFloat(index / 2) * step,
                                width: width, height: Self.rowHeight)
        }
    }

    private func takeCard() -> ThemeCard {
        let card = spare.popLast() ?? ThemeCard { [weak self] family in self?.onPick(family) }
        if card.superview == nil { addSubview(card) }
        return card
    }
}

/// One theme in the grid: three color bars on the theme's background, the
/// name and the description; outlined when it is the one in use.
final class ThemeCard: NSView {
    private(set) var family: ThemeFamily = .cadex
    var selected = false { didSet { updateBorder() } }
    private let onPick: (ThemeFamily) -> Void
    private let swatch = Swatch()
    private let name = NSTextField(labelWithString: "")
    private let line = NSTextField(labelWithString: "")

    init(onPick: @escaping (ThemeFamily) -> Void) {
        self.onPick = onPick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        line.font = .systemFont(ofSize: 11)
        line.lineBreakMode = .byTruncatingTail
        name.lineBreakMode = .byTruncatingTail
        let texts = NSStackView(views: [name, line])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 2
        let row = NSStackView(views: [swatch, texts])
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatch.widthAnchor.constraint(equalToConstant: 56),
            swatch.heightAnchor.constraint(equalToConstant: 42),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ThemeCard is created in code") }

    func show(_ family: ThemeFamily, selected: Bool) {
        self.family = family
        name.stringValue = family.name
        line.stringValue = family.description
        name.textColor = SettingsColors.text
        line.textColor = SettingsColors.secondaryText
        swatch.themes = [family.dark, family.light].compactMap { $0 }
        self.selected = selected
        toolTip = family.description
    }

    override func mouseDown(with event: NSEvent) {
        onPick(family)
    }

    private func updateBorder() {
        layer?.borderColor = (selected ? SettingsColors.accent : SettingsColors.border).cgColor
        layer?.backgroundColor = SettingsColors.box.cgColor
        layer?.borderWidth = selected ? 2 : 1
    }
}

/// The swatch of a card: accent, secondary text and text bars on the
/// theme's background; a theme with both versions shows the dark one on
/// the left half and the light one on the right.
private final class Swatch: NSView {
    var themes: [Theme] = [] { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard !themes.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).addClip()
        let part = bounds.width / CGFloat(themes.count)
        for (i, theme) in themes.enumerated() {
            let area = NSRect(x: bounds.minX + CGFloat(i) * part, y: bounds.minY, width: part, height: bounds.height)
            theme.terminal.background.nsColor.setFill()
            area.fill()
            let colors = [theme.interface.accent, theme.terminal.ansi[2], theme.terminal.ansi[1], theme.terminal.foreground]
            let colorsShown = themes.count == 1 ? colors : [colors[0], colors[3]]
            let width: CGFloat = 6, gap: CGFloat = 4
            let total = CGFloat(colorsShown.count) * width + CGFloat(colorsShown.count - 1) * gap
            for (j, color) in colorsShown.enumerated() {
                color.nsColor.setFill()
                let bar = NSRect(x: area.midX - total / 2 + CGFloat(j) * (width + gap), y: area.minY + 9, width: width, height: area.height - 18)
                NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
