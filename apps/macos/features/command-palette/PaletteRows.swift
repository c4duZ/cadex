import AppKit
import UILooks
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

    /// `joined`: the whole shortcut in one key (⌘J's "⌘1", the mockup).
    func show(_ label: String?, style: PaletteStyle, joined: Bool = false) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        spacing = 3
        for key in joined ? [label].compactMap({ $0 }).filter { !$0.isEmpty } : Self.keys(of: label ?? "") {
            let text = NSTextField(labelWithString: key)
            // One thin key, as the proposal's `kbd`: a line, no fill, dim letters.
            text.font = UILooks.font(11)
            text.textColor = style.secondaryText
            text.alignment = .center
            text.translatesAutoresizingMaskIntoConstraints = false
            let cap = NSView()
            cap.wantsLayer = true
            cap.layer?.backgroundColor = nil
            cap.layer?.cornerRadius = 5
            cap.layer?.borderWidth = 1
            cap.layer?.borderColor = style.border.cgColor
            cap.addSubview(text)
            NSLayoutConstraint.activate([
                cap.heightAnchor.constraint(equalToConstant: 18),
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
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 9, yRadius: 9).fill()
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

    private let line = NSView()

    func show(_ text: String, style: PaletteStyle) {
        title.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: UILooks.font(11, weight: .semibold), .foregroundColor: style.secondaryText, .kern: 0.6,
        ])
        // A section with a blank title is a line (⌘J's, above "+ New task", the mockup).
        let blank = text.trimmingCharacters(in: .whitespaces).isEmpty
        if blank, line.superview == nil {
            line.wantsLayer = true
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
            NSLayoutConstraint.activate([
                line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
                line.centerYAnchor.constraint(equalTo: centerYAnchor), line.heightAnchor.constraint(equalToConstant: 1),
            ])
        }
        line.layer?.backgroundColor = style.secondaryText.withAlphaComponent(0.18).cgColor
        line.isHidden = !blank
    }
}

/// The footer: the keys this list answers to ("↩ executar  ⌥↩ ao lado").
final class PaletteFooterView: NSStackView {
    func show(_ hints: [PaletteHint], style: PaletteStyle) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        spacing = 14
        for hint in hints {
            let keys = KeycapsView()
            keys.show(hint.keys, style: style, joined: true)
            let label = NSTextField(labelWithString: hint.label)
            label.font = UILooks.font(12)
            label.textColor = style.secondaryText
            let pair = NSStackView(views: [keys, label])
            pair.spacing = 6
            addArrangedSubview(pair)
        }
    }
}
