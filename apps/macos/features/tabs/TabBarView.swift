import AppKit

/// The tab strip above the terminal: one cell per tab, the active one
/// highlighted, × to close on hover. Click selects, double-click renames,
/// dragging reorders. Drawn by hand so dragging is simple; the final look
/// comes with the themes feature (plan 3).
final class TabBarView: NSView {
    struct Item: Equatable {
        let id: Int
        let title: String
        let active: Bool
    }

    static let height: CGFloat = 30
    private static let maxWidth: CGFloat = 220
    private static let closeSize: CGFloat = 16

    var items: [Item] = [] { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?
    /// A tab dropped at a new position (index in the order).
    var onMove: ((Int, Int) -> Void)?

    private var hovered: Int?
    private var dragging: (id: Int, startX: CGFloat, offset: CGFloat)?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
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

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        for (i, item) in items.enumerated() {
            var rect = frame(at: i)
            if let drag = dragging, drag.id == item.id { rect.origin.x += drag.offset }
            drawTab(item, in: rect, hovered: hovered == item.id)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    private func drawTab(_ item: Item, in rect: NSRect, hovered: Bool) {
        if item.active {
            NSColor.controlBackgroundColor.setFill()
            rect.fill()
        }
        NSColor.separatorColor.setFill()
        NSRect(x: rect.maxX - 1, y: rect.minY + 6, width: 1, height: rect.height - 12).fill()

        let showClose = item.active || hovered
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: item.active ? .medium : .regular),
            .foregroundColor: item.active ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        let inset = Self.closeSize + 14
        let textRect = NSRect(x: rect.minX + inset, y: rect.midY - 8, width: rect.width - inset * 2, height: 16)
        (item.title as NSString).draw(in: textRect, withAttributes: attributes)

        guard showClose else { return }
        let close = closeFrame(in: rect)
        let image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Fechar aba")
        image?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))?
            .draw(in: close.insetBy(dx: 3, dy: 3))
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let id = index(at: point).map { items[$0].id }
        if id != hovered {
            hovered = id
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
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

    override func mouseDragged(with event: NSEvent) {
        guard var drag = dragging else { return }
        drag.offset = convert(event.locationInWindow, from: nil).x - drag.startX
        dragging = drag
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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
