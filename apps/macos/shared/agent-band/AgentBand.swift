import AppKit
import QuartzCore

/// The pill that says an agent is acting (the preview's tab, another app of
/// the Mac): the system's HUD material, a dot pulsing in the accent color,
/// the text centered on one line, and at the end a key cap (`esc`) or a
/// Stop button. One look for both bands; the first ones were a label with a
/// painted background, its text off center (the owner, 2026-11-15).
@MainActor
public final class AgentBandView: NSView {
    public enum Trailing {
        /// A key cap that says which key stops it; the band takes no clicks.
        case key(String)
        /// A button, on the first click even with another app in front.
        case button(String, () -> Void)
    }

    public static let height: CGFloat = 32
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let background = NSVisualEffectView()
    private var action: (() -> Void)?
    private let takesClicks: Bool

    public init(trailing: Trailing, inWindow: Bool) {
        if case .button = trailing { takesClicks = true } else { takesClicks = false }
        super.init(frame: .zero)
        wantsLayer = true
        shadow = NSShadow()
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        background.material = .hudWindow
        background.blendingMode = inWindow ? .withinWindow : .behindWindow
        background.state = .active
        background.appearance = NSAppearance(named: .vibrantDark)
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.height / 2
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail

        // A dark tint over the blur: on a white page the HUD material alone
        // went flat grey and the white text lost its contrast (2026-11-15).
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.62).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.leadingAnchor.constraint(equalTo: background.leadingAnchor), tint.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            tint.topAnchor.constraint(equalTo: background.topAnchor), tint.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        let end = makeTrailing(trailing)
        let row = NSStackView(views: [dot, label, end])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.setCustomSpacing(10, after: label)
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        let rightInset: CGFloat = if case .button = trailing { 4 } else { 8 }
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: Self.height),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -rightInset),
            row.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentBandView is created in code") }

    public var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }

    /// The dot breathes while the band is up: the agent is there now.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, dot.layer?.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.35
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(pulse, forKey: "pulse")
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        takesClicks ? super.hitTest(point) : nil
    }

    private func makeTrailing(_ trailing: Trailing) -> NSView {
        switch trailing {
        case .key(let key):
            let cap = NSTextField(labelWithString: key)
            cap.font = .systemFont(ofSize: 10.5, weight: .semibold)
            cap.textColor = NSColor.white.withAlphaComponent(0.85)
            cap.alignment = .center
            let box = NSView()
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            box.layer?.cornerRadius = 5
            box.layer?.borderWidth = 0.5
            box.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            cap.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(cap)
            box.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                box.heightAnchor.constraint(equalToConstant: 18),
                cap.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
                cap.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
                cap.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            ])
            return box
        case .button(let title, let action):
            self.action = action
            let button = BandButton(title: title, target: self, action: #selector(pressed))
            return button
        }
    }

    @objc private func pressed() { action?() }
}

/// The band's Stop: a light capsule, and the first click counts, since the
/// agent's app is in front and Cadex is not (2026-11-15).
@MainActor
private final class BandButton: NSButton {
    override init(frame: NSRect) { super.init(frame: frame) }

    convenience init(title: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.cornerRadius = 12
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white])
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 24),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BandButton is created in code") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.3).cgColor
        super.mouseDown(with: event)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }
}
