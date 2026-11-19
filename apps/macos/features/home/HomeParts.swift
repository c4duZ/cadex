import AppKit
import Menus
import Icons
import Strings
import UILooks

/// The pieces of the home screen as the Home mockup draws them (components.home): the prompt box,
/// a card and a recent project's row. HomeView lays them out.
typealias H = DesignTokens.Home

/// A view that runs `onPress` on a click, with the pointing hand over it.
@MainActor
class HomeClickable: NSView {
    var onPress: (() -> Void)?
    /// The right click's entries, given by the app (each runs a command or the same thing as a click);
    /// cards and rows had none (UX audit, 2026-11-18).
    var rightMenu: (() -> [MenuEntry])?
    override func rightMouseDown(with event: NSEvent) {
        guard let entries = rightMenu?(), !entries.isEmpty else { return super.rightMouseDown(with: event) }
        PopupMenu.show(entries, at: convert(event.locationInWindow, from: nil), in: self)
    }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    /// The fill, the line and the corners of a box of the screen.
    func box(bg: NSColor, border: NSColor, radius: CGFloat) {
        wantsLayer = true
        layer?.backgroundColor = bg.cgColor
        layer?.borderColor = border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(radius)
    }
}

@MainActor
func homeLabel(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, tracking: CGFloat = 0) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.attributedStringValue = NSAttributedString(string: text, attributes: [
        .font: UILooks.font(size, weight: weight), .foregroundColor: color, .kern: UILooks.pt(size) * tracking,
    ])
    label.lineBreakMode = .byTruncatingTail
    return label
}

/// The prompt's box, with the mockup's `box-shadow: 0 0 0 3px` ring just outside it (a layer
/// beyond its bounds, as the focused pane's halo).
@MainActor
final class HomePromptBox: HomeClickable {
    private let ring = CALayer()

    override func layout() {
        super.layout()
        guard let layer, let halo = H.Prompt.shadow.first else { return }
        if ring.superlayer == nil { layer.masksToBounds = false; layer.insertSublayer(ring, at: 0) }
        let spread = UILooks.pt(halo.spread)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds.insetBy(dx: -spread, dy: -spread)
        ring.cornerRadius = layer.cornerRadius + spread
        ring.borderWidth = spread
        ring.borderColor = halo.color.cgColor
        CATransaction.commit()
    }
}

/// "◆ Claude · bkdg ▾": a choice under the prompt, a menu on click.
@MainActor
final class HomeChip: HomeClickable {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        box(bg: H.Chip.bg, border: .clear, radius: H.Chip.radius)
        label.font = UILooks.font(H.Chip.fontSize)
        label.textColor = DesignTokens.Color.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        let pad = H.Chip.padding
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(pad.left)),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(pad.right)),
            label.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(pad.top)),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(pad.bottom)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HomeChip is created in code") }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue + " ▾" }
    }
}

/// One of the four cards: the icon and title, a sentence, the shortcut.
@MainActor
final class HomeCardView: HomeClickable {
    private let key = NSTextField(labelWithString: "")

    /// The shortcut, read again at each show: the screen can be made before the keymap is.
    func setShortcut(_ text: String) {
        key.stringValue = text
        key.isHidden = text.isEmpty
    }

    init(_ card: HomeCard) {
        super.init(frame: .zero)
        box(bg: H.Card.bg, border: H.Card.border, radius: H.Card.radius)
        let icon = NSImageView(image: card.icon.image(size: UILooks.pt(H.Card.Head.icon)))
        icon.contentTintColor = DesignTokens.Color.textPrimary
        let title = homeLabel(card.title, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary, weight: H.Card.Head.weight)
        let head = NSStackView(views: [icon, title])
        head.spacing = UILooks.pt(H.Card.Head.gap)
        let text = NSTextField(wrappingLabelWithString: "")
        sentence = text
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = H.Card.Text.lineHeight
        text.attributedStringValue = NSAttributedString(string: card.text, attributes: [
            .font: UILooks.font(H.Card.Text.fontSize), .foregroundColor: H.Card.Text.color, .paragraphStyle: style,
        ])
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        key.font = UILooks.font(H.Card.Key.fontSize)
        key.textColor = H.Card.Key.color
        let column = NSStackView(views: [head, text, key])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = UILooks.pt(H.Card.gap)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        let pad = UILooks.pt(H.Card.padding)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            column.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            column.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            column.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -pad),
            text.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(card.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HomeCardView is created in code") }

    private weak var sentence: NSTextField?

    /// Its height at `width`: the sentence wraps at the card's inner width first (measured on one
    /// line, the shortcut's line fell outside the card, 2026-11-17).
    func height(at width: CGFloat) -> CGFloat {
        sentence?.preferredMaxLayoutWidth = max(width - 2 * UILooks.pt(H.Card.padding), 0)
        frame.size.width = width
        return fittingSize.height
    }
}

/// A recent project: its name, path, state in its color and when; Remove when its folder is gone.
@MainActor
final class HomeRecentRow: HomeClickable {
    init(_ recent: HomeRecent, remove: @escaping () -> Void) {
        super.init(frame: .zero)
        typealias R = H.Recent
        box(bg: R.bg, border: R.border, radius: R.radius)
        let name = homeLabel(recent.name, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        let path = homeLabel(HomeWords.shortPath(recent.folder), size: R.Path.fontSize, color: R.Path.color)
        path.lineBreakMode = .byTruncatingMiddle
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        path.setContentHuggingPriority(.init(1), for: .horizontal)
        let state = homeLabel(recent.stateText, size: R.State.fontSize, color: Self.color(recent.state))
        let tail: NSView
        if recent.state == .missing {
            let button = NSButton(title: T("Remove", "Tirar"), target: nil, action: nil)
            button.isBordered = false
            button.attributedTitle = NSAttributedString(string: button.title, attributes: [
                .font: UILooks.font(R.When.fontSize), .foregroundColor: DesignTokens.Color.accentLink,
            ])
            tail = HomeAction(button, remove)
        } else {
            let when = homeLabel(HomeWords.when(recent.usedAt), size: R.When.fontSize, color: R.When.color)
            // In the text itself: an attributed value without a paragraph style is left-aligned.
            let right = NSMutableParagraphStyle()
            right.alignment = .right
            let text = NSMutableAttributedString(attributedString: when.attributedStringValue)
            text.addAttribute(.paragraphStyle, value: right, range: NSRange(location: 0, length: text.length))
            when.attributedStringValue = text
            tail = when
        }
        pieces = (name, path, state, tail)
        for view in [name, path, state, tail] { addSubview(view) }
        heightAnchor.constraint(equalToConstant: UILooks.pt(R.padding.top + R.padding.bottom) + ceil(name.intrinsicContentSize.height)).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(recent.name + ", " + recent.stateText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HomeRecentRow is created in code") }

    private var pieces: (name: NSView, path: NSView, state: NSView, tail: NSView)?

    /// By hand: the name and the "when" at the mockup's widths, the state as long as its words, the
    /// path with what is left (a stack view gave the state the path's room, 2026-11-17).
    override func layout() {
        super.layout()
        guard let pieces else { return }
        typealias R = H.Recent
        let gap = UILooks.pt(R.gap), left = UILooks.pt(R.padding.left), right = UILooks.pt(R.padding.right)
        func place(_ view: NSView, x: CGFloat, width: CGFloat) {
            let height = view.intrinsicContentSize.height
            view.frame = CGRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: max(width, 0), height: height)
        }
        let nameWidth = UILooks.pt(R.nameWidth), tailWidth = UILooks.pt(R.whenWidth)
        // The words' own width plus the field's insets: the label's intrinsic width came short and
        // cut "1 needs you" (2026-11-17).
        let words = (pieces.state as? NSTextField)?.attributedStringValue.size().width ?? pieces.state.intrinsicContentSize.width
        let stateWidth = ceil(words) + 2 * DesignTokens.Stroke.glyph * 2
        place(pieces.name, x: left, width: nameWidth)
        place(pieces.tail, x: bounds.width - right - tailWidth, width: tailWidth)
        place(pieces.state, x: bounds.width - right - tailWidth - gap - stateWidth, width: stateWidth)
        let pathX = left + nameWidth + gap
        place(pieces.path, x: pathX, width: pieces.state.frame.minX - gap - pathX)
    }

    static func color(_ state: HomeRecent.State) -> NSColor {
        switch state {
        case .needsYou: DesignTokens.Color.stateNeeds
        case .finished: DesignTokens.Color.stateDone
        case .open, .closed, .missing: DesignTokens.Color.textMuted
        }
    }
}

/// A plain button whose click runs a closure (the row's Remove, the header's links).
@MainActor
final class HomeAction: NSView {
    private let run: () -> Void

    init(_ button: NSButton, _ run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        button.target = self
        button.action = #selector(pressed)
        button.translatesAutoresizingMaskIntoConstraints = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor), button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor), button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HomeAction is created in code") }

    @objc private func pressed() { run() }
}
