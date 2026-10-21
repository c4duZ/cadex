import AppKit
import Strings
import UILooks

/// The theme's colors for a Customize window, the same as the settings
/// window's: text, quiet text, the accent, the ground, the rows' boxes.
public struct CustomizeColors {
    public var text: NSColor
    public var secondary: NSColor
    public var accent: NSColor
    public var panel: NSColor
    public var box: NSColor

    public init(text: NSColor = .labelColor, secondary: NSColor = .secondaryLabelColor, accent: NSColor = .controlAccentColor,
                panel: NSColor = .windowBackgroundColor, box: NSColor = .controlBackgroundColor) {
        self.text = text
        self.secondary = secondary
        self.accent = accent
        self.panel = panel
        self.box = box
    }
}

/// "Customize": a window of its own in front of the app, like the settings
/// window, listing things to show, hide and drag into place (the sidebar's
/// pages, the status bar's items). The owner asked on 2026-10-21 for the
/// prototype's look: first a system popover (blue switches, focus ring),
/// then a card under the button, both refused. Each change goes out at
/// once; Esc, ⌘W or the close button closes it.
@MainActor
public final class CustomizeWindow: NSWindow {
    private let list = CustomizeList()
    private let colors: CustomizeColors
    private let onChange: ([CustomizeEntry]) -> Void
    static var width: CGFloat { UILooks.pt(420) }

    public init(title: String, note: String, entries: [CustomizeEntry], colors: CustomizeColors,
                onChange: @escaping ([CustomizeEntry]) -> Void) {
        self.colors = colors
        self.onChange = onChange
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        self.title = title
        isReleasedWhenClosed = false
        // Over the app in full screen, in the same Space, as the settings window.
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        backgroundColor = colors.panel
        contentView = makeContent(title: title, note: note)
        list.onChange = { [weak self] entries in self?.onChange(entries) }
        list.show(entries, colors: colors)
    }

    /// What the list shows now.
    public var entries: [CustomizeEntry] { list.entries }

    /// Centered over the window it was opened from, with its look.
    public func show(over parent: NSWindow?) {
        appearance = parent?.effectiveAppearance
        contentView?.layoutSubtreeIfNeeded()
        if let size = contentView?.fittingSize { setContentSize(size) }
        if let parent {
            let frame = parent.frame
            setFrameOrigin(NSPoint(x: frame.midX - self.frame.width / 2, y: frame.midY - self.frame.height / 2))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
    }

    override public func cancelOperation(_ sender: Any?) { close() }

    private func makeContent(title: String, note: String) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = UILooks.font(15, weight: .semibold)
        heading.textColor = colors.text
        let noteLabel = NSTextField(wrappingLabelWithString: note)
        noteLabel.font = UILooks.font(12)
        noteLabel.textColor = colors.secondary
        let stack = NSStackView(views: [heading, noteLabel, list])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(10, after: noteLabel)
        // The top leaves room for the close button in the transparent title bar.
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let width = Self.width - 44
        for view in [noteLabel, list] as [NSView] { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
        noteLabel.preferredMaxLayoutWidth = width
        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.width),
        ])
        return root
    }
}

/// The switch of the prototype: a pill in the accent when on, the knob at
/// the end it points to.
@MainActor
final class CustomizeToggle: NSView {
    private(set) var isOn: Bool
    var onChange: ((Bool) -> Void)?
    private let colors: CustomizeColors
    private let knob = NSView()

    init(on: Bool, colors: CustomizeColors, label: String) {
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
    required init?(coder: NSCoder) { fatalError("CustomizeToggle is created in code") }

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
