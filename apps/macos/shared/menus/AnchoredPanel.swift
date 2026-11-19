import AppKit
import UILooks

/// A popover opened by a click on a button of the window (the bell, plan 26 phase D): a rounded
/// panel under the button in the new frame's popover look (components.popover: the raised fill,
/// the selected line, the two-layer shadow), no arrow, as the mockups draw it. It can take the
/// keyboard (an answer typed in a card) and closes on Esc, on a click outside it, and when the
/// window goes away. One at a time.
@MainActor
public final class AnchoredPanel: NSObject {
    public static private(set) weak var shown: AnchoredPanel?
    private let panel = AnchoredPanelWindow()
    private var monitor: Any?
    private var resign: NSObjectProtocol?
    /// The button it opened from: a click on it is the button's (to close), not an outside one.
    private weak var anchor: NSView?
    public var onClose: (() -> Void)?
    public var isOpen: Bool { panel.isVisible }

    public override init() { super.init() }

    /// Shows `content` under `view`, its right edge on the view's right edge, kept on screen.
    public func show(_ content: NSView, below view: NSView, width: CGFloat) {
        AnchoredPanel.shown?.close()
        guard view.window != nil else { return }
        anchor = view
        let box = panel.box
        box.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        Glass.dress(box, DesignTokens.Popover.bg)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: width),
        ])
        refit()
        view.window?.addChildWindow(panel, ordered: .above)
        // In front without the keyboard: typing stays in the terminal (review of 2026-11-17).
        panel.orderFront(nil)
        AnchoredPanel.shown = self
        watchOutside()
    }

    /// Sized again to what it holds now, still under its button: the content changed (a request
    /// came or went, Activity switched).
    public func refit() {
        guard let view = anchor, let window = view.window else { return }
        let box = panel.box
        box.layoutSubtreeIfNeeded()
        let size = box.fittingSize
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(x: rect.maxX - size.width, y: rect.minY - size.height - UILooks.pt(DesignTokens.Badge.top))
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX), screen.maxX - size.width)
            origin.y = max(origin.y, screen.minY)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    public func close() {
        guard AnchoredPanel.shown === self || panel.isVisible else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resign { NotificationCenter.default.removeObserver(resign) }
        resign = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        // The content leaves the panel, so a view that reads only while it shows stops reading.
        panel.box.subviews.forEach { $0.removeFromSuperview() }
        if AnchoredPanel.shown === self { AnchoredPanel.shown = nil }
        onClose?()
    }

    /// A click anywhere but in the panel or on its button, or Esc, closes it; the click still goes
    /// where it was (on the button it toggles). Leaving the app closes it too: the panel would hide
    /// with the app and come back by itself.
    private func watchOutside() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil } // Esc
                return event
            }
            if event.window === self.panel { return event }
            if let anchor = self.anchor, event.window === anchor.window,
               anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) { return event }
            self.close()
            return event
        }
        resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

/// The panel: borderless, it takes the keyboard without making the app's window lose its look.
final class AnchoredPanelWindow: NSPanel {
    let box = AnchoredBox()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        // The window's shadow: a layer's would be cut by the rounded clip.
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        collectionBehavior = [.fullScreenAuxiliary, .transient]
        contentView = box
    }

    override var canBecomeKey: Bool { true }
}

/// The popover's rounded ground with its line and shadows (components.popover).
final class AnchoredBox: NSView {
    typealias Look = DesignTokens.Popover

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(Look.radius)
        layer?.masksToBounds = true
        layer?.borderWidth = DesignTokens.Stroke.hairline
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AnchoredBox is created in code") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        // Under glass the ground is the GlassPane's (`show` dresses the box), not the layer's.
        if Glass.opacity == nil { layer?.backgroundColor = Look.bg.cgColor }
        layer?.borderColor = Look.border.cgColor
    }
}
