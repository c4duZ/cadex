import AppKit
import Icons
import UILooks

/// The list of a Customize window, as in the prototype approved on
/// 2026-10-21 (docs/plans/17-sidebar-agents-status.md): section titles and
/// a rounded box per row with a drag handle, the icon, the name, a value
/// lined up on the right and a switch in the theme's accent. Dragging a row
/// up or down reorders it while the mouse moves, past a title too; a click
/// on the switch flips it.
@MainActor
final class CustomizeList: NSView {
    static let spacing: CGFloat = 4
    /// A drag starts after the mouse moves this much (points).
    static let dragThreshold: CGFloat = 4

    var onChange: (([CustomizeEntry]) -> Void)?
    private(set) var entries: [CustomizeEntry] = []
    private(set) var views: [NSView] = []
    private var colors = CustomizeColors()
    private var drag: (view: CustomizeRowView, start: NSPoint, origin: CGFloat, moved: Bool)?

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func show(_ entries: [CustomizeEntry], colors: CustomizeColors) {
        self.entries = entries
        self.colors = colors
        views.forEach { $0.removeFromSuperview() }
        views = entries.map { entry in
            let view: NSView
            switch entry {
            case .header(let title): view = Self.header(title, colors: colors)
            case .row(let row):
                let rowView = CustomizeRowView(row: row, colors: colors)
                rowView.toggle.onChange = { [weak self] _ in self?.flip(row.id) }
                view = rowView
            }
            addSubview(view)
            return view
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    static func height(of entry: CustomizeEntry) -> CGFloat {
        switch entry {
        case .header: UILooks.rowHeight(26)
        case .row(let row): UILooks.rowHeight(row.subtitle == nil ? 40 : 52)
        }
    }

    override var intrinsicContentSize: NSSize {
        let total = entries.map(Self.height).reduce(0, +) + CGFloat(max(entries.count - 1, 0)) * Self.spacing
        return NSSize(width: NSView.noIntrinsicMetric, height: total)
    }

    override func layout() {
        super.layout()
        var y: CGFloat = 0
        for (index, view) in views.enumerated() {
            let height = Self.height(of: entries[index])
            if drag?.view !== view { view.frame = NSRect(x: 0, y: y, width: bounds.width, height: height) }
            y += height + Self.spacing
        }
    }

    private func flip(_ id: String) {
        entries = CustomizeLayout.flipped(entries, id)
        onChange?(entries)
    }

    private static func header(_ title: String, colors: CustomizeColors) -> NSView {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = UILooks.font(11, weight: .semibold)
        label.textColor = colors.secondary
        let box = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
        ])
        return box
    }

    // MARK: Drag

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let view = views.first(where: { $0.frame.contains(point) }) as? CustomizeRowView else { return }
        if view.toggle.frame.contains(view.convert(point, from: self)) { return view.toggle.flip() }
        drag = (view, point, view.frame.minY, false)
        // On top of the others while it moves: it slid under them and
        // vanished in the owner's test (2026-10-21).
        addSubview(view, positioned: .above, relativeTo: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var current = drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dy = point.y - current.start.y
        if !current.moved && abs(dy) < Self.dragThreshold { return }
        current.moved = true
        drag = current
        NSCursor.closedHand.set()
        let last = max(intrinsicContentSize.height - current.view.frame.height, 0)
        current.view.frame.origin.y = min(max(current.origin + dy, 0), last)
        guard let from = views.firstIndex(where: { $0 === current.view }) else { return }
        let heights = entries.map(Self.height)
        let to = CustomizeLayout.dropIndex(at: current.view.frame.midY, widths: heights, spacing: Self.spacing)
        let moved = CustomizeLayout.moved(entries, from: from, to: to)
        guard moved != entries else { return }
        let view = views.remove(at: from)
        views.insert(view, at: moved.firstIndex(of: entries[from]) ?? from)
        entries = moved
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            var y: CGFloat = 0
            for (index, other) in views.enumerated() {
                if other !== current.view { other.animator().frame.origin.y = y }
                y += Self.height(of: entries[index]) + Self.spacing
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let current = drag else { return }
        drag = nil
        NSCursor.arrow.set()
        needsLayout = true
        if current.moved { onChange?(entries) }
    }
}

/// One row in the list.
@MainActor
final class CustomizeRowView: NSView {
    let id: String
    let toggle: ThemeSwitch

    init(row: CustomizeRow, colors: CustomizeColors) {
        id = row.id
        toggle = ThemeSwitch(on: row.on, colors: colors, label: row.title)
        super.init(frame: .zero)
        // The settings window's row box: 8 pt corners, a 1 pt border.
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = colors.border.cgColor
        layer?.backgroundColor = colors.box.cgColor
        let handle = NSImageView(image: Icon.dotsSixVertical.image(size: UILooks.pt(13)))
        handle.contentTintColor = colors.secondary.withAlphaComponent(0.6)
        let icon = NSImageView(image: row.logo?.image(size: UILooks.pt(15)) ?? (row.icon ?? .dotsThree).image(size: UILooks.pt(15)))
        icon.contentTintColor = row.logo == nil ? colors.secondary : colors.text
        icon.isHidden = row.icon == nil && row.logo == nil
        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = colors.text
        title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: row.subtitle ?? "")
        subtitle.font = UILooks.font(11)
        subtitle.textColor = colors.secondary
        subtitle.lineBreakMode = .byTruncatingTail
        let texts = NSStackView(views: row.subtitle == nil ? [title] : [title, subtitle])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        let trailing = NSTextField(labelWithString: row.trailing ?? "")
        trailing.font = UILooks.font(11)
        trailing.textColor = colors.secondary
        trailing.alignment = .right
        for view in [handle, icon, texts, trailing, toggle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let textStart = row.icon == nil && row.logo == nil ? handle.trailingAnchor : icon.trailingAnchor
        NSLayoutConstraint.activate([
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            handle.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.leadingAnchor.constraint(equalTo: textStart, constant: 9),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -8),
            // A fixed column, so every switch lines up whatever the value.
            trailing.widthAnchor.constraint(equalToConstant: UILooks.pt(48)),
            trailing.trailingAnchor.constraint(equalTo: toggle.leadingAnchor, constant: -10),
            trailing.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("CustomizeRowView is created in code") }

    // The list handles clicks and drags.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}
