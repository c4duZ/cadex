import AppKit
import UILooks

/// The content of a status bar item's card (docs/spec/status-bar.md, Os cartões; the proposal the
/// owner approved on 2026-11-18): a header with a title and its detail, a big number, a bar in
/// parts, sections of rows (a click runs the row's action) and the actions at the foot. Each item
/// gives only its blocks; the look is the same for all. Goes inside a HoverCard.
@MainActor
public enum StatusCard {
    public struct Row {
        public var title: String
        public var detail: String?
        public var value: String?
        public var dot: NSColor?
        /// The value in a warning color (amber).
        public var warn: Bool
        public var action: (() -> Void)?

        public init(_ title: String, detail: String? = nil, value: String? = nil, dot: NSColor? = nil, warn: Bool = false,
                    action: (() -> Void)? = nil) {
            self.title = title
            self.detail = detail
            self.value = value
            self.dot = dot
            self.warn = warn
            self.action = action
        }
    }

    public struct Action {
        public var title: String
        public var run: () -> Void

        public init(_ title: String, run: @escaping () -> Void) {
            self.title = title
            self.run = run
        }
    }

    public enum Block {
        case header(String, detail: String? = nil, warn: Bool = false)
        case big(String, caption: String? = nil)
        /// Parts of a whole, 0 to 1 each, in their colors.
        case bar([(Double, NSColor)])
        case legend([(String, NSColor)])
        case section(String)
        case rows([Row])
        case note(String, warn: Bool = false)
        case actions([Action])
    }

    public static let width: CGFloat = 300

    /// The card for `blocks`; `close` runs before any row or action (the card goes away first).
    public static func build(_ blocks: [Block], close: @escaping () -> Void) -> NSView {
        let width = UILooks.pt(Self.width)
        var views: [NSView] = []
        for block in blocks {
            switch block {
            case .header(let title, let detail, let warn):
                let line = NSStackView(views: [label(title, DesignTokens.FontSize.body, .semibold, DesignTokens.Color.textPrimary), NSView()])
                if let detail { line.addArrangedSubview(label(detail, DesignTokens.FontSize.small, .regular, warn ? DesignTokens.Color.accentAmberText : DesignTokens.Color.textMuted)) }
                views.append(line)
                views.append(rule())
            case .big(let value, let caption):
                let line = NSStackView(views: [label(value, DesignTokens.FontSize.stat, .semibold, DesignTokens.Color.textPrimary, digits: true)])
                line.alignment = .firstBaseline
                if let caption { line.addArrangedSubview(label(caption, DesignTokens.FontSize.small, .regular, DesignTokens.Color.textMuted)) }
                views.append(line)
            case .bar(let parts):
                views.append(BarView(parts: parts))
            case .legend(let parts):
                let line = NSStackView(views: parts.map { text, color in
                    let swatch = NSView()
                    swatch.wantsLayer = true
                    swatch.layer?.backgroundColor = color.cgColor
                    swatch.layer?.cornerRadius = 2
                    swatch.widthAnchor.constraint(equalToConstant: UILooks.pt(8)).isActive = true
                    swatch.heightAnchor.constraint(equalToConstant: UILooks.pt(8)).isActive = true
                    let pair = NSStackView(views: [swatch, label(text, DesignTokens.FontSize.caption, .regular, DesignTokens.Color.textSecondary)])
                    pair.spacing = 4
                    return pair
                })
                line.spacing = 8
                views.append(line)
            case .section(let title):
                let caption = label(title.uppercased(), DesignTokens.FontSize.chip, .semibold, DesignTokens.Color.textTertiary)
                views.append(caption)
            case .rows(let rows):
                for row in rows { views.append(rowView(row, width: width, close: close)) }
            case .note(let text, let warn):
                let note = NSTextField(wrappingLabelWithString: text)
                note.font = UILooks.font(DesignTokens.FontSize.small)
                note.textColor = warn ? DesignTokens.Color.accentAmberText : DesignTokens.Color.textMuted
                note.preferredMaxLayoutWidth = width
                views.append(note)
            case .actions(let actions):
                views.append(rule())
                let rows = actions.map { action in
                    let row = HoverRow(label(action.title, DesignTokens.FontSize.meta, .regular, DesignTokens.Color.accentLink), inset: 6)
                    row.onClick = { close(); action.run() }
                    return row
                }
                // Wrapped as the proposal's foot (flex-wrap): three actions cut the first one in the
                // accounts card ("Open an agent ⋯", 2026-11-20).
                views += footLines(rows, width: width)
            }
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        for view in views where !(view is NSTextField) || view is BarView {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return stack
    }

    /// The foot's actions in lines no wider than `width`, in order.
    private static func footLines(_ rows: [NSView], width: CGFloat) -> [NSView] {
        let gap: CGFloat = 2
        var lines: [[NSView]] = [[]]
        var used: CGFloat = 0
        for row in rows {
            let w = row.fittingSize.width
            if !lines[lines.count - 1].isEmpty, used + gap + w > width {
                lines.append([])
                used = 0
            }
            used += (lines[lines.count - 1].isEmpty ? 0 : gap) + w
            lines[lines.count - 1].append(row)
        }
        return lines.map { views in
            let line = NSStackView(views: views + [NSView()])
            line.spacing = gap
            return line
        }
    }

    private static func rowView(_ row: Row, width: CGFloat, close: @escaping () -> Void) -> NSView {
        var parts: [NSView] = []
        if let dot = row.dot {
            let mark = NSView()
            mark.wantsLayer = true
            mark.layer?.backgroundColor = dot.cgColor
            mark.layer?.cornerRadius = UILooks.pt(3.5)
            mark.widthAnchor.constraint(equalToConstant: UILooks.pt(7)).isActive = true
            mark.heightAnchor.constraint(equalToConstant: UILooks.pt(7)).isActive = true
            parts.append(mark)
        }
        let title = label(row.title, DesignTokens.FontSize.meta, .regular, DesignTokens.Color.textPrimary)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        parts.append(title)
        if let detail = row.detail {
            let d = label(detail, DesignTokens.FontSize.small, .regular, DesignTokens.Color.textMuted)
            d.lineBreakMode = .byTruncatingTail
            d.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
            parts.append(d)
        }
        parts.append(NSView())
        if let value = row.value {
            let v = label(value, DesignTokens.FontSize.meta, .regular, row.warn ? DesignTokens.Color.accentAmberText : DesignTokens.Color.textSecondary, digits: true)
            v.setContentCompressionResistancePriority(.required, for: .horizontal)
            parts.append(v)
        }
        let line = NSStackView(views: parts)
        line.spacing = 8
        guard let action = row.action else {
            let plain = NSView()
            line.translatesAutoresizingMaskIntoConstraints = false
            plain.addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: plain.leadingAnchor, constant: 6),
                line.trailingAnchor.constraint(equalTo: plain.trailingAnchor, constant: -6),
                line.topAnchor.constraint(equalTo: plain.topAnchor, constant: 4),
                line.bottomAnchor.constraint(equalTo: plain.bottomAnchor, constant: -4),
            ])
            return plain
        }
        let hover = HoverRow(line)
        hover.onClick = { close(); action() }
        return hover
    }

    private static func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, digits: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = digits ? UILooks.monospacedDigits(size, weight: weight) : UILooks.font(size, weight: weight)
        field.textColor = color
        return field
    }

    private static func rule() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = DesignTokens.Color.linePopover.cgColor
        line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline).isActive = true
        return line
    }
}

/// A bar in parts: each a share of the width, in its color, on the track.
private final class BarView: NSView {
    private let parts: [(Double, NSColor)]

    init(parts: [(Double, NSColor)]) {
        self.parts = parts
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: UILooks.pt(6)).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BarView is created in code") }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r)
        DesignTokens.Color.bgSelected.setFill()
        track.fill()
        track.addClip()
        var x: CGFloat = 0
        for (share, color) in parts {
            let w = bounds.width * CGFloat(min(max(share, 0), 1))
            color.setFill()
            NSRect(x: x, y: 0, width: w, height: bounds.height).fill()
            x += w
        }
    }
}
