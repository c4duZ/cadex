import AppKit

/// The name of an icon button, shown under it 0.2 s after the pointer
/// arrives, in the menus' colors. The system tooltip took about a second
/// and looked apart from the app (owner, 2026-10-20). One tip at a time;
/// it goes when the pointer leaves, on a click, a key or a scroll.
@MainActor
public enum HoverTip {
    static let delay: TimeInterval = 0.2

    /// Shows `text` over `view` on hover; nil removes it. Replaces the
    /// view's system tooltip, so the two never show together.
    public static func attach(_ text: String?, to view: NSView) {
        view.toolTip = nil
        view.setAccessibilityHelp(text)
        if let old = objc_getAssociatedObject(view, &trackerKey) as? HoverTipTracker {
            view.removeTrackingArea(old.area)
        }
        let tracker = text.flatMap { $0.isEmpty ? nil : HoverTipTracker(text: $0, view: view) }
        // The view keeps its tracker alive, and frees it with itself.
        objc_setAssociatedObject(view, &trackerKey, tracker, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        if let tracker { view.addTrackingArea(tracker.area) }
    }

    nonisolated(unsafe) private static var trackerKey: UInt8 = 0
    private static var pending: DispatchWorkItem?
    private static var panel: HoverTipPanel?
    private static var monitor: Any?

    static func pointerEntered(_ tracker: HoverTipTracker) {
        hide()
        let work = DispatchWorkItem { [weak tracker] in
            MainActor.assumeIsolated { if let tracker { show(tracker) } }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    static func pointerExited() {
        hide()
    }

    private static func show(_ tracker: HoverTipTracker) {
        guard let view = tracker.view, let window = view.window, window.isVisible, !PopupMenu.isOpen else { return }
        let panel = self.panel ?? HoverTipPanel()
        self.panel = panel
        panel.show(tracker.text, under: view, in: window)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { event in
            MainActor.assumeIsolated { hide() }
            return event
        }
    }

    static func hide() {
        pending?.cancel()
        pending = nil
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Where the tip goes: centered under the view, above it when there is
    /// no room below, inside the screen sideways (screen coordinates).
    static func origin(for size: NSSize, under anchor: NSRect, screen: NSRect) -> NSPoint {
        var x = anchor.midX - size.width / 2
        var y = anchor.minY - 6 - size.height
        if y < screen.minY { y = anchor.maxY + 6 }
        x = min(max(x, screen.minX + 4), screen.maxX - size.width - 4)
        return NSPoint(x: x, y: y)
    }
}

/// Watches the pointer over one view (a tracking area needs an owner that
/// answers mouseEntered and mouseExited).
@MainActor
final class HoverTipTracker: NSResponder {
    let text: String
    weak var view: NSView?
    private(set) var area: NSTrackingArea!

    init(text: String, view: NSView) {
        self.text = text
        self.view = view
        super.init()
        area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HoverTipTracker is created in code") }

    override func mouseEntered(with event: NSEvent) { HoverTip.pointerEntered(self) }
    override func mouseExited(with event: NSEvent) { HoverTip.pointerExited() }
}

/// The tip's window: a small rounded label that never takes the mouse or
/// the keyboard.
final class HoverTipPanel: NSPanel {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .transient, .ignoresCycle]
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 1
        label.font = .systemFont(ofSize: 11)
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        contentView = box
    }

    override var canBecomeKey: Bool { false }

    func show(_ text: String, under view: NSView, in window: NSWindow) {
        let style = MenuStyle.current
        label.stringValue = text
        label.textColor = style.text
        contentView?.layer?.backgroundColor = style.background.cgColor
        contentView?.layer?.borderColor = style.border.cgColor
        let size = NSSize(width: ceil(label.intrinsicContentSize.width) + 16, height: 22)
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        setFrame(NSRect(origin: HoverTip.origin(for: size, under: anchor, screen: screen), size: size), display: true)
        orderFront(nil)
    }
}
