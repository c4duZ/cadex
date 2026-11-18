import AppKit
import UILooks
import Icons
import Menus
import StateGlyph
import Strings

/// The tab strip in the title bar (components.tab of the new frame's tokens; screens.md,
/// TitleBar): each tab as wide as its title, the active one on the chip's fill in the primary
/// text, the others bare in the secondary text, with no line under them; the state glyph of
/// what runs in it (no icon otherwise); × under the pointer. This replaces the
/// equal-width native-looking tabs the owner chose on 2026-10-19, by the mockups approved on
/// 2026-11-17 (docs/adr/0035-work-frame.md). Click selects, double-click renames, dragging
/// reorders, the middle button closes. Drawn by hand so dragging is simple.
public final class TabBarView: NSView {
    /// The theme's colors, set by whoever applies it: the pane headers take them
    /// (onStyleChange); the strip itself draws in the new frame's tokens.
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
        /// Shown on hover: the terminal's folder or the file's path, which
        /// the title shortens.
        var tip: String?
        /// What runs in it (an agent's state): the state glyph before the title.
        var state: GlyphState?
        /// Something finished that the owner has not seen: the title in bold, no badge
        /// (docs/spec/tabs.md).
        var unseen = false
    }

    typealias Look = DesignTokens.Tab
    static var height: CGFloat { UILooks.pt(Look.height) }
    /// The longest a title goes before it is cut, and the narrowest a tab shrinks to when many
    /// are open (then the strip clips): the strip's own limits, not in the mockups.
    private static var maxTitle: CGFloat { UILooks.pt(Look.maxTitle) }
    private static var minWidth: CGFloat { UILooks.pt(Look.minWidth) }
    private static var closeSize: CGFloat { UILooks.pt(Look.close) }
    private static var padding: CGFloat { UILooks.pt(Look.paddingX) }
    private static var inner: CGFloat { UILooks.pt(Look.gap) }
    private static var pillRadius: CGFloat { UILooks.pt(Look.radius) }
    private static var gap: CGFloat { UILooks.pt(Look.groupGap) }

    public var style = Style(activeFill: .controlBackgroundColor, hoverFill: .quaternaryLabelColor,
                             text: .labelColor, secondaryText: .secondaryLabelColor) {
        didSet { needsDisplay = true; onStyleChange?() }
    }
    /// The theme changed the strip's colors: the pane headers take them too.
    var onStyleChange: (() -> Void)?

    var items: [Item] = [] {
        didSet {
            needsDisplay = true
            if items != oldValue { invalidateIntrinsicContentSize() }
            syncGlyphs()
        }
    }
    /// The state glyph of each tab that has one, by tab id: views, so the working ring spins.
    private var glyphs: [Int: StateGlyphView] = [:]

    /// As wide as its tabs, so "+" sits right after them; the title bar
    /// squeezes it when there is no room.
    public override var intrinsicContentSize: NSSize {
        NSSize(width: naturalWidths.reduce(0, +) + Self.gap * CGFloat(max(items.count - 1, 0)), height: Self.height)
    }
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?
    /// A right click on a tab, at a point of the bar (the tab is selected first).
    var onContextMenu: ((Int, NSPoint) -> Void)?
    /// A tab dropped at a new position (index in the order).
    var onMove: ((Int, Int) -> Void)?

    private var hovered: Int?
    /// The pointer on the hovered tab's ×: it lights, a round fill and the × brighter (the owner,
    /// 2026-11-18: the × gave no sign under the mouse).
    private var pointerOnClose = false
    /// The tab the middle button went down on.
    private var middlePressed: Int?
    var dragging: (id: Int, startX: CGFloat, offset: CGFloat)? { didSet { syncGlyphs() } }
    /// The other tabs sliding to their new places while one is dragged
    /// (TabBarDrag.swift): where each started and when.
    var slideFrom: [Int: CGFloat] = [:]
    var slideStart: CFTimeInterval = 0
    var slideTimer: Timer?
    var dragOrder: [Int] = []

    public override var isFlipped: Bool { true }
    /// Clicks on tabs must not drag the window from the title bar.
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    // MARK: Layout

    private func font(_ item: Item) -> NSFont {
        UILooks.font(DesignTokens.FontSize.body, weight: item.unseen ? DesignTokens.FontWeight.semibold
                     : item.active ? Look.Active.weight : .regular)
    }

    /// A tab as wide as its title with the glyph and the paddings, as the mockup draws it. Measured
    /// in the widest weight, so selecting a tab or an agent finishing does not move the others
    /// (review of 2026-11-17); × shows over the title's end, on its own fill, with no room kept.
    func naturalWidth(_ item: Item) -> CGFloat {
        let widest = UILooks.font(DesignTokens.FontSize.body, weight: DesignTokens.FontWeight.semibold)
        let title = min((item.title as NSString).size(withAttributes: [.font: widest]).width, Self.maxTitle)
        return (Self.padding * 2 + Self.lead(item) + title).rounded(.up)
    }

    private var naturalWidths: [CGFloat] { items.map(naturalWidth) }

    /// Each tab its natural width; when they do not fit, all shrink by the same share, never
    /// under `minWidth`.
    var widths: [Int: CGFloat] {
        let natural = naturalWidths
        let gaps = Self.gap * CGFloat(max(items.count - 1, 0))
        let total = natural.reduce(0, +)
        let share = total + gaps > bounds.width && total > 0 ? max(bounds.width - gaps, 0) / total : 1
        return Dictionary(uniqueKeysWithValues: zip(items.map(\.id), natural.map { max(($0 * share).rounded(.down), min($0, Self.minWidth)) }))
    }

    /// Where each tab of an order starts.
    func positions(_ order: [Int]) -> [Int: CGFloat] {
        let widths = widths
        var x: CGFloat = 0
        var out: [Int: CGFloat] = [:]
        for id in order {
            out[id] = x
            x += (widths[id] ?? 0) + Self.gap
        }
        return out
    }

    var frames: [NSRect] {
        let widths = widths, starts = positions(items.map(\.id))
        return items.map { NSRect(x: starts[$0.id] ?? 0, y: 0, width: widths[$0.id] ?? 0, height: bounds.height) }
    }

    func frame(at index: Int) -> NSRect {
        let all = frames
        return index < all.count ? all[index] : .zero
    }

    private func closeFrame(in tab: NSRect) -> NSRect {
        NSRect(x: tab.maxX - Self.closeSize - Self.inner, y: tab.midY - Self.closeSize / 2, width: Self.closeSize, height: Self.closeSize)
    }

    /// Behind ×, the tab's own fill, so the title's end does not show through it.
    private func closeBackdrop(in tab: NSRect) -> NSRect {
        let close = closeFrame(in: tab)
        return NSRect(x: close.minX - Self.inner, y: close.minY, width: tab.maxX - close.minX + Self.inner, height: close.height)
    }

    private func index(at point: NSPoint) -> Int? {
        frames.firstIndex { $0.minX <= point.x && point.x < $0.maxX + Self.gap }
    }

    // MARK: State glyphs

    public override func layout() {
        super.layout()
        syncGlyphs()
    }

    /// The glyph's size in the mockups' strip: 9 on the active tab, 7 on the others
    /// (components.stateGlyph sizes; screens.md, TitleBar).
    static func glyphSize(_ item: Item) -> CGFloat {
        let sizes = DesignTokens.StateGlyph.sizes
        return item.active ? sizes[1] : sizes[0]
    }

    /// One view per tab with a state, on its glyph spot; hidden while a tab is dragged
    /// (drawTab draws still ones then), gone with the state or the tab.
    private func syncGlyphs() {
        var kept: Set<Int> = []
        for (item, rect) in zip(items, frames) {
            guard let state = item.state else { continue }
            let size = Self.glyphSize(item)
            var view = glyphs[item.id]
            if view?.size != size {
                view?.removeFromSuperview()
                view = StateGlyphView(size: size)
                addSubview(view!)
                glyphs[item.id] = view
            }
            view?.state = state
            let margin = UILooks.pt(StateGlyphLook.margin(size: size))
            view?.frame = Self.glyphSpot(item, in: rect).insetBy(dx: -margin, dy: -margin)
            view?.isHidden = dragging != nil
            kept.insert(item.id)
        }
        for (id, view) in glyphs where !kept.contains(id) {
            view.removeFromSuperview()
            glyphs[id] = nil
        }
    }

    // MARK: Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard dragging != nil else {
            for (item, rect) in zip(items, frames) { drawTab(item, in: rect, hovered: hovered == item.id) }
            return
        }
        drawWhileDragging()
    }

    /// Room before the title: the state glyph and the gap when something runs, nothing else. The
    /// TitleBar mockup draws a tab as its dot (or no dot) and its name; the terminal and file
    /// icons made the strip busier than the drawing (owner, 2026-11-17).
    static func lead(_ item: Item) -> CGFloat {
        item.state == nil ? 0 : UILooks.pt(glyphSize(item)) + inner
    }

    /// The glyph's spot: right after the padding, as wide as the glyph.
    static func glyphSpot(_ item: Item, in rect: NSRect) -> NSRect {
        let side = UILooks.pt(glyphSize(item))
        return NSRect(x: rect.minX + padding, y: rect.midY - side / 2, width: side, height: side)
    }

    func drawTab(_ item: Item, in rect: NSRect, hovered: Bool) {
        let pill = NSRect(x: rect.minX, y: rect.midY - Self.height / 2, width: rect.width, height: Self.height)
        if item.active || hovered {
            (item.active ? Look.Active.bg : DesignTokens.Color.bgButton).setFill()
            NSBezierPath(roundedRect: pill, xRadius: Self.pillRadius, yRadius: Self.pillRadius).fill()
        }
        let color = item.active ? Look.Active.color : Look.Inactive.color

        // At rest the glyph is a view laid over its spot (it spins); while a tab is dragged the
        // strip draws a still one where the tab is now.
        if let state = item.state, dragging != nil { StateGlyphLook.draw(state, in: Self.glyphSpot(item, in: rect)) }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font(item), .foregroundColor: color, .paragraphStyle: paragraph]
        let textX = rect.minX + Self.padding + Self.lead(item)
        let textWidth = max(rect.maxX - Self.padding - textX, 0)
        let lineHeight = ceil(font(item).ascender - font(item).descender)
        (item.title as NSString).draw(in: NSRect(x: textX, y: rect.midY - lineHeight / 2, width: textWidth, height: lineHeight),
                                      withAttributes: attributes)

        // Only under the pointer: the mockups show no × on the active tab, and it would cover
        // the end of a title the tab is sized to (2026-11-17).
        guard hovered else { return }
        (item.active ? Look.Active.bg : DesignTokens.Color.bgButton).setFill()
        closeBackdrop(in: rect).fill()
        let close = closeFrame(in: rect)
        if pointerOnClose {
            Look.Inactive.color.withAlphaComponent(0.22).setFill()
            let spot = close.insetBy(dx: -UILooks.pt(DesignTokens.Stroke.glyph), dy: -UILooks.pt(DesignTokens.Stroke.glyph))
            NSBezierPath(ovalIn: spot).fill()
        }
        tinted(.x, size: Self.closeSize, color: pointerOnClose ? Look.Active.color : Look.Inactive.color).draw(in: close)
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
        let index = index(at: point)
        let id = index.map { items[$0].id }
        let close = index.map { closeFrame(in: frame(at: $0)).insetBy(dx: -3, dy: -3).contains(point) } ?? false
        if id != hovered || close != pointerOnClose {
            hovered = id
            pointerOnClose = close
            needsDisplay = true
        }
        showTip(at: point)
    }

    public override func mouseEntered(with event: NSEvent) {
        TitleBarHold.entered(self)
    }

    public override func mouseExited(with event: NSEvent) {
        TitleBarHold.exited(self, holding: dragging != nil)
        hovered = nil
        pointerOnClose = false
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
        beginDrag(item.id, at: point.x)
    }

    public override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let i = index(at: point) else { return }
        onSelect?(items[i].id)
        onContextMenu?(items[i].id, point)
    }

    public override func mouseDragged(with event: NSEvent) {
        moveDrag(to: convert(event.locationInWindow, from: nil).x)
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
        endDrag()
        TitleBarHold.released(self, event)
    }
}
