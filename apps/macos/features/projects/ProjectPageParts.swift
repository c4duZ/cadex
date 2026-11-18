import AppKit
import StateGlyph
import Strings
import UILooks

/// The pieces of a project's page (components.project; the Project mockup): a box, a label, a
/// number's card, a conversation's or automation's row, the switch and an account's chip.
typealias PP = DesignTokens.Project

@MainActor
func pageLabel(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, tracking: CGFloat = 0) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.attributedStringValue = NSAttributedString(string: text, attributes: [
        .font: UILooks.font(size, weight: weight), .foregroundColor: color, .kern: UILooks.pt(size) * tracking,
    ])
    // One line, cut with "…": a long merge subject wrapped and made its card taller (2026-11-17).
    label.lineBreakMode = .byTruncatingTail
    label.maximumNumberOfLines = 1
    label.usesSingleLineMode = true
    label.cell?.wraps = false
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return label
}

/// A box of the page that runs `onPress` on a click.
@MainActor
class PageBox: NSView {
    var onPress: (() -> Void)?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { if onPress != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    /// The first click of an inactive window presses too, as the system's sidebar items do.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { onPress != nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    /// A box that presses takes the click that lands on its words or glyphs: a label kept the
    /// mouse-down and the box never got the mouse-up, so a click on a card's or a row's text did
    /// nothing (found with clicks given to a test window, 2026-11-18). Buttons, switches, fields
    /// and boxes that press inside it keep theirs.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point), onPress != nil, hit !== self else { return super.hitTest(point) }
        if hit is NSButton || (hit as? PageBox)?.onPress != nil { return hit }
        if let field = hit as? NSTextField, field.isEditable || field.isSelectable { return hit }
        return self
    }

    func box(bg: NSColor, border: NSColor, radius: CGFloat) {
        wantsLayer = true
        layer?.backgroundColor = bg.cgColor
        layer?.borderColor = border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(radius)
    }

    func hold(_ content: NSView, padding: NSEdgeInsets) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(padding.left)),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(padding.right)),
            content.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(padding.top)),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(padding.bottom)),
        ])
    }
}

/// "RECENT CONVERSATIONS".
@MainActor
func sectionLabel(_ text: String) -> NSTextField {
    pageLabel(text, size: PP.Label.fontSize, color: PP.Label.color, weight: PP.Label.weight, tracking: PP.Label.tracking)
}

@MainActor
func vertical(_ views: [NSView], gap: CGFloat) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = UILooks.pt(gap)
    return stack
}

/// "Tasks open / 4 / 1 working · 1 needs you".
@MainActor
func statCard(_ stat: ProjectPageState.Stat) -> NSView {
    typealias S = PP.Stat
    let card = PageBox()
    card.box(bg: S.bg, border: S.border, radius: S.radius)
    card.hold(vertical([pageLabel(stat.label, size: S.Label.fontSize, color: S.Label.color),
                        pageLabel(stat.value, size: S.Value.fontSize, color: DesignTokens.Color.textPrimary, weight: S.Value.weight),
                        pageLabel(stat.note.isEmpty ? " " : stat.note, size: S.Note.fontSize, color: S.Note.color)], gap: S.gap),
              padding: S.padding)
    return card
}

/// A row: optionally the state's dot, the title and its line under, and on the right `tail`.
@MainActor
func pageRow(state: GlyphState?, title: String, meta: String, tail: NSView?) -> PageBox {
    typealias R = PP.Row
    let row = PageBox()
    row.box(bg: R.bg, border: R.border, radius: R.radius)
    var views: [NSView] = []
    if let state {
        let glyph = StateGlyphView(size: DesignTokens.Pane.Header.glyph, state: state)
        glyph.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Pane.Header.glyph)).isActive = true
        glyph.heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Pane.Header.glyph)).isActive = true
        views.append(glyph)
    }
    let text = vertical([pageLabel(title, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold),
                         pageLabel(meta, size: R.Meta.fontSize, color: R.Meta.color)], gap: R.textGap)
    text.setContentHuggingPriority(.init(1), for: .horizontal)
    views.append(text)
    if let tail {
        // The time and the switch keep their size; the title gives way.
        tail.setContentCompressionResistancePriority(.required, for: .horizontal)
        tail.setContentHuggingPriority(.required, for: .horizontal)
        views.append(tail)
    }
    let line = NSStackView(views: views)
    line.spacing = UILooks.pt(R.gap)
    line.distribution = .fill
    row.hold(line, padding: R.padding)
    row.setAccessibilityElement(true)
    row.setAccessibilityRole(.button)
    row.setAccessibilityLabel(title + ", " + meta)
    return row
}

/// The automation's switch (components.project.toggle).
@MainActor
final class PageSwitch: PageBox {
    typealias Tg = PP.Toggle
    private let knob = NSView()

    init(on: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: UILooks.pt(Tg.width), height: UILooks.pt(Tg.height)))
        box(bg: on ? Tg.on : Tg.off, border: .clear, radius: Tg.radius)
        knob.wantsLayer = true
        knob.layer?.backgroundColor = Tg.Knob.color.cgColor
        knob.layer?.cornerRadius = UILooks.pt(Tg.Knob.size) / 2
        let inset = (UILooks.pt(Tg.height) - UILooks.pt(Tg.Knob.size)) / 2
        knob.frame = NSRect(x: on ? UILooks.pt(Tg.width) - UILooks.pt(Tg.Knob.size) - inset : inset, y: inset,
                            width: UILooks.pt(Tg.Knob.size), height: UILooks.pt(Tg.Knob.size))
        addSubview(knob)
        widthAnchor.constraint(equalToConstant: UILooks.pt(Tg.width)).isActive = true
        heightAnchor.constraint(equalToConstant: UILooks.pt(Tg.height)).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityValue(on)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PageSwitch is created in code") }
}

/// "Claude bkdg 84%": the percent amber above components.project.account.warnAbovePercent.
@MainActor
func accountChip(_ account: ProjectPageState.Account) -> NSView {
    typealias A = PP.Account
    let chip = PageBox()
    chip.box(bg: A.bg, border: A.border, radius: A.radius)
    let text = NSMutableAttributedString(string: account.name, attributes: [
        .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: DesignTokens.Color.textPrimary,
    ])
    if let percent = account.percent {
        text.append(NSAttributedString(string: " \(percent)%", attributes: [
            .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: CGFloat(percent) > A.warnAbovePercent ? A.warn : A.muted,
        ]))
    }
    let label = NSTextField(labelWithAttributedString: text)
    label.maximumNumberOfLines = 1
    label.cell?.wraps = false
    label.lineBreakMode = .byTruncatingMiddle
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    chip.hold(label, padding: A.padding)
    return chip
}

/// Boxes in rows that wrap (the accounts' chips; the numbers' cards, all one width and height):
/// its height is its intrinsic size from the width it gets.
@MainActor
final class PageFlow: NSView {
    enum Mode { case wrap, grid(columns: (CGFloat) -> Int) }
    private let items: [NSView]
    private let mode: Mode
    private let gap: CGFloat
    private var height: CGFloat = 0

    init(_ items: [NSView], mode: Mode, gap: CGFloat) {
        self.items = items
        self.mode = mode
        self.gap = UILooks.pt(gap)
        super.init(frame: .zero)
        items.forEach { $0.translatesAutoresizingMaskIntoConstraints = true; addSubview($0) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PageFlow is created in code") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: height) }

    override func layout() {
        super.layout()
        let width = bounds.width
        guard width > 0 else { return }
        var y: CGFloat = 0
        switch mode {
        case .wrap:
            var x: CGFloat = 0, line: CGFloat = 0
            for item in items {
                let size = item.fittingSize
                let w = min(size.width, width)
                if x > 0, x + w > width { x = 0; y += line + gap; line = 0 }
                item.frame = CGRect(x: x, y: y, width: w, height: size.height)
                x += w + gap
                line = max(line, size.height)
            }
            y += line
        case .grid(let columnsFor):
            let columns = max(1, columnsFor(width))
            let w = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            items.forEach { $0.frame.size.width = w }
            let h = items.map(\.fittingSize.height).max() ?? 0
            for (index, item) in items.enumerated() {
                item.frame = CGRect(x: CGFloat(index % columns) * (w + gap), y: CGFloat(index / columns) * (h + gap), width: w, height: h)
            }
            y = items.isEmpty ? 0 : CGFloat((items.count - 1) / columns + 1) * (h + gap) - gap
        }
        if y != height {
            height = y
            invalidateIntrinsicContentSize()
            superview?.needsLayout = true
        }
    }

    /// A click finds its card even while the flow's own height lags behind its cards (they are
    /// placed by hand and drawn past its bounds): the Projects page's cards took no click, 2026-11-18.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for item in items.reversed() where item.frame.contains(local) { return item.hitTest(local) ?? item }
        return super.hitTest(point)
    }
}
