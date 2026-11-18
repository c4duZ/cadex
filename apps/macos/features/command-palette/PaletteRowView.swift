import AppKit
import Icons
import UILooks

/// A row of the palette as the approved proposal draws it (scratchpad ux2/index.html, `.pal .it`,
/// 2026-11-18): the glyph dim or a colored square, the title in 13 with a smaller second line when
/// there is one, and on the right the reason it cannot run, the detail, a usage bar with its
/// number, a chip, or the shortcut in one thin key. The selected row's fill is the row view's.
final class PaletteRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("palette-row")
    private let icon = NSImageView()
    private let tile = NSView()
    private let tileGlyph = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let note = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let meter = PaletteMeter()
    private let meterText = NSTextField(labelWithString: "")
    private let chip = NSTextField(labelWithString: "")
    private let keys = KeycapsView()
    private var style = PaletteStyle.system
    private var available = true

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        tile.wantsLayer = true
        tile.layer?.cornerRadius = UILooks.pt(6)
        tile.addSubview(tileGlyph)
        chip.wantsLayer = true
        chip.layer?.cornerRadius = UILooks.pt(6)
        chip.alignment = .center
        for label in [title, note, detail] { label.lineBreakMode = .byTruncatingMiddle }
        detail.alignment = .right
        meterText.alignment = .right
        let words = NSStackView(views: [title, note])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = UILooks.pt(1)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        note.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        let trailing = NSStackView(views: [detail, meter, meterText, chip, keys])
        trailing.spacing = UILooks.pt(10)
        trailing.setHuggingPriority(.required, for: .horizontal)
        for view in [icon, tile, words, trailing] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        tileGlyph.translatesAutoresizingMaskIntoConstraints = false
        let lead = UILooks.pt(10), side = UILooks.pt(20)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: lead + UILooks.pt(2)),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: UILooks.pt(16)),
            icon.heightAnchor.constraint(equalToConstant: UILooks.pt(16)),
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: lead),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: side),
            tile.heightAnchor.constraint(equalToConstant: side),
            tileGlyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            tileGlyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            tileGlyph.widthAnchor.constraint(equalToConstant: UILooks.pt(12)),
            tileGlyph.heightAnchor.constraint(equalToConstant: UILooks.pt(12)),
            words.leadingAnchor.constraint(equalTo: leadingAnchor, constant: lead + side + UILooks.pt(12)),
            words.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: words.trailingAnchor, constant: UILooks.pt(12)),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -lead),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            meterText.widthAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(34)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaletteRowView is created in code") }

    func show(_ item: PaletteItem, style: PaletteStyle, selected: Bool) {
        self.style = style
        available = item.unavailableReason == nil
        let dim = style.secondaryText
        let color = available ? style.text : dim.withAlphaComponent(0.6)
        let jump = item.look == .jump
        let font = UILooks.font(13, weight: jump ? .semibold : .regular)
        let text = NSMutableAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: color])
        for range in item.bold {
            // The search's matched letters take the accent; ⌘J's action keeps the text's color.
            text.addAttributes([.font: UILooks.font(13, weight: .semibold), .foregroundColor: available && item.look == .standard ? style.accent : color],
                               range: NSRange(range, in: item.title))
        }
        title.attributedStringValue = text
        note.stringValue = item.note ?? ""
        note.font = UILooks.font(11.5)
        note.textColor = dim.withAlphaComponent(0.85)
        note.isHidden = item.note == nil
        detail.stringValue = item.unavailableReason ?? item.detail ?? ""
        detail.font = UILooks.font(12)
        detail.textColor = dim.withAlphaComponent(available ? 1 : 0.7)
        detail.isHidden = detail.stringValue.isEmpty
        showTile(item)
        meter.isHidden = item.meter == nil
        meter.value = item.meter ?? 0
        meter.track = style.keycap
        meterText.stringValue = item.meterText ?? ""
        meterText.isHidden = item.meterText == nil
        meterText.font = UILooks.font(12)
        meterText.textColor = dim
        chip.isHidden = item.chip == nil
        chip.attributedStringValue = NSAttributedString(string: " \(item.chip ?? "") ", attributes: [
            .font: UILooks.font(10.5, weight: .bold), .foregroundColor: dim,
        ])
        chip.layer?.backgroundColor = style.keycap.cgColor
        keys.show(available ? item.shortcut : nil, style: style, joined: true)
        setSelected(selected)
    }

    private func showTile(_ item: PaletteItem) {
        switch item.tile {
        case .kind(let glyph, let tint)?:
            tile.layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
            tileGlyph.image = glyph.image(size: UILooks.pt(12))
            tileGlyph.contentTintColor = tint
        case .logo(let image, let tint)?:
            tile.layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
            tileGlyph.image = image
            tileGlyph.contentTintColor = tint
        case nil:
            break
        }
        tile.isHidden = item.tile == nil
        icon.isHidden = item.tile != nil
        icon.image = item.image ?? item.icon?.image(size: 16)
    }

    /// The glyph stays dim, as the proposal draws it; the row's fill says which is chosen.
    func setSelected(_ selected: Bool) {
        let tint = selected && available ? style.text : style.secondaryText
        icon.contentTintColor = available ? tint : tint.withAlphaComponent(0.5)
    }
}

/// The usage bar of an account row: 64 × 5, green, amber from 70 %, red from 90 %.
final class PaletteMeter: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var track: NSColor = .quaternaryLabelColor

    override var intrinsicContentSize: NSSize { NSSize(width: UILooks.pt(64), height: UILooks.pt(5)) }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        track.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let fill = value >= 0.9 ? DesignTokens.Color.stateFailed : value >= 0.7 ? DesignTokens.Color.stateNeeds : DesignTokens.Color.stateDone
        fill.setFill()
        let width = max(bounds.height, bounds.width * min(max(value, 0), 1))
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height), xRadius: radius, yRadius: radius).fill()
    }
}
