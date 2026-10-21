import AppKit
import Icons
import Strings
import UILooks

/// The row on top of the sidebar: the shown icons in order, a "…" for the
/// ones that do not fit, and the customize button on the right. Dragging an
/// icon sideways reorders it; a click without moving presses it.
@MainActor
final class SidebarIconRow: NSView {
    static let spacing: CGFloat = 2
    /// A drag starts after the mouse moves this much (points).
    static let dragThreshold: CGFloat = 4

    var onPress: ((String) -> Void)?
    var onReorder: (([String]) -> Void)?
    var onCustomize: ((NSView) -> Void)?
    /// The ids that did not fit, for the "…" menu under that button.
    var onOverflow: (([String], NSView) -> Void)?
    var colors = SidebarColors() { didSet { restyle() } }
    private(set) var buttons: [SidebarIconButton] = []
    private let more = SidebarIconButton(id: "…", icon: .dotsThree, tip: T("More", "Mais"))
    let customize = SidebarIconButton(id: "customize", icon: .slidersHorizontal,
                                              tip: T("Customize Sidebar", "Personalizar o painel lateral"))
    private var fitCount = 0
    /// The icon being dragged, where the mouse went down and where the icon was then.
    private var drag: (button: SidebarIconButton, start: NSPoint, originX: CGFloat, moved: Bool)?
    private var pressed: SidebarIconButton?

    init() {
        super.init(frame: .zero)
        for button in [more, customize] { addSubview(button) }
        customize.onPress = { [weak self] in self.map { $0.onCustomize?($0.customize) } }
        more.onPress = { [weak self] in self?.showOverflow() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarIconRow is created in code") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: SidebarIconButton.size.height) }
    override var isFlipped: Bool { true }
    // The row sits under the transparent title bar, where a press on a
    // view that allows it drags the window: dragging Files sideways did
    // nothing in the owner's test (2026-10-21). TitleBarButton does the same.
    override var mouseDownCanMoveWindow: Bool { false }

    /// The shown items, in order; each button is made once per id.
    func setItems(_ items: [SidebarItem]) {
        let old = Dictionary(uniqueKeysWithValues: buttons.map { ($0.id, $0) })
        buttons = items.map { item in
            if let button = old[item.id] { return button }
            let button = SidebarIconButton(id: item.id, icon: item.icon, tip: item.tip)
            button.onPress = { [weak self] in self?.onPress?(item.id) }
            return button
        }
        for button in old.values where !buttons.contains(where: { $0 === button }) { button.removeFromSuperview() }
        for button in buttons where button.superview == nil { addSubview(button, positioned: .below, relativeTo: more) }
        restyle()
        needsLayout = true
    }

    func select(_ id: String?) {
        for button in buttons { button.selected = button.id == id }
    }

    func setBadge(_ badge: String?, for id: String) {
        buttons.first { $0.id == id }?.badge = badge
    }

    override func layout() {
        super.layout()
        let size = SidebarIconButton.size
        let room = bounds.width - size.width - UILooks.pt(8)
        fitCount = SidebarLayout.fitting(buttons.count, iconWidth: size.width, spacing: Self.spacing, width: room)
        for (index, button) in buttons.enumerated() {
            button.isHidden = index >= fitCount
            if drag?.button !== button { button.frame = NSRect(origin: slot(index), size: size) }
        }
        more.isHidden = fitCount == buttons.count
        more.frame = NSRect(origin: slot(fitCount), size: size)
        customize.frame = NSRect(x: bounds.width - size.width, y: 0, width: size.width, height: size.height)
    }

    private func slot(_ index: Int) -> NSPoint {
        NSPoint(x: CGFloat(index) * (SidebarIconButton.size.width + Self.spacing), y: 0)
    }

    private func restyle() {
        for button in buttons + [more, customize] { button.colors = colors }
    }

    private func showOverflow() {
        onOverflow?(buttons.dropFirst(fitCount).map(\.id), more)
    }

    // MARK: Press or drag

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hit = (buttons + [more, customize]).first { !$0.isHidden && $0.frame.contains(point) }
        pressed = hit
        if let hit, buttons.prefix(fitCount).contains(where: { $0 === hit }) {
            drag = (hit, point, hit.frame.minX, false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - current.start.x
        if !current.moved && abs(dx) < Self.dragThreshold { return }
        if !current.moved {
            // On top of its neighbours while it moves: it slid under Files
            // in the owner's test (2026-10-21).
            addSubview(current.button, positioned: .above, relativeTo: nil)
            current.button.layer?.shadowOpacity = 0.35
            current.button.layer?.shadowRadius = 4
            current.button.layer?.shadowOffset = .zero
        }
        current.moved = true
        drag = current
        guard let from = buttons.firstIndex(where: { $0 === current.button }) else { return }
        // From where it was when the drag began: adding the whole move to
        // its new slot after a swap made it jump past its neighbour.
        current.button.frame.origin.x = min(max(current.originX + dx, 0), slot(fitCount - 1).x)
        let widths = Array(repeating: SidebarIconButton.size.width, count: fitCount)
        let to = SidebarLayout.dropIndex(at: current.button.frame.midX, widths: widths, spacing: Self.spacing)
        if to != from {
            buttons.remove(at: from)
            buttons.insert(current.button, at: to)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                for (index, button) in buttons.enumerated() where button !== current.button && index < fitCount {
                    button.animator().frame.origin = slot(index)
                }
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil; pressed = nil }
        if let current = drag, current.moved {
            current.button.layer?.shadowOpacity = 0
            needsLayout = true
            onReorder?(buttons.map(\.id))
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let pressed, pressed.frame.contains(point) { _ = pressed.accessibilityPerformPress() }
    }
}
