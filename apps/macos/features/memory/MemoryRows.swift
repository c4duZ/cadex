import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The rows of the Memory tab (the owner, 2026-11-18: the tab was hard to read and stiff): one
/// line per page or session, the page's kind as a colored glyph, the meta in one dim line, the
/// age on the right; the row lights under the pointer, a click opens it, the right click gives the
/// page's menu. They replace the wiki's tree, which scrolled inside the tab's own scroll and named
/// the sessions by their first sentence.
@MainActor
final class MemoryRow: NSView {
    typealias M = DesignTokens.Inspector.Memory

    private let press: () -> Void
    private let entries: () -> [MenuEntry]
    private var hovered = false { didSet { layer?.backgroundColor = hovered ? DesignTokens.Color.bgButton.cgColor : nil } }

    /// `glyph` and `tint`: the kind's sign in its tile; `meta`: a second dim line; `age`: on the right.
    init(title: String, meta: String?, age: String?, glyph: Icon, tint: NSColor,
         press: @escaping () -> Void, menu: @escaping () -> [MenuEntry] = { [] }) {
        self.press = press
        self.entries = menu
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(M.Card.radius)
        // The kind's tile: 20 pt, its color at 14 % behind the glyph (the review's proposal, 2026-11-18).
        let side = UILooks.pt(20)
        let tile = NSImageView(image: glyph.image(size: UILooks.pt(M.Search.icon)))
        tile.contentTintColor = tint
        tile.wantsLayer = true
        tile.layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
        tile.layer?.cornerRadius = UILooks.pt(DesignTokens.Radius.chip)
        tile.widthAnchor.constraint(equalToConstant: side).isActive = true
        tile.heightAnchor.constraint(equalToConstant: side).isActive = true
        let name = MemoryText.label(title, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textRow)
        var lines: [NSView] = [name]
        if let meta, !meta.isEmpty { lines.append(MemoryText.label(meta, size: M.Card.Meta.fontSize, color: M.Card.Meta.color)) }
        let words = NSStackView(views: lines)
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = UILooks.pt(M.Card.gap)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var views: [NSView] = [tile, words]
        if let age, !age.isEmpty {
            let when = MemoryText.label(age, size: M.Card.Meta.fontSize, color: M.Card.Meta.color)
            when.setContentCompressionResistancePriority(.required, for: .horizontal)
            views.append(when)
        }
        let row = NSStackView(views: views)
        row.spacing = UILooks.pt(M.WikiRow.gap)
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(M.Card.padding.top) / 2, left: UILooks.pt(M.Card.padding.left) / 2,
                                      bottom: UILooks.pt(M.Card.padding.bottom) / 2, right: UILooks.pt(M.Card.padding.right) / 2)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(M.WikiRow.height)),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel([title, meta, age].compactMap { $0 }.joined(separator: ", "))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MemoryRow is created in code") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { press() }
    }

    override func rightMouseDown(with event: NSEvent) {
        let entries = self.entries()
        guard !entries.isEmpty else { return super.rightMouseDown(with: event) }
        PopupMenu.show(entries, at: convert(event.locationInWindow, from: nil), in: self)
    }

    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}

/// A page's kind as the tab draws it: a decision, a gotcha, a pattern, a rule, anything else.
@MainActor
enum MemoryKind {
    static func glyph(_ page: MemoryPage) -> (Icon, NSColor) {
        if page.relative.hasPrefix("_rules/") { return (.pushPin, DesignTokens.Color.stateReview) }
        switch (page.kind ?? "").lowercased() {
        case "decision": return (.checkCircle, DesignTokens.Color.stateWorking)
        case "gotcha", "pitfall", "warning": return (.warning, DesignTokens.Color.stateNeeds)
        case "pattern", "convention": return (.puzzlePiece, DesignTokens.Color.stateReview)
        case "concept", "fact", "entity", "insight": return (.lightbulb, DesignTokens.Color.textSecondary)
        default: return (.fileText, DesignTokens.Color.textSecondary)
        }
    }
}

/// "now", "12 min", "3 h", "yesterday", "4 d": how long ago, short.
enum MemoryAge {
    static func text(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return T("now", "agora") }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h" }
        let days = hours / 24
        return days == 1 ? T("yesterday", "ontem") : T("\(days) d", "\(days) d")
    }
}

@MainActor
enum MemoryText {
    static func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, wraps: Bool = false) -> NSTextField {
        let field = wraps ? NSTextField(wrappingLabelWithString: string) : NSTextField(labelWithString: string)
        field.font = UILooks.font(size, weight: weight)
        field.textColor = color
        if !wraps { field.lineBreakMode = .byTruncatingTail }
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}
