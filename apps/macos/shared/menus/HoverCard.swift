import AppKit

/// A card over a status bar item while the pointer is on it: the usage of
/// every account, the SSH hosts (the owner liked the usage one, 2026-10-21,
/// and asked the same care for the others). It opens 0.25 s after the
/// pointer arrives and stays while the pointer is on the item or on the
/// card: moving up into it keeps it open (the owner, 2026-10-21); it closes
/// 0.4 s after the pointer leaves both. It sits right on the item, so no gap
/// lets the pointer fall out on the way. In the menus' colors, never
/// taking the keyboard or the focus.
@MainActor
public final class HoverCard: NSObject {
    private weak var view: NSView?
    private let content: () -> NSView
    private(set) var panel: HoverCardPanel?
    private var pending: DispatchWorkItem?
    private var tracking: NSTrackingArea?

    /// Shows `content()`, rebuilt each time it opens, over `view`.
    public init(over view: NSView, content: @escaping () -> NSView) {
        self.view = view
        self.content = content
        super.init()
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        view.addTrackingArea(area)
        tracking = area
    }

    /// The card's content changed while it shows (a new reading).
    public func refresh() {
        guard let panel, panel.isVisible else { return }
        panel.show(content(), above: view)
    }

    /// A click on the item: open now, no wait.
    public func openNow() {
        pending?.cancel()
        open()
    }

    public func close() {
        pending?.cancel()
        panel?.orderOut(nil)
    }

    // The tracking area calls its owner by the Objective-C names; Swift's
    // own would be mouseEnteredWithEvent:, which nothing calls: the card
    // never opened (the owner's test, 2026-10-21).
    @objc(mouseEntered:) public func mouseEntered(with event: NSEvent) {
        if panel?.isVisible == true { schedule(open: false) } else { schedule(open: true) }
    }
    @objc(mouseExited:) public func mouseExited(with event: NSEvent) { schedule(open: false) }

    private func schedule(open: Bool) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if open { self.open() } else { self.closeIfLeft() }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (open ? 0.25 : 0.15), execute: work)
    }

    /// Closes unless the pointer is on the item or the card, by where it
    /// really is: the card's own "left" could be lost when its content was
    /// redrawn, and it stayed open after the pointer went (owner, 2026-10-21).
    /// While the pointer is on one of them it looks again in 0.15 s, so
    /// leaving either way closes it at once.
    private func closeIfLeft() {
        guard let panel, panel.isVisible else { return }
        let pointer = NSEvent.mouseLocation
        let itemRect = view.flatMap { v in v.window.map { $0.convertToScreen(v.convert(v.bounds, to: nil)) } } ?? .zero
        if panel.frame.contains(pointer) || itemRect.insetBy(dx: -2, dy: -4).contains(pointer) {
            schedule(open: false)
        } else {
            panel.orderOut(nil)
        }
    }

    private func open() {
        guard let view, view.window != nil, !PopupMenu.isOpen else { return }
        let panel = self.panel ?? HoverCardPanel()
        // Coming in or going out, the pointer's place decides (closeIfLeft).
        panel.onEnter = { [weak self] in self?.schedule(open: false) }
        panel.onLeave = { [weak self] in self?.schedule(open: false) }
        self.panel = panel
        panel.show(content(), above: view)
    }
}

/// The card's window: rounded, the menus' ground and border.
@MainActor
final class HoverCardPanel: NSPanel {
    var onEnter: (() -> Void)?
    var onLeave: (() -> Void)?
    private(set) var hasPointer = false
    private let box = CardBox()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient]
        box.onEnter = { [weak self] in
            self?.hasPointer = true
            self?.onEnter?()
        }
        box.onExit = { [weak self] in
            self?.hasPointer = false
            self?.onLeave?()
        }
        contentView = box
    }

    override var canBecomeKey: Bool { false }

    /// Above `view` like a popover: the arrow on its bottom edge points at
    /// the item's middle, its tip on the item's top, so the pointer goes
    /// straight in. Kept on screen; the arrow follows the item.
    func show(_ content: NSView, above view: NSView?) {
        guard let view, let window = view.window else { return }
        let style = MenuStyle.current
        box.fill = style.background
        box.stroke = style.border
        box.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -(14 + CardBox.arrow)),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
        ])
        box.layoutSubtreeIfNeeded()
        setContentSize(box.fittingSize)
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(x: rect.midX - frame.width / 2, y: rect.maxY - 2)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 6), screen.maxX - frame.width - 6)
            origin.y = min(origin.y, screen.maxY - frame.height - 6)
        }
        setFrameOrigin(origin)
        box.arrowX = min(max(rect.midX - origin.x, 18), frame.width - 18)
        box.needsDisplay = true
        orderFront(nil)
    }
}

/// The card's ground, drawn as a popover: a rounded box with an arrow on
/// its bottom edge pointing at the item; says when the pointer comes in and
/// goes out.
private final class CardBox: NSView {
    static let arrow: CGFloat = 7
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var fill: NSColor = .windowBackgroundColor
    var stroke: NSColor = .separatorColor
    var arrowX: CGFloat = 40

    override func draw(_ dirtyRect: NSRect) {
        let a = Self.arrow
        let body = NSRect(x: 0.5, y: a + 0.5, width: bounds.width - 1, height: bounds.height - a - 1)
        let path = NSBezierPath(roundedRect: body, xRadius: 10, yRadius: 10)
        let tip = NSBezierPath()
        tip.move(to: NSPoint(x: arrowX - a - 1, y: a + 0.5))
        tip.line(to: NSPoint(x: arrowX, y: 0.5))
        tip.line(to: NSPoint(x: arrowX + a + 1, y: a + 0.5))
        tip.close()
        path.append(tip)
        fill.setFill()
        path.fill()
        stroke.setStroke()
        // The border around the box and the arrow's two sides, not across
        // the arrow's root.
        NSBezierPath(roundedRect: body, xRadius: 10, yRadius: 10).stroke()
        fill.setFill()
        NSRect(x: arrowX - a, y: a - 0.5, width: a * 2, height: 2).fill()
        let sides = NSBezierPath()
        sides.move(to: NSPoint(x: arrowX - a - 1, y: a + 0.5))
        sides.line(to: NSPoint(x: arrowX, y: 0.5))
        sides.line(to: NSPoint(x: arrowX + a + 1, y: a + 0.5))
        sides.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// A line of a card that answers the pointer: a soft fill under it, the
/// action on a click (a host to connect to, "Test Again").
@MainActor
public final class HoverRow: NSView {
    public var onClick: (() -> Void)?
    private var hovering = false { didSet { layer?.backgroundColor = hovering ? MenuStyle.current.selection.cgColor : nil } }

    public init(_ content: NSView, inset: CGFloat = 6) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HoverRow is created in code") }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    public override func mouseEntered(with event: NSEvent) {
        hovering = true
        NSCursor.pointingHand.set()
    }

    public override func mouseExited(with event: NSEvent) {
        hovering = false
        NSCursor.arrow.set()
    }

    public override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    public override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
