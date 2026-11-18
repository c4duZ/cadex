import AppKit
import Icons
import Menus
import StateGlyph
import Strings
import UILooks

/// The empty Automations page (the proposal's `.empty`, enlarged by the owner on 2026-11-18): a
/// dashed box filling the area, the clock in a 64 pt square, "No automations yet", an example, and
/// Create automation in the middle; off, a note under it that creating the first turns them on.
@MainActor
final class AutomationsEmpty: NSView {
    /// What the page keeps above and around the box (its head and margins), so the box fills the rest.
    static let chrome: CGFloat = 170
    private let dash = CAShapeLayer()
    private let create: () -> Void

    init(create: @escaping () -> Void, off: Bool) {
        self.create = create
        super.init(frame: .zero)
        wantsLayer = true
        dash.fillColor = nil
        dash.strokeColor = DesignTokens.Color.lineControl.cgColor
        dash.lineWidth = DesignTokens.Stroke.hairline
        dash.lineDashPattern = [5, 4]
        layer?.addSublayer(dash)
        let square = NSView()
        square.wantsLayer = true
        square.layer?.backgroundColor = DesignTokens.Color.bgButton.cgColor
        square.layer?.cornerRadius = UILooks.pt(DesignTokens.Radius.card + 4)
        let clock = NSImageView(image: Icon.clock.image(size: UILooks.pt(32)))
        clock.contentTintColor = DesignTokens.Color.textSecondary
        clock.translatesAutoresizingMaskIntoConstraints = false
        square.addSubview(clock)
        NSLayoutConstraint.activate([
            square.widthAnchor.constraint(equalToConstant: UILooks.pt(64)), square.heightAnchor.constraint(equalToConstant: UILooks.pt(64)),
            clock.centerXAnchor.constraint(equalTo: square.centerXAnchor), clock.centerYAnchor.constraint(equalTo: square.centerYAnchor),
        ])
        let title = boardLabel(T("No automations yet", "Nenhuma automação ainda"), size: 20, color: DesignTokens.Color.textPrimary, weight: .bold)
        let example = NSTextField(wrappingLabelWithString: T("For example: every morning at 9, review the open PRs of a project and leave a summary.",
                                                             "Por exemplo: toda manhã às 9h, revisar os PRs abertos de um projeto e deixar um resumo."))
        example.font = UILooks.font(DesignTokens.FontSize.prompt)
        example.textColor = DesignTokens.Color.textSecondary
        example.alignment = .center
        example.preferredMaxLayoutWidth = UILooks.pt(460)
        let button = DesignButton.make("+  " + T("Create automation", "Criar automação"), .primary, height: 38) { [weak self] in self?.create() }
        var views: [NSView] = [square, title, example, button]
        if off { views.append(Self.note()) }
        let column = NSStackView(views: views)
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = UILooks.pt(8)
        column.setCustomSpacing(UILooks.pt(18), after: square)
        column.setCustomSpacing(UILooks.pt(22), after: example)
        column.setCustomSpacing(UILooks.pt(18), after: button)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: centerXAnchor), column.centerYAnchor.constraint(equalTo: centerYAnchor),
            column.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -UILooks.pt(48)),
            heightAnchor.constraint(greaterThanOrEqualTo: column.heightAnchor, constant: UILooks.pt(80)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AutomationsEmpty is created in code") }

    override func layout() {
        super.layout()
        let radius = UILooks.pt(DesignTokens.Radius.sheet)
        dash.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// "Automations are off. Creating the first one turns them on." in the permission's amber.
    private static func note() -> NSView {
        let text = boardLabel(T("Automations are off. Creating the first one turns them on.", "As automações estão desligadas. Criar a primeira as liga."),
                              size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textAmberNote)
        let box = NSStackView(views: [text])
        box.edgeInsets = NSEdgeInsets(top: UILooks.pt(8), left: UILooks.pt(12), bottom: UILooks.pt(8), right: UILooks.pt(12))
        box.wantsLayer = true
        box.layer?.backgroundColor = DesignTokens.Color.tintPermission.cgColor
        box.layer?.borderColor = DesignTokens.Color.lineAmber.cgColor
        box.layer?.borderWidth = DesignTokens.Stroke.hairline
        box.layer?.cornerRadius = UILooks.pt(DesignTokens.Radius.item)
        return box
    }
}

/// A line of the automations' table, or its head: the switch, name, when, project, account, last,
/// next, each column a share of the width; it lights under the pointer, a click opens, the right
/// click shows `menu`.
@MainActor
final class AutomationTableRow: NSView {
    /// The columns' shares after the switch: name, when, project, account, last, next.
    static let shares: [CGFloat] = [2.2, 1.4, 1.1, 1.3, 1.4, 1.1]
    var onPress: (() -> Void)?
    var onToggle: (() -> Void)?
    var entries: () -> [MenuEntry] = { [] }
    private let isHead: Bool
    private var hovering = false { didSet { layer?.backgroundColor = hovering && !isHead ? DesignTokens.Color.bgButton.cgColor : nil } }

    static func header() -> AutomationTableRow {
        let words = [T("NAME", "NOME"), T("WHEN", "QUANDO"), T("PROJECT", "PROJETO"), T("ACCOUNT", "CONTA"), T("LAST", "ÚLTIMA"), T("NEXT", "PRÓXIMA")]
        return AutomationTableRow(cells: words.map { boardLabel($0, size: DesignTokens.FontSize.caption, color: DesignTokens.Color.textTertiary, weight: .bold) },
                                  toggle: nil, head: true)
    }

    convenience init(_ line: AutomationsLine) {
        let body = { (text: String, color: NSColor) in boardLabel(text, size: DesignTokens.FontSize.panel, color: color) }
        let name = boardLabel(line.name, size: DesignTokens.FontSize.panel, color: DesignTokens.Color.textPrimary, weight: .semibold)
        var last: NSView = body(line.last, DesignTokens.Color.textRow)
        if let state = line.lastState {
            let glyph = StateGlyphView(size: DesignTokens.Pane.Header.glyph, state: state)
            glyph.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Pane.Header.glyph)).isActive = true
            glyph.heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Pane.Header.glyph)).isActive = true
            let pair = NSStackView(views: [glyph, last])
            pair.spacing = UILooks.pt(6)
            last = pair
        }
        let quiet = DesignTokens.Color.textTertiary
        // The account with Claude's logo in its orange, as the proposal's table.
        let logo = NSImageView(image: ProviderLogo.claude.image(size: UILooks.pt(11)))
        logo.contentTintColor = ProviderLogo.claude.brandColor
        let account = NSStackView(views: [logo, body(line.account, DesignTokens.Color.textRow)])
        account.spacing = UILooks.pt(5)
        self.init(cells: [name, body(line.when, DesignTokens.Color.textRow), body(line.project, DesignTokens.Color.textRow),
                          account, last, body(line.next, line.on ? DesignTokens.Color.textRow : quiet)],
                  toggle: line.on, head: false)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(line.name + ", " + line.when)
    }

    private init(cells: [NSView], toggle: Bool?, head: Bool) {
        isHead = head
        super.init(frame: .zero)
        wantsLayer = true
        let lead: NSView
        if let toggle {
            let toggleView = AutomationSwitch(on: toggle)
            toggleView.onPress = { [weak self] in self?.onToggle?() }
            lead = toggleView
        } else {
            lead = NSView()
        }
        lead.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lead)
        let pad = UILooks.pt(10)
        NSLayoutConstraint.activate([
            lead.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad), lead.centerYAnchor.constraint(equalTo: centerYAnchor),
            lead.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Project.Toggle.width)),
            heightAnchor.constraint(equalToConstant: UILooks.pt(head ? 32 : 40)),
        ])
        let total = Self.shares.reduce(0, +)
        var previous: NSLayoutXAxisAnchor = lead.trailingAnchor
        let room = widthAnchor
        for (cell, share) in zip(cells, Self.shares) {
            cell.translatesAutoresizingMaskIntoConstraints = false
            cell.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            addSubview(cell)
            NSLayoutConstraint.activate([
                cell.leadingAnchor.constraint(equalTo: previous, constant: pad),
                cell.centerYAnchor.constraint(equalTo: centerYAnchor),
                cell.widthAnchor.constraint(equalTo: room, multiplier: share / total, constant: -UILooks.pt(DesignTokens.Project.Toggle.width + 80) * share / total),
            ])
            previous = cell.trailingAnchor
        }
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = DesignTokens.Color.lineDefault.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor), line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AutomationTableRow is created in code") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    /// The first click of an inactive window presses too (the Projects card took none, 2026-11-18).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseMoved(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if !isHead, bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
    override func rightMouseDown(with event: NSEvent) {
        let entries = self.entries()
        guard !entries.isEmpty else { return }
        PopupMenu.show(entries, at: convert(event.locationInWindow, from: nil), in: self)
    }
}

/// The on/off switch of a line (components.project.toggle): green on, gray off, the knob moving.
@MainActor
final class AutomationSwitch: NSView {
    typealias Tg = DesignTokens.Project.Toggle
    var onPress: (() -> Void)?
    private let on: Bool

    init(on: Bool) {
        self.on = on
        super.init(frame: .zero)
        heightAnchor.constraint(equalToConstant: UILooks.pt(Tg.height)).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AutomationSwitch is created in code") }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - UILooks.pt(Tg.height)) / 2, width: UILooks.pt(Tg.width), height: UILooks.pt(Tg.height))
        (on ? Tg.on : Tg.off).setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()
        let knob = UILooks.pt(Tg.Knob.size)
        let x = on ? track.maxX - knob - (track.height - knob) / 2 : track.minX + (track.height - knob) / 2
        Tg.Knob.color.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: track.midY - knob / 2, width: knob, height: knob)).fill()
    }

    /// The first click of an inactive window presses too (the Projects card took none, 2026-11-18).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onPress?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
