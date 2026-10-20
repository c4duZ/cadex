import AppKit
import Icons
import Menus
import Strings

/// The tab strip in the title bar, the bar's main element: tabs of equal
/// width side by side, as macOS's own tabs (Safari, Ghostty), each with its
/// own light fill so it reads as a tab, the active one stronger and marked
/// with a line in the theme's accent; × on the active tab and under the
/// pointer. The owner chose this over Terax's quiet pills, which gave the
/// space and the tabs the same weight (2026-10-19). Click selects,
/// double-click renames, dragging reorders, the middle button closes.
/// Drawn by hand so dragging is simple; colors come from the theme.
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
        /// The tab's kind: a terminal, or the document's (file by type,
        /// history, web page).
        var icon: Icon = .terminalWindow
        /// The file type's color (Swift orange, Markdown blue...), or nil:
        /// the accent when active, gray otherwise.
        var iconColor: NSColor?
        /// The Material drawing of the file, drawn as it is (over `icon`).
        var image: NSImage?
        /// Shown on hover: the terminal's folder or the file's path, which
        /// the title shortens.
        var tip: String?
    }

    static let height: CGFloat = 30
    /// Tabs shrink to this when many are open, then the strip clips.
    private static let minWidth: CGFloat = 96
    private static let maxWidth: CGFloat = 220
    private static let closeSize: CGFloat = 14
    private static let iconSize: CGFloat = 13
    private static let padding: CGFloat = 10
    private static let pillHeight: CGFloat = 28
    private static let pillRadius: CGFloat = 7
    private static let gap: CGFloat = 4

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
    /// The tab the middle button went down on.
    private var middlePressed: Int?
    private var dragging: (id: Int, startX: CGFloat, offset: CGFloat)?

    public override var isFlipped: Bool { true }
    /// Clicks on tabs must not drag the window from the title bar.
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    // MARK: Layout

    private func font(_ item: Item) -> NSFont {
        .systemFont(ofSize: 12, weight: item.active ? .medium : .regular)
    }

    /// Every tab at full width: the strip asks for this much.
    private var naturalWidths: [CGFloat] {
        items.map { _ in Self.maxWidth }
    }

    /// Equal widths, the most that fits, never under `minWidth`.
    private var frames: [NSRect] {
        let gaps = Self.gap * CGFloat(max(items.count - 1, 0))
        let fit = items.isEmpty ? Self.maxWidth : (bounds.width - gaps) / CGFloat(items.count)
        let width = min(max(fit, Self.minWidth), Self.maxWidth).rounded(.down)
        return items.indices.map { i in
            NSRect(x: CGFloat(i) * (width + Self.gap), y: 0, width: width, height: bounds.height)
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
        let fill = item.active ? style.activeFill : hovered ? style.hoverFill : style.text.withAlphaComponent(0.05)
        fill.setFill()
        NSBezierPath(roundedRect: pill, xRadius: Self.pillRadius, yRadius: Self.pillRadius).fill()
        if item.active {
            style.accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: pill.minX + 10, y: pill.maxY - 2.5, width: pill.width - 20, height: 2),
                         xRadius: 1, yRadius: 1).fill()
        }
        let color = item.active ? style.text : style.secondaryText

        let iconRect = NSRect(x: rect.minX + Self.padding, y: rect.midY - Self.iconSize / 2, width: Self.iconSize, height: Self.iconSize)
        if let image = item.image {
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: item.active ? 1 : 0.8)
        } else {
            let iconColor = item.iconColor.map { item.active ? $0 : $0.withAlphaComponent(0.75) } ?? (item.active ? style.accent : color)
            tinted(item.icon, size: Self.iconSize, color: iconColor).draw(in: iconRect)
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font(item), .foregroundColor: color, .paragraphStyle: paragraph]
        let textX = iconRect.maxX + 6
        let textWidth = max(closeFrame(in: rect).minX - 4 - textX, 0)
        let lineHeight = ceil(font(item).ascender - font(item).descender)
        (item.title as NSString).draw(in: NSRect(x: textX, y: rect.midY - lineHeight / 2, width: textWidth, height: lineHeight),
                                      withAttributes: attributes)

        guard hovered || item.active else { return }
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
        showTip(at: point)
    }

    public override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
        HoverTip.hide()
    }

    /// The tab's folder or path, or what × does (shared/menus HoverTip).
    private func showTip(at point: NSPoint) {
        guard dragging == nil, let i = index(at: point), i < items.count else { return HoverTip.hide() }
        let tab = frame(at: i)
        let close = closeFrame(in: tab)
        if close.insetBy(dx: -3, dy: -3).contains(point) { return HoverTip.hover(T("Close tab", "Fechar aba"), over: close, in: self) }
        HoverTip.hover(items[i].tip ?? items[i].title, over: tab, in: self)
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let i = index(at: point) else { return }
        let item = items[i]
        if closeFrame(in: frame(at: i)).contains(point), hovered == item.id || item.active {
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

    /// The middle button (mouse 3) closes the tab under it, as in browsers
    /// and VS Code (owner, 2026-10-19). On release, so a press that wanders
    /// off the tab closes nothing.
    public override func otherMouseDown(with event: NSEvent) {
        middlePressed = event.buttonNumber == 2 ? index(at: convert(event.locationInWindow, from: nil)).map { items[$0].id } : nil
    }

    public override func otherMouseUp(with event: NSEvent) {
        defer { middlePressed = nil }
        guard event.buttonNumber == 2, let pressed = middlePressed,
              let i = index(at: convert(event.locationInWindow, from: nil)), items[i].id == pressed else { return }
        onClose?(pressed)
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
