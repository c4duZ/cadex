import AppKit

/// A card over a status bar item while the pointer is on it: the usage of
/// every account, the SSH hosts, the ports (the owner liked the usage one,
/// 2026-10-21, and asked the same care for the others). It comes in softly
/// 0.18 s after the pointer arrives (rising 4 pt as it fades in, 0.15 s),
/// stays while the pointer is on the item, on the card or on the strip
/// between them, and goes the moment the pointer is on none of them (0.1 s
/// fade). While open it looks at the pointer 30 times a second; closed, it
/// costs nothing. Its first version waited on "pointer left" notices and
/// chained delays: it popped in and hung about a second on the way out
/// (owner, 2026-10-21). In the menus' colors, never taking the keyboard.
@MainActor
public final class HoverCard: NSObject {
    private weak var view: NSView?
    private let content: () -> NSView
    private(set) var panel: HoverCardPanel?
    private var pending: DispatchWorkItem?
    private var watch: Timer?

    /// Shows `content()`, rebuilt each time it opens, over `view`.
    /// Under the item instead of over it (an item of the title bar: the account, 2026-11-18).
    private let below: Bool

    public init(over view: NSView, below: Bool = false, content: @escaping () -> NSView) {
        self.view = view
        self.below = below
        self.content = content
        super.init()
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        HoverTip.yieldToCard(on: view)
        view.toolTip = nil
    }

    var isOpen: Bool { watch != nil }
    /// Told when the card opens (true) and closes (false): what it shows
    /// may be read only while it is open (the tailnet's machines, plan 23).
    public var onOpenChange: ((Bool) -> Void)?

    /// The card's content changed while it shows (a new reading): the new
    /// content in place, no animation, no new window.
    public func refresh() {
        guard isOpen, let panel else { return }
        panel.place(content(), at: view, below: below)
    }

    /// A click on the item: open now, no wait.
    public func openNow() {
        pending?.cancel()
        open()
    }

    /// From the keyboard or ⌘K (agents.show-accounts): the pointer is elsewhere, so the card
    /// stays until the pointer comes into it (then the usual rule), a click elsewhere or Esc. Opened
    /// as a hover card it closed in 33 ms (review of 2026-11-17).
    public func openPinned() {
        pending?.cancel()
        open()
        guard isOpen else { return }
        pinned = true
        pinMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode != 53 { return event }
            if event.type != .keyDown, event.window === self.panel { return event }
            self.close()
            return event.type == .keyDown ? nil : event
        }
    }
    private var pinned = false
    private var pinMonitor: Any?

    public func close() {
        pinned = false
        if let pinMonitor { NSEvent.removeMonitor(pinMonitor) }
        pinMonitor = nil
        pending?.cancel()
        let wasOpen = isOpen
        watch?.invalidate()
        watch = nil
        panel?.dismiss()
        if wasOpen { onOpenChange?(false) }
    }

    // The tracking area calls its owner by the Objective-C names; Swift's
    // own would be mouseEnteredWithEvent:, which nothing calls: the card
    // never opened (the owner's test, 2026-10-21).
    @objc(mouseEntered:) public func mouseEntered(with event: NSEvent) {
        guard !isOpen else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.open() } }
        pending = work
        // Passing over the bar on the way elsewhere does not open it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    @objc(mouseExited:) public func mouseExited(with event: NSEvent) {
        // Not open yet: the pointer only passed. Open: the watch decides.
        if !isOpen { pending?.cancel() }
    }

    private func open() {
        guard let view, view.window?.isVisible == true, !PopupMenu.isOpen, !isOpen else { return }
        let panel = self.panel ?? HoverCardPanel()
        self.panel = panel
        panel.place(content(), at: view, below: below)
        panel.present()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.look() } }
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
        onOpenChange?(true)
    }

    /// The pointer on the item, the card or the strip between: stay.
    private func look() {
        guard let view, let window = view.window, window.isVisible, let panel else { return close() }
        let pointer = NSEvent.mouseLocation
        let item = window.convertToScreen(view.convert(view.bounds, to: nil)).insetBy(dx: -2, dy: -2)
        let card = panel.frame.insetBy(dx: -2, dy: -2)
        let low = below ? card.maxY - 2 : item.maxY - 2
        let bridge = NSRect(x: min(item.minX, card.minX), y: low, width: max(item.maxX, card.maxX) - min(item.minX, card.minX),
                            height: max(below ? item.minY - card.maxY : card.minY - item.maxY, 0) + 4)
        let inside = item.contains(pointer) || card.contains(pointer) || bridge.contains(pointer)
        // Pinned: the pointer has not come yet; once it does, the hover rule takes over.
        if pinned {
            if inside { pinned = false }
            return
        }
        if !inside { close() }
    }
}

/// The card's window: rounded, the menus' ground and border.
@MainActor
final class HoverCardPanel: NSPanel {
    private let box = CardBox()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient]
        contentView = box
    }

    override var canBecomeKey: Bool { false }

    /// The content, sized, above `view` like a popover: the arrow on its
    /// bottom edge points at the item's middle, its tip on the item's top,
    /// so the pointer goes straight in. Kept on screen.
    func place(_ content: NSView, at view: NSView?, below: Bool) {
        guard let view, let window = view.window else { return }
        let style = MenuStyle.current
        box.fill = style.background
        box.stroke = style.border
        box.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 14 + (below ? CardBox.arrow : 0)),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -(14 + (below ? 0 : CardBox.arrow))),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
        ])
        box.layoutSubtreeIfNeeded()
        let size = box.fittingSize
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(x: rect.midX - size.width / 2, y: below ? rect.minY - size.height + 2 : rect.maxY - 2)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 6), screen.maxX - size.width - 6)
            origin.y = min(max(origin.y, screen.minY + 6), screen.maxY - size.height - 6)
        }
        box.pointsUp = below
        target = NSRect(origin: origin, size: size)
        if isVisible { setFrame(target, display: true) }
        box.arrowX = min(max(rect.midX - origin.x, 18), size.width - 18)
        box.needsDisplay = true
    }

    private var target = NSRect.zero

    /// In softly: from 4 pt lower and clear to its place, 0.15 s.
    func present() {
        alphaValue = 0
        setFrame(target.offsetBy(dx: 0, dy: -4), display: false)
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(target, display: true)
        }
    }

    /// Out in 0.1 s.
    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Opened again meanwhile: stay.
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }
}

/// The card's ground, drawn as a popover: a rounded box with an arrow on
/// its bottom edge pointing at the item.
private final class CardBox: NSView {
    static let arrow: CGFloat = 7
    var fill: NSColor = .windowBackgroundColor
    var stroke: NSColor = .separatorColor
    var arrowX: CGFloat = 40
    /// Under its item: the same shape upside down, the arrow on top.
    var pointsUp = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        if pointsUp {
            let flip = NSAffineTransform()
            flip.translateX(by: 0, yBy: bounds.height)
            flip.scaleX(by: 1, yBy: -1)
            flip.concat()
        }
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
