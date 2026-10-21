import AppKit
import Icons
import Strings
import UILooks

/// The theme's colors for the Customize window, the same as the settings
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

/// One tab of the Customize window: the sidebar's icons, the status bar's
/// items. Its owner builds it and takes back each change.
public struct CustomizePage {
    public let id: String
    public let title: String
    public let icon: Icon
    public let note: String
    public let entries: [CustomizeEntry]
    public let onChange: ([CustomizeEntry]) -> Void

    public init(id: String, title: String, icon: Icon, note: String, entries: [CustomizeEntry], onChange: @escaping ([CustomizeEntry]) -> Void) {
        self.id = id
        self.title = title
        self.icon = icon
        self.note = note
        self.entries = entries
        self.onChange = onChange
    }
}

/// "Customize": one window for the whole app, like the settings window,
/// with a tab per thing to arrange (the owner, 2026-10-21: one window with
/// tabs, not a window per bar). Over the app in full screen, in the same
/// Space, as settings; Esc, ⌘W or the close button closes it. The look is
/// the prototype's (a system popover and a card under the button were
/// refused). Each change goes out at once.
@MainActor
public final class CustomizeWindow: NSWindow {
    public static let shared = CustomizeWindow()

    private let tabs = NSSegmentedControl()
    private let note = NSTextField(wrappingLabelWithString: "")
    private let list = CustomizeList()
    private var pages: [CustomizePage] = []
    private var colors = CustomizeColors()
    private(set) var selected = 0
    static var width: CGFloat { UILooks.pt(440) }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 300),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        title = T("Customize", "Personalizar")
        isReleasedWhenClosed = false
        // Over the app in full screen, in the same Space: a plain window
        // opened in another Space and took the user out of the app (the
        // settings window's lesson, 2026-10-20).
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        contentView = makeContent()
        tabs.target = self
        tabs.action = #selector(tabChanged)
        list.onChange = { [weak self] entries in
            guard let self, self.pages.indices.contains(self.selected) else { return }
            self.pages[self.selected].onChange(entries)
        }
    }

    /// Opens on the page `id` with these pages (from the window that
    /// asked), centered over that window the first time.
    public func show(_ pages: [CustomizePage], selecting id: String, colors: CustomizeColors, over parent: NSWindow?) {
        let wasVisible = isVisible
        self.pages = pages
        self.colors = colors
        backgroundColor = colors.panel
        appearance = parent?.effectiveAppearance
        tabs.segmentCount = pages.count
        for (index, page) in pages.enumerated() {
            tabs.setLabel(page.title, forSegment: index)
            tabs.setImage(page.icon.image(size: 14), forSegment: index)
            tabs.setImageScaling(.scaleNone, forSegment: index)
        }
        tabs.selectedSegmentBezelColor = colors.accent
        select(pages.firstIndex { $0.id == id } ?? 0)
        if !wasVisible, let parent {
            let frame = parent.frame
            setFrameOrigin(NSPoint(x: frame.midX - self.frame.width / 2, y: frame.midY - self.frame.height / 2))
        }
        makeKeyAndOrderFront(nil)
    }

    /// The settings changed elsewhere (⌘K, another window): the open page
    /// shows them, keeping the tab.
    public func refresh(_ pages: [CustomizePage]) {
        guard isVisible, pages.map(\.id) == self.pages.map(\.id) else { return }
        self.pages = pages
        if list.entries != pages[selected].entries { list.show(pages[selected].entries, colors: colors) }
    }

    /// What the open page shows now.
    public var entries: [CustomizeEntry] { list.entries }

    override public func cancelOperation(_ sender: Any?) { close() }

    @objc private func tabChanged() { select(tabs.selectedSegment) }

    private func select(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        selected = index
        tabs.selectedSegment = index
        note.stringValue = pages[index].note
        note.textColor = colors.secondary
        list.show(pages[index].entries, colors: colors)
        contentView?.layoutSubtreeIfNeeded()
        if let size = contentView?.fittingSize {
            // Grows or shrinks from the top edge, so the tabs stay put.
            let top = frame.maxY
            setContentSize(size)
            setFrameOrigin(NSPoint(x: frame.minX, y: top - frame.height))
        }
    }

    private func makeContent() -> NSView {
        tabs.segmentStyle = .automatic
        tabs.trackingMode = .selectOne
        note.font = UILooks.font(12)
        let width = Self.width - 44
        note.preferredMaxLayoutWidth = width
        let stack = NSStackView(views: [tabs, note, list])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(16, after: tabs)
        // The top leaves room for the close button in the transparent title bar.
        stack.edgeInsets = NSEdgeInsets(top: 36, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [note, list] as [NSView] { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
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
