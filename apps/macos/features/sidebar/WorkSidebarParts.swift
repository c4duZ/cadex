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
    /// For tests: each option's word and whether it is drawn as the chosen one (bold, primary).
    var words: [(WorkSidebarMode, Bool)] { options.map { ($0.0, $0.1.textColor == S.On.color) } }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
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
        // The guide runs from the first line's text to the last one's, not the rows' whole height:
        // across the group and its bottom margin it stood taller than the text and lower than it,
        // out of line (the owner, 2026-11-24: "a linha da esquerda tá muito grande e torta").
        let font = UILooks.font(C.fontSize)
        let inset = max(0, (UILooks.rowHeight(DesignTokens.WorkSidebar.Row.height) - ceil(font.ascender - font.descender)) / 2)
        NSLayoutConstraint.activate([
            guide.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(C.indent)),
            guide.topAnchor.constraint(equalTo: stack.topAnchor, constant: inset),
            guide.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: -inset),
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
    typealias Lit = DesignTokens.MemoryPanel.Nav.FootItem
    var onPress: (() -> Void)?
    private var hovering = false { didSet { paint() } }
    /// Its page is open (Memória, plan 40 C): the selected fill and the primary text.
    var lit = false { didSet { paint() } }
    private let glyph: NSImageView
    private let label: NSTextField
    /// Small on the right ("ai-memory 3.5.0"), only while lit.
    private let detail = NSTextField(labelWithString: "")

    init(title: String, icon: Icon) {
        glyph = NSImageView(image: icon.fittedImage(size: UILooks.pt(F.icon)))
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(DesignTokens.WorkSidebar.Row.radius)
        label.font = UILooks.font(F.fontSize)
        detail.font = UILooks.font(Lit.Version.fontSize)
        detail.textColor = Lit.Version.color
        detail.isHidden = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [glyph, label, spacer, detail])
        stack.spacing = UILooks.pt(F.gap)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.rowHeight(F.height)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(F.paddingX)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(F.paddingX)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        paint()
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    func setDetail(_ text: String) { detail.stringValue = text }

    var detailSaid: String { detail.isHidden ? "" : detail.stringValue }

    private func paint() {
        layer?.backgroundColor = lit ? Lit.Selected.bg.cgColor : hovering ? DesignTokens.WorkSidebar.Row.Selected.bg.cgColor : nil
        let color = lit ? Lit.Selected.color : F.color
        label.textColor = color
        glyph.contentTintColor = color
        detail.isHidden = !lit || detail.stringValue.isEmpty
        setAccessibilityValue(lit ? T("open", "aberta") : nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkFootRow is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
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
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}

/// Files' head (components.workSidebar.files.head): the place's name and, under it, what it is.
@MainActor
final class WorkFilesHead: NSView {
    typealias H = DesignTokens.WorkSidebar.Files.Head
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        title.font = UILooks.font(H.fontSize, weight: H.weight)
        title.textColor = DesignTokens.Color.textPrimary
        detail.font = UILooks.font(H.Detail.fontSize)
        detail.textColor = H.Detail.color
        for label in [title, detail] {
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(H.padding.left)),
            title.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -UILooks.pt(H.padding.right)),
            detail.topAnchor.constraint(equalTo: title.bottomAnchor),
            detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -UILooks.pt(H.padding.right)),
            detail.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(H.padding.bottom)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkFilesHead is created in code") }

    /// The Files page's buttons at the right of the name (the owner, 2026-11-20: not a row of their own).
    func hold(_ accessory: NSView) {
        accessory.translatesAutoresizingMaskIntoConstraints = false
        accessory.setContentHuggingPriority(.required, for: .horizontal)
        accessory.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(accessory)
        let gap = UILooks.pt(H.padding.right)
        NSLayoutConstraint.activate([
            accessory.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -gap),
            accessory.centerYAnchor.constraint(equalTo: title.bottomAnchor),
            title.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -gap),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -gap),
        ])
    }

    func say(_ name: String, _ what: String) {
        title.stringValue = name
        detail.stringValue = what
        toolTip = name + " · " + what
    }

    var said: String { title.stringValue + " · " + detail.stringValue }
}

/// "N changes · see" (components.workSidebar.changes): Changes, discreet, at the end of the tree.
@MainActor
final class WorkChangesLine: NSView {
    typealias C = DesignTokens.WorkSidebar.Changes
    var onPress: (() -> Void)?
    private let words = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderColor = C.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(C.radius)
        words.font = UILooks.font(C.fontSize)
        words.textColor = C.color
        let see = NSTextField(labelWithString: T("see", "ver"))
        see.font = UILooks.font(C.fontSize, weight: C.Link.weight)
        see.textColor = C.Link.color
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [words, spacer, see])
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.rowHeight(C.height)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(C.padding.left)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(C.padding.right)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkChangesLine is created in code") }

    func say(_ count: Int) {
        words.stringValue = count == 1 ? T("1 change", "1 mudança") : T("\(count) changes", "\(count) mudanças")
        setAccessibilityLabel(words.stringValue)
    }

    var said: String { words.stringValue }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
}
