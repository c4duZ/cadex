import AppKit
import Icons

/// The palette's colors, from the theme (the app sets them): the panels'
/// fill and border, text, the selected row and the accent, as the tab
/// strip and the sidebar use them (docs/spec/command-palette.md).
public struct PaletteStyle: Sendable {
    public var background: NSColor
    public var border: NSColor
    public var text: NSColor
    public var secondaryText: NSColor
    public var selection: NSColor
    public var accent: NSColor
    /// The keys' fill (⇧ ⌘ D).
    public var keycap: NSColor

    public init(background: NSColor, border: NSColor, text: NSColor, secondaryText: NSColor,
                selection: NSColor, accent: NSColor, keycap: NSColor) {
        self.background = background
        self.border = border
        self.text = text
        self.secondaryText = secondaryText
        self.selection = selection
        self.accent = accent
        self.keycap = keycap
    }

    /// Before the theme arrives.
    public static let system = PaletteStyle(
        background: .windowBackgroundColor, border: .separatorColor, text: .labelColor,
        secondaryText: .secondaryLabelColor, selection: .quaternaryLabelColor, accent: .controlAccentColor,
        keycap: .quaternaryLabelColor)
}

/// The rows on screen: a title where the section changes, then its items.
enum PaletteRows {
    enum Row: Equatable {
        case header(String)
        case item(Int)
    }

    static func rows(for items: [PaletteItem]) -> [Row] {
        var rows: [Row] = []
        var current: String?
        for (index, item) in items.enumerated() {
            if let section = item.section, section != current {
                rows.append(.header(section))
                current = section
            }
            rows.append(.item(index))
        }
        return rows
    }

    /// The next item row `step` away from `row`, skipping titles; nil at the ends.
    static func next(from row: Int, by step: Int, in rows: [Row]) -> Int? {
        var candidate = row + step
        while candidate >= 0, candidate < rows.count {
            if case .item = rows[candidate] { return candidate }
            candidate += step
        }
        return nil
    }
}

/// Keys drawn as small rounded caps: "⇧⌘D" is ⇧, ⌘ and D.
final class KeycapsView: NSStackView {
    static func keys(of label: String) -> [String] {
        let modifiers = label.prefix { "⌃⌥⇧⌘".contains($0) }
        let rest = label.dropFirst(modifiers.count)
        return modifiers.map(String.init) + (rest.isEmpty ? [] : [String(rest)])
    }

    func show(_ label: String?, style: PaletteStyle) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        spacing = 3
        for key in Self.keys(of: label ?? "") {
            let text = NSTextField(labelWithString: key)
            text.font = .systemFont(ofSize: 11, weight: .medium)
            text.textColor = style.secondaryText
            text.alignment = .center
            text.translatesAutoresizingMaskIntoConstraints = false
            let cap = NSView()
            cap.wantsLayer = true
            cap.layer?.backgroundColor = style.keycap.cgColor
            cap.layer?.cornerRadius = 5
            cap.layer?.borderWidth = 1
            cap.layer?.borderColor = style.border.cgColor
            cap.addSubview(text)
            NSLayoutConstraint.activate([
                cap.heightAnchor.constraint(equalToConstant: 20),
                cap.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
                text.centerYAnchor.constraint(equalTo: cap.centerYAnchor),
                text.leadingAnchor.constraint(equalTo: cap.leadingAnchor, constant: 5),
                text.trailingAnchor.constraint(equalTo: cap.trailingAnchor, constant: -5),
            ])
            addArrangedSubview(cap)
        }
    }
}

/// The selected row: a rounded fill, not the system's blue band.
final class PaletteRowBackground: NSTableRowView {
    var fill: NSColor = .quaternaryLabelColor

    override func drawSelection(in dirtyRect: NSRect) {
        fill.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 8, yRadius: 8).fill()
    }

    override var isEmphasized: Bool { get { false } set {} }
}

/// A section's title over its rows: small, grey, spaced capitals, lined
/// up with the rows' icons.
final class PaletteHeaderView: NSView {
    private let title = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaletteHeaderView is created in code") }

    func show(_ text: String, style: PaletteStyle) {
        title.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: style.secondaryText, .kern: 0.6,
        ])
    }
}

/// A row: the icon, the title with the matched letters in bold, then on
/// the right the detail, the reason it is unavailable, or the shortcut
/// as keys.
final class PaletteRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("palette-row")
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let keys = KeycapsView()
    private var style = PaletteStyle.system
    private var available = true

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        detail.alignment = .right
        detail.font = .systemFont(ofSize: 12)
        for view in [icon, title, detail, keys] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for label in [title, detail] { label.lineBreakMode = .byTruncatingMiddle }
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            detail.trailingAnchor.constraint(equalTo: keys.leadingAnchor, constant: -8),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
            keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            keys.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaletteRowView is created in code") }

    func show(_ item: PaletteItem, style: PaletteStyle, selected: Bool) {
        self.style = style
        available = item.unavailableReason == nil
        let color = available ? style.text : style.secondaryText.withAlphaComponent(0.6)
        let text = NSMutableAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: color,
        ])
        for range in item.bold {
            text.addAttributes([.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: available ? style.accent : color],
                               range: NSRange(range, in: item.title))
        }
        title.attributedStringValue = text
        detail.stringValue = item.unavailableReason ?? item.detail ?? ""
        detail.textColor = style.secondaryText.withAlphaComponent(available ? 1 : 0.7)
        keys.show(available ? item.shortcut : nil, style: style)
        icon.image = item.image ?? item.icon?.image(size: 16)
        setSelected(selected)
    }

    /// The icon takes the accent on the selected row.
    func setSelected(_ selected: Bool) {
        let tint = selected && available ? style.accent : style.secondaryText
        icon.contentTintColor = available ? tint : tint.withAlphaComponent(0.5)
    }
}

/// The footer: the keys this list answers to ("↩ executar  ⌥↩ ao lado").
final class PaletteFooterView: NSStackView {
    func show(_ hints: [PaletteHint], style: PaletteStyle) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        spacing = 14
        for hint in hints {
            let keys = KeycapsView()
            keys.show(hint.keys, style: style)
            let label = NSTextField(labelWithString: hint.label)
            label.font = .systemFont(ofSize: 12)
            label.textColor = style.secondaryText
            let pair = NSStackView(views: [keys, label])
            pair.spacing = 6
            addArrangedSubview(pair)
        }
    }
}
