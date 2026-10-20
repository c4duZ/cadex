import AppKit
import Icons

/// The window of one open menu. It takes the keyboard (arrows, Return,
/// Esc) and closes when it loses it, as a click outside does.
final class PopupMenuPanel: NSPanel {
    var onClose: (@MainActor () -> Void)?
    private let list: PopupMenuList
    private weak var opener: NSWindow?
    private var closed = false

    init(entries: [MenuEntry], parent: NSWindow) {
        let size = NSSize(width: MenuLayout.width(entries), height: MenuLayout.totalHeight(entries))
        list = PopupMenuList(entries: entries, style: MenuStyle.current)
        opener = parent
        super.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        // Over the app in full screen, in its Space, like the settings
        // window (2026-10-20).
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient, .ignoresCycle]
        list.frame = NSRect(origin: .zero, size: size)
        list.onChoose = { [weak self] entry in self?.close(running: entry.action) }
        contentView = list
    }

    override var canBecomeKey: Bool { true }

    /// Top-left at `point` (screen), or bottom-left when `upward`; flipped
    /// when there is no room that way, and inside the screen sideways.
    func show(at point: NSPoint, upward: Bool) {
        let screen = (opener?.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var origin = NSPoint(x: point.x, y: upward ? point.y : point.y - frame.height)
        if upward, origin.y + frame.height > screen.maxY { origin.y = max(point.y - frame.height, screen.minY) }
        if !upward, origin.y < screen.minY { origin.y = min(point.y, screen.maxY - frame.height) }
        origin.x = min(max(origin.x, screen.minX), screen.maxX - frame.width)
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
    }

    override func resignKey() {
        super.resignKey()
        close(running: nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: list.move(by: 1)                      // ↓
        case 126: list.move(by: -1)                     // ↑
        case 36, 76: list.chooseSelected()              // Return, keypad Enter
        case 53: close(running: nil)                    // Esc
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        close(running: nil)
    }

    /// Hides the menu, gives the keyboard back to the window it opened
    /// over, then runs the chosen action there.
    func close(running action: (@MainActor () -> Void)?) {
        guard !closed else { return }
        closed = true
        orderOut(nil)
        if let opener, opener.isVisible { opener.makeKey() }
        action?()
        onClose?()
    }
}

/// The rows, drawn in one view: icon, title, keys, the selection as a
/// rounded fill in the theme's color.
final class PopupMenuList: NSView {
    var onChoose: ((MenuEntry) -> Void)?
    private let entries: [MenuEntry]
    private let style: MenuStyle
    private var selected: Int?

    init(entries: [MenuEntry], style: MenuStyle) {
        self.entries = entries
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = style.border.cgColor
        layer?.backgroundColor = style.background.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PopupMenuList is created in code") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseMoved(with event: NSEvent) { select(at: event) }
    override func mouseExited(with event: NSEvent) { setSelected(nil) }
    override func mouseDown(with event: NSEvent) { select(at: event) }

    override func mouseUp(with event: NSEvent) {
        select(at: event)
        chooseSelected()
    }

    override func rightMouseUp(with event: NSEvent) { mouseUp(with: event) }

    func move(by step: Int) {
        setSelected(MenuLayout.next(from: selected, by: step, in: entries))
    }

    func chooseSelected() {
        guard let selected else { return }
        onChoose?(entries[selected])
    }

    private func select(at event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let frames = MenuLayout.frames(entries, width: bounds.width)
        let index = frames.firstIndex { $0.contains(point) }
        setSelected(index.flatMap { entries[$0].isSeparator || !entries[$0].isEnabled ? nil : $0 })
    }

    private func setSelected(_ index: Int?) {
        guard index != selected else { return }
        selected = index
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, frame) in MenuLayout.frames(entries, width: bounds.width).enumerated() {
            let entry = entries[i]
            if entry.isSeparator {
                style.border.setFill()
                NSRect(x: frame.minX + 6, y: frame.midY, width: frame.width - 12, height: 1).fill()
                continue
            }
            if i == selected {
                style.selection.setFill()
                NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6).fill()
            }
            drawItem(entry, in: frame, selected: i == selected)
        }
    }

    private func drawItem(_ entry: MenuEntry, in frame: NSRect, selected: Bool) {
        let color = entry.isEnabled ? style.text : style.secondaryText.withAlphaComponent(0.5)
        var x = frame.minX + 10
        if let icon = entry.icon {
            let tint = !entry.isEnabled ? color : selected ? style.accent : style.secondaryText
            icon.image(size: 16).menuTinted(tint).draw(in: NSRect(x: x, y: frame.midY - 8, width: 16, height: 16))
            x += 24
        }
        let title = NSAttributedString(string: entry.title, attributes: [.font: MenuLayout.font, .foregroundColor: color])
        title.draw(at: NSPoint(x: x, y: frame.midY - title.size().height / 2))
        if let shortcut = entry.shortcut, entry.isEnabled { drawKeys(shortcut, right: frame.maxX - 6, midY: frame.midY) }
    }

    private func drawKeys(_ label: String, right: CGFloat, midY: CGFloat) {
        var x = right - MenuLayout.keycapsWidth(label)
        for key in MenuLayout.keys(of: label) {
            let width = MenuLayout.keycapWidth(key)
            let cap = NSRect(x: x, y: midY - 9, width: width, height: 18)
            let path = NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            style.keycap.setFill()
            path.fill()
            style.border.setStroke()
            path.stroke()
            let text = NSAttributedString(string: key, attributes: [.font: MenuLayout.keyFont, .foregroundColor: style.secondaryText])
            let size = text.size()
            text.draw(at: NSPoint(x: cap.midX - size.width / 2, y: cap.midY - size.height / 2))
            x += width + 3
        }
    }
}

extension NSImage {
    /// A template image filled with `color` (Phosphor glyphs are templates,
    /// and drawing one by hand does not tint it).
    func menuTinted(_ color: NSColor) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
