import AppKit
import Icons
import Strings
import UILooks

/// The "Trabalho | Arquivos" switch (components.workSidebar.switch): two words over the whole width,
/// the lit one on a solid fill.
@MainActor
final class WorkSwitch: NSView {
    typealias S = DesignTokens.WorkSidebar.Switch
    var onPick: ((WorkSidebarMode) -> Void)?
    private var options: [(WorkSidebarMode, NSTextField, NSView)] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = S.bg.cgColor
        layer?.borderColor = S.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(S.radius)
        let stack = NSStackView()
        stack.distribution = .fillEqually
        stack.spacing = UILooks.pt(S.gap)
        for (mode, title) in [(WorkSidebarMode.work, T("Work", "Trabalho")), (.files, T("Files", "Arquivos"))] {
            // The word centered in its own box: a label as tall as the box drew at its top.
            let label = NSTextField(labelWithString: title)
            label.alignment = .center
            let box = NSView()
            box.wantsLayer = true
            box.layer?.cornerRadius = UILooks.pt(S.Option.radius)
            label.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)
            NSLayoutConstraint.activate([
                box.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(S.Option.height)),
                label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                label.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            ])
            options.append((mode, label, box))
            stack.addArrangedSubview(box)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let pad = UILooks.pt(S.padding)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
        ])
        setAccessibilityRole(.radioGroup)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkSwitch is created in code") }

    func select(_ mode: WorkSidebarMode) {
        for (each, label, box) in options {
            let on = each == mode
            label.font = UILooks.font(S.Option.fontSize, weight: on ? S.On.weight : S.Option.weight)
            label.textColor = on ? S.On.color : S.Option.color
            box.layer?.backgroundColor = on ? S.On.bg.cgColor : nil
        }
    }

    var lit: WorkSidebarMode? { options.first { $0.2.layer?.backgroundColor != nil }?.0 }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onPick?(point.x < bounds.midX ? .work : .files)
    }
}

/// A project's main and tasks under it, hanging from a guide line (components.workSidebar.children).
@MainActor
final class WorkChildren: NSView {
    typealias C = DesignTokens.WorkSidebar.Children
    private let stack = NSStackView()
    private(set) var rows: [WorkRow] = []

    init() {
        super.init(frame: .zero)
        let guide = NSView()
        guide.wantsLayer = true
        guide.layer?.backgroundColor = C.guide.cgColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        for view in [guide, stack] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(C.indent)),
            guide.topAnchor.constraint(equalTo: topAnchor),
            guide.bottomAnchor.constraint(equalTo: bottomAnchor),
            guide.widthAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            stack.leadingAnchor.constraint(equalTo: guide.trailingAnchor, constant: UILooks.pt(C.paddingLeft)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(C.marginBottom)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkChildren is created in code") }

    func add(_ row: WorkRow) {
        rows.append(row)
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

/// A line of the foot (components.workSidebar.foot.row): an icon and a word; the click runs its command.
@MainActor
final class WorkFootRow: NSView {
    typealias F = DesignTokens.WorkSidebar.Foot.Row
    var onPress: (() -> Void)?
    private var hovering = false {
        didSet { layer?.backgroundColor = hovering ? DesignTokens.WorkSidebar.Row.Selected.bg.cgColor : nil }
    }

    init(title: String, icon: Icon) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(DesignTokens.WorkSidebar.Row.radius)
        let glyph = NSImageView(image: icon.fittedImage(size: UILooks.pt(F.icon)))
        glyph.contentTintColor = F.color
        let label = NSTextField(labelWithString: title)
        label.font = UILooks.font(F.fontSize)
        label.textColor = F.color
        let stack = NSStackView(views: [glyph, label])
        stack.spacing = UILooks.pt(F.gap)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.rowHeight(F.height)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(F.paddingX)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkFootRow is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}

/// The edge marker (components.workSidebar.edge): an amber bar as wide as the list saying who waits
/// out of sight; the click scrolls to it.
@MainActor
final class WorkEdge: NSView {
    typealias E = DesignTokens.WorkSidebar.Edge
    var onPress: (() -> Void)?
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = E.bg.cgColor
        layer?.borderColor = E.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(E.radius)
        label.font = UILooks.font(E.fontSize, weight: E.weight)
        label.textColor = E.color
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.rowHeight(E.height)),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(E.gap)),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(E.gap)),
        ])
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkEdge is created in code") }

    func say(_ text: String) {
        label.stringValue = text
        setAccessibilityLabel(text)
    }

    var said: String { label.stringValue }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}
