import AppKit
import Icons

/// The tab strip in the title bar: one pill per tab, the active one filled,
/// × to close on hover. Click selects, double-click renames, dragging
/// reorders. Drawn by hand so dragging is simple; colors come from the
/// theme through `style`.
public final class TabBarView: NSView {
    /// The colors of the strip, set by whoever applies the theme.
    public struct Style {
        public var activeFill: NSColor
        public var hoverFill: NSColor
        public var text: NSColor
        public var secondaryText: NSColor

        public init(activeFill: NSColor, hoverFill: NSColor, text: NSColor, secondaryText: NSColor) {
            self.activeFill = activeFill
            self.hoverFill = hoverFill
            self.text = text
            self.secondaryText = secondaryText
        }
    }

    struct Item: Equatable {
        let id: Int
        let title: String
        let active: Bool
    }

    static let height: CGFloat = 30
    private static let maxWidth: CGFloat = 180
    private static let closeSize: CGFloat = 16
    private static let pillInset: CGFloat = 2
    private static let pillRadius: CGFloat = 7

    public var style = Style(activeFill: .controlBackgroundColor, hoverFill: .quaternaryLabelColor,
                             text: .labelColor, secondaryText: .secondaryLabelColor) {
        didSet { needsDisplay = true }
    }

    var items: [Item] = [] {
        didSet {
            needsDisplay = true
            if items.count != oldValue.count { invalidateIntrinsicContentSize() }
        }
    }

    /// As wide as its tabs, so "+" sits right after them; the title bar
    /// squeezes it when there is no room.
    public override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(max(items.count, 1)) * Self.maxWidth, height: Self.height)
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

    private var tabWidth: CGFloat {
        guard !items.isEmpty else { return Self.maxWidth }
        return min(Self.maxWidth, bounds.width / CGFloat(items.count))
    }

    private func frame(at index: Int) -> NSRect {
        NSRect(x: CGFloat(index) * tabWidth, y: 0, width: tabWidth, height: bounds.height)
    }

    private func closeFrame(in tab: NSRect) -> NSRect {
        NSRect(x: tab.maxX - Self.closeSize - 8, y: tab.midY - Self.closeSize / 2, width: Self.closeSize, height: Self.closeSize)
    }

    private func index(at point: NSPoint) -> Int? {
        let i = Int(point.x / tabWidth)
        return i >= 0 && i < items.count ? i : nil
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        for (i, item) in items.enumerated() {
            var rect = frame(at: i)
            if let drag = dragging, drag.id == item.id { rect.origin.x += drag.offset }
            drawTab(item, in: rect, hovered: hovered == item.id)
        }
    }

    private func drawTab(_ item: Item, in rect: NSRect, hovered: Bool) {
        let pill = rect.insetBy(dx: Self.pillInset, dy: Self.pillInset)
        if item.active || hovered {
            (item.active ? style.activeFill : style.hoverFill).setFill()
            NSBezierPath(roundedRect: pill, xRadius: Self.pillRadius, yRadius: Self.pillRadius).fill()
        }

        let showClose = item.active || hovered
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: item.active ? .medium : .regular),
            .foregroundColor: item.active ? style.text : style.secondaryText,
            .paragraphStyle: paragraph,
        ]
        let inset = Self.closeSize + 14
        let textRect = NSRect(x: rect.minX + inset, y: rect.midY - 8, width: rect.width - inset * 2, height: 16)
        (item.title as NSString).draw(in: textRect, withAttributes: attributes)

        guard showClose else { return }
        let close = closeFrame(in: rect)
        // The template icon drawn in the text color: lock focus on a copy and
        // fill over it with sourceAtop.
        let image = Icon.x.image(size: 12)
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            self.style.secondaryText.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: close.insetBy(dx: 2, dy: 2))
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
        if closeFrame(in: frame(at: i)).contains(point), item.active || hovered == item.id {
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
        let to = min(max(Int(center / tabWidth), 0), items.count - 1)
        if to != from { onMove?(drag.id, to) }
    }
}
