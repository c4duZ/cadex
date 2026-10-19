import AppKit
import Icons

/// The tab strip in the title bar: one tab per item, as wide as its title,
/// with a small icon; the active one filled, × on hover, as in Terax (the
/// owner compared both on 2026-10-19: fixed-width pills with centered titles
/// looked unlike it). Click selects, double-click renames, dragging
/// reorders. Drawn by hand so dragging is simple; colors come from the
/// theme through `style`.
public final class TabBarView: NSView {
    /// The colors of the strip, set by whoever applies the theme.
    public struct Style {
        public var activeFill: NSColor
        public var hoverFill: NSColor
        public var text: NSColor
        public var secondaryText: NSColor
        /// The active tab's icon: where the theme shows in the strip.
        public var accent: NSColor

        public init(activeFill: NSColor, hoverFill: NSColor, text: NSColor, secondaryText: NSColor, accent: NSColor = .controlAccentColor) {
            self.activeFill = activeFill
            self.hoverFill = hoverFill
            self.text = text
            self.secondaryText = secondaryText
            self.accent = accent
        }
    }

    struct Item: Equatable {
        let id: Int
        let title: String
        let active: Bool
        /// A terminal tab, or a document (file, diff, history, preview).
        var terminal = true
    }

    static let height: CGFloat = 30
    private static let minWidth: CGFloat = 72
    private static let maxWidth: CGFloat = 200
    private static let closeSize: CGFloat = 14
    private static let iconSize: CGFloat = 13
    private static let padding: CGFloat = 10
    private static let pillHeight: CGFloat = 24
    private static let pillRadius: CGFloat = 6
    private static let gap: CGFloat = 2

    public var style = Style(activeFill: .controlBackgroundColor, hoverFill: .quaternaryLabelColor,
                             text: .labelColor, secondaryText: .secondaryLabelColor) {
        didSet { needsDisplay = true }
    }

    var items: [Item] = [] {
        didSet {
            needsDisplay = true
            if items != oldValue { invalidateIntrinsicContentSize() }
        }
    }

    /// As wide as its tabs, so "+" sits right after them; the title bar
    /// squeezes it when there is no room.
    public override var intrinsicContentSize: NSSize {
        NSSize(width: naturalWidths.reduce(0, +) + Self.gap * CGFloat(max(items.count - 1, 0)), height: Self.height)
    }
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?
    /// A tab dropped at a new position (index in the order).
    var onMove: ((Int, Int) -> Void)?

    private var hovered: Int?
    private var dragging: (id: Int, startX: CGFloat, offset: CGFloat)?

    public override var isFlipped: Bool { true }
    /// Clicks on tabs must not drag the window from the title bar.
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    // MARK: Layout

    private func font(_ item: Item) -> NSFont {
        .systemFont(ofSize: 12, weight: item.active ? .medium : .regular)
    }

    /// Icon, title and the room for × (kept so the title does not move on hover).
    private var naturalWidths: [CGFloat] {
        items.map { item in
            let text = (item.title as NSString).size(withAttributes: [.font: font(item)]).width
            let width = Self.padding + Self.iconSize + 6 + ceil(text) + 4 + Self.closeSize + Self.padding - 2
            return min(max(width, Self.minWidth), Self.maxWidth)
        }
    }

    /// The tabs' frames; when they do not fit, all shrink by the same factor.
    private var frames: [NSRect] {
        let widths = naturalWidths
        let gaps = Self.gap * CGFloat(max(items.count - 1, 0))
        let total = widths.reduce(0, +)
        let scale = total + gaps > bounds.width && total > 0 ? max(bounds.width - gaps, 0) / total : 1
        var x: CGFloat = 0
        return widths.map { width in
            defer { x += width * scale + Self.gap }
            return NSRect(x: x, y: 0, width: width * scale, height: bounds.height)
        }
    }

    private func frame(at index: Int) -> NSRect {
        let all = frames
        return index < all.count ? all[index] : .zero
    }

    private func closeFrame(in tab: NSRect) -> NSRect {
        NSRect(x: tab.maxX - Self.closeSize - Self.padding + 2, y: tab.midY - Self.closeSize / 2, width: Self.closeSize, height: Self.closeSize)
    }

    private func index(at point: NSPoint) -> Int? {
        frames.firstIndex { $0.minX <= point.x && point.x < $0.maxX + Self.gap }
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        let all = frames
        for (i, item) in items.enumerated() where i < all.count {
            var rect = all[i]
            if let drag = dragging, drag.id == item.id { rect.origin.x += drag.offset }
            drawTab(item, in: rect, hovered: hovered == item.id)
        }
    }

    private func drawTab(_ item: Item, in rect: NSRect, hovered: Bool) {
        let pill = NSRect(x: rect.minX, y: rect.midY - Self.pillHeight / 2, width: rect.width, height: Self.pillHeight)
        if item.active || hovered {
            (item.active ? style.activeFill : style.hoverFill).setFill()
            NSBezierPath(roundedRect: pill, xRadius: Self.pillRadius, yRadius: Self.pillRadius).fill()
        }
        let color = item.active ? style.text : style.secondaryText

        let iconRect = NSRect(x: rect.minX + Self.padding, y: rect.midY - Self.iconSize / 2, width: Self.iconSize, height: Self.iconSize)
        tinted(item.terminal ? .terminalWindow : .file, size: Self.iconSize, color: item.active ? style.accent : color).draw(in: iconRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font(item), .foregroundColor: color, .paragraphStyle: paragraph]
        let textX = iconRect.maxX + 6
        let textWidth = max(closeFrame(in: rect).minX - 4 - textX, 0)
        let lineHeight = ceil(font(item).ascender - font(item).descender)
        (item.title as NSString).draw(in: NSRect(x: textX, y: rect.midY - lineHeight / 2, width: textWidth, height: lineHeight),
                                      withAttributes: attributes)

        guard hovered else { return }
        tinted(.x, size: 11, color: style.secondaryText).draw(in: closeFrame(in: rect).insetBy(dx: 1.5, dy: 1.5))
    }

    /// A template icon in a color: drawn on a copy, filled over with sourceAtop.
    private func tinted(_ icon: Icon, size: CGFloat, color: NSColor) -> NSImage {
        let image = icon.image(size: size)
        return NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    // MARK: Mouse

    public override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let id = index(at: point).map { items[$0].id }
        if id != hovered {
            hovered = id
            needsDisplay = true
        }
    }

    public override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let i = index(at: point) else { return }
        let item = items[i]
        if closeFrame(in: frame(at: i)).contains(point), hovered == item.id {
            onClose?(item.id)
            return
        }
        if event.clickCount == 2 {
            onRename?(item.id)
            return
        }
        onSelect?(item.id)
        dragging = (item.id, point.x, 0)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard var drag = dragging else { return }
        drag.offset = convert(event.locationInWindow, from: nil).x - drag.startX
        dragging = drag
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        defer {
            dragging = nil
            needsDisplay = true
        }
        guard let drag = dragging, abs(drag.offset) > 4, let from = items.firstIndex(where: { $0.id == drag.id }) else { return }
        // The tab lands where its center is.
        let center = frame(at: from).midX + drag.offset
        let to = frames.lastIndex { $0.minX <= center } ?? 0
        if to != from { onMove?(drag.id, to) }
    }
}
