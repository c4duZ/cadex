import AppKit
import Icons
import UILooks

/// The rows of the Customize panel, as in the prototype approved on
/// 2026-10-21 (docs/plans/17-sidebar-agents-status.md): a rounded box per
/// page with a drag handle, the icon, the name, the shortcut lined up on
/// the right and a switch in the theme's accent. Dragging a row up or down
/// reorders it; a click on the switch flips it.
@MainActor
final class SidebarCustomizeList: NSView {
    static var rowHeight: CGFloat { UILooks.rowHeight(34) }
    static let spacing: CGFloat = 4

    var onFlip: ((String) -> Void)?
    var onMove: ((String, Int) -> Void)?
    private(set) var rows: [SidebarCustomizeRow] = []
    private var drag: (row: SidebarCustomizeRow, start: NSPoint, origin: CGFloat, moved: Bool)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func show(_ items: [SidebarItem], shown: [String], colors: SidebarColors) {
        rows.forEach { $0.removeFromSuperview() }
        rows = items.map { item in
            let row = SidebarCustomizeRow(item: item, on: shown.contains(item.id), colors: colors)
            row.toggle.onChange = { [weak self] _ in self?.onFlip?(item.id) }
            addSubview(row)
            return row
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: CGFloat(rows.count) * (Self.rowHeight + Self.spacing) - Self.spacing)
    }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() where drag?.row !== row {
            row.frame = NSRect(x: 0, y: y(index), width: bounds.width, height: Self.rowHeight)
        }
    }

    private func y(_ index: Int) -> CGFloat { CGFloat(index) * (Self.rowHeight + Self.spacing) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let row = rows.first(where: { $0.frame.contains(point) }) else { return }
        if row.toggle.frame.contains(row.convert(point, from: self)) { return row.toggle.flip() }
        drag = (row, point, row.frame.minY, false)
        row.layer?.zPosition = 1
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dy = point.y - current.start.y
        if !current.moved && abs(dy) < SidebarIconRow.dragThreshold { return }
        current.moved = true
        drag = current
        NSCursor.closedHand.set()
        current.row.frame.origin.y = min(max(current.origin + dy, 0), y(rows.count - 1))
        guard let from = rows.firstIndex(where: { $0 === current.row }) else { return }
        let heights = Array(repeating: Self.rowHeight, count: rows.count)
        let to = SidebarLayout.dropIndex(at: current.row.frame.midY, widths: heights, spacing: Self.spacing)
        guard to != from else { return }
        rows.remove(at: from)
        rows.insert(current.row, at: to)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            for (index, row) in rows.enumerated() where row !== current.row { row.animator().frame.origin.y = y(index) }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = drag else { return }
        drag = nil
        current.row.layer?.zPosition = 0
        NSCursor.arrow.set()
        needsLayout = true
        if current.moved, let index = rows.firstIndex(where: { $0 === current.row }) {
            onMove?(current.row.id, index)
        }
    }
}

/// One page in the list.
@MainActor
final class SidebarCustomizeRow: NSView {
    let id: String
    let toggle: SidebarToggle

    init(item: SidebarItem, on: Bool, colors: SidebarColors) {
        id = item.id
        toggle = SidebarToggle(on: on, colors: colors, label: item.title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = colors.box.cgColor
        let handle = NSImageView(image: Icon.dotsSixVertical.image(size: UILooks.pt(13)))
        handle.contentTintColor = colors.secondary.withAlphaComponent(0.6)
        let icon = NSImageView(image: item.icon.image(size: UILooks.pt(15)))
        icon.contentTintColor = colors.secondary
        let title = NSTextField(labelWithString: item.title)
        title.font = UILooks.font(13)
        title.textColor = colors.text
        title.lineBreakMode = .byTruncatingTail
        let key = NSTextField(labelWithString: item.shortcut ?? "")
        key.font = UILooks.font(11)
        key.textColor = colors.secondary
        key.alignment = .right
        for view in [handle, icon, title, key, toggle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            handle.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: key.leadingAnchor, constant: -8),
            // A fixed column, so every switch lines up whatever the shortcut.
            key.widthAnchor.constraint(equalToConstant: UILooks.pt(48)),
            key.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -10),
            key.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarCustomizeRow is created in code") }

    // The list handles clicks and drags.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}

/// The switch of the prototype: a pill in the accent when on, the knob at
/// the end it points to.
@MainActor
final class SidebarToggle: NSView {
    private(set) var isOn: Bool
    var onChange: ((Bool) -> Void)?
    private let colors: SidebarColors
    private let knob = NSView()

    init(on: Bool, colors: SidebarColors, label: String) {
        isOn = on
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        knob.wantsLayer = true
        knob.layer?.backgroundColor = NSColor.white.cgColor
        addSubview(knob)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(label)
        restyle(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarToggle is created in code") }

    override var intrinsicContentSize: NSSize { NSSize(width: UILooks.pt(32), height: UILooks.pt(19)) }

    func flip() {
        isOn.toggle()
        restyle(animated: true)
        onChange?(isOn)
    }

    override func accessibilityValue() -> Any? { isOn }
    override func accessibilityPerformPress() -> Bool {
        flip()
        return true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        restyle(animated: false)
    }

    private func restyle(animated: Bool) {
        layer?.backgroundColor = (isOn ? colors.accent : colors.secondary.withAlphaComponent(0.3)).cgColor
        let side = max(bounds.height - 4, 0)
        let frame = NSRect(x: isOn ? bounds.width - side - 2 : 2, y: 2, width: side, height: side)
        knob.layer?.cornerRadius = side / 2
        if animated { knob.animator().frame = frame } else { knob.frame = frame }
    }
}
