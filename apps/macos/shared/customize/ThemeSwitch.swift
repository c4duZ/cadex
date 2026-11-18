import AppKit
import UILooks

/// The app's switch, from the prototype approved on 2026-10-21: a pill in
/// the theme's accent when on, the knob at the end it points to. Customize
/// and the settings window use it, so the two look the same (the owner,
/// 2026-10-21); the system's switch ignored the theme's accent.
@MainActor
public final class ThemeSwitch: NSView {
    public private(set) var isOn: Bool
    public var onChange: ((Bool) -> Void)?
    private let accent: NSColor
    private let off: NSColor
    private let knob = NSView()

    public init(on: Bool, accent: NSColor, off: NSColor, label: String) {
        isOn = on
        self.accent = accent
        self.off = off
        super.init(frame: .zero)
        wantsLayer = true
        knob.wantsLayer = true
        knob.layer?.backgroundColor = NSColor.white.cgColor
        knob.layer?.shadowOpacity = 0.2
        knob.layer?.shadowRadius = 1
        knob.layer?.shadowOffset = .zero
        addSubview(knob)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(label)
        setContentHuggingPriority(.required, for: .horizontal)
        restyle(animated: false)
    }

    convenience init(on: Bool, colors: CustomizeColors, label: String) {
        self.init(on: on, accent: colors.accent, off: colors.secondary.withAlphaComponent(0.3), label: label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ThemeSwitch is created in code") }

    override public var intrinsicContentSize: NSSize { NSSize(width: UILooks.pt(32), height: UILooks.pt(19)) }

    public func flip() {
        isOn.toggle()
        restyle(animated: true)
        onChange?(isOn)
    }

    // A click anywhere on it flips it (inside Customize the list does that).
    override public func mouseDown(with event: NSEvent) { flip() }
    override public var mouseDownCanMoveWindow: Bool { false }

    override public func accessibilityValue() -> Any? { isOn }
    override public func accessibilityPerformPress() -> Bool {
        flip()
        return true
    }

    override public func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        restyle(animated: false)
    }

    private func restyle(animated: Bool) {
        layer?.backgroundColor = (isOn ? accent : off).cgColor
        let side = max(bounds.height - 4, 0)
        let frame = NSRect(x: isOn ? bounds.width - side - 2 : 2, y: 2, width: side, height: side)
        knob.layer?.cornerRadius = side / 2
        if animated { knob.animator().frame = frame } else { knob.frame = frame }
    }
}
