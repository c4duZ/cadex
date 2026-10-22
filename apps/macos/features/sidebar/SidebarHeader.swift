import AppKit
import Icons
import Menus
import Strings
import UILooks

/// A button of a page's header: the command it runs, its icon and its tip
/// (also its line in the "⋯" menu).
public struct SidebarAction {
    public let command: String
    public let icon: Icon
    public let tip: String
    public init(_ command: String, _ icon: Icon, _ tip: String) {
        self.command = command
        self.icon = icon
        self.tip = tip
    }
}

/// What the header's left side says: the folder in Files, the branch in
/// Git (its glyph, the click switches branch), the page's name elsewhere.
public struct SidebarTitle {
    public let text: String
    public let icon: Icon?
    public let command: String?
    public let tip: String?
    public init(_ text: String, icon: Icon? = nil, command: String? = nil, tip: String? = nil) {
        self.text = text
        self.icon = icon
        self.command = command
        self.tip = tip
    }
}

/// The one header row of every page, right under the icons: the name on
/// the left, the actions on the right in boxes of one size, at most
/// `maxShown`, the rest under "⋯". The same in every page: a title row
/// over each page's own header showed the folder's name twice with a big
/// gap, and hiding it on Files alone left the pages unlike (the owner,
/// 2026-10-22).
@MainActor
final class SidebarHeader: NSView {
    static var height: CGFloat { UILooks.pt(28) }
    static var buttonSize: NSSize { NSSize(width: UILooks.pt(24), height: UILooks.pt(24)) }
    static let maxShown = 3

    var run: ((String) -> Void)?
    var colors = SidebarColors() { didSet { restyle() } }
    let subtabs = SidebarSubtabs()
    let titleView = SidebarHeaderTitle()
    private(set) var buttons: [SidebarIconButton] = []
    private let more = SidebarIconButton(id: "…", icon: .dotsThree, tip: T("More actions", "Mais ações"), iconSide: 14)
    private var overflow: [SidebarAction] = []
    private var pressed: SidebarIconButton?
    /// Spins left of the buttons while the page's action runs (a push).
    private let progress = NSProgressIndicator()

    init() {
        super.init(frame: .zero)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        for view in [titleView, subtabs, progress, more] as [NSView] { addSubview(view) }
        titleView.onPress = { [weak self] command in self?.run?(command) }
        more.onPress = { [weak self] in self?.showMore() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarHeader is created in code") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// The page's title and actions: the first `maxShown` as buttons, the
    /// rest and `extra` under "⋯".
    func set(_ title: SidebarTitle, actions: [SidebarAction], extra: [SidebarAction]) {
        titleView.set(title)
        buttons.forEach { $0.removeFromSuperview() }
        buttons = actions.prefix(Self.maxShown).map { action in
            let button = SidebarIconButton(id: action.command, icon: action.icon, tip: action.tip, iconSide: 14)
            button.onPress = { [weak self] in self?.run?(action.command) }
            addSubview(button)
            return button
        }
        overflow = Array(actions.dropFirst(Self.maxShown)) + extra
        more.isHidden = overflow.isEmpty
        restyle()
        needsLayout = true
    }

    var busy = false {
        didSet {
            guard busy != oldValue else { return }
            busy ? progress.startAnimation(nil) : progress.stopAnimation(nil)
            needsLayout = true
        }
    }

    override func layout() {
        super.layout()
        let size = Self.buttonSize
        let y = (bounds.height - size.height) / 2
        var x = bounds.width
        for button in (more.isHidden ? [] : [more]) + buttons.reversed() {
            x -= size.width
            button.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
            x -= SidebarIconRow.spacing
        }
        if busy {
            let side = UILooks.pt(14)
            x -= side + UILooks.pt(4)
            progress.frame = NSRect(x: x, y: (bounds.height - side) / 2, width: side, height: side)
        }
        if !subtabs.isHidden {
            let fit = subtabs.fittingSize
            x -= fit.width + UILooks.pt(4)
            subtabs.frame = NSRect(x: x, y: (bounds.height - fit.height) / 2, width: fit.width, height: fit.height)
        }
        let height = UILooks.pt(22)
        let width = min(titleView.preferredWidth, max(x - UILooks.pt(6), 0))
        titleView.frame = NSRect(x: 0, y: (bounds.height - height) / 2, width: width, height: height)
    }

    private func restyle() {
        for button in buttons + [more] { button.colors = colors }
        subtabs.colors = colors
        titleView.colors = colors
    }

    private func showMore() {
        let entries = overflow.map { action in
            MenuEntry(action.tip, icon: action.icon) { [weak self] in self?.run?(action.command) }
        }
        PopupMenu.show(entries, below: more)
    }

    // The buttons leave clicks to their row, as the icons do.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        pressed = (buttons + [more]).first { !$0.isHidden && $0.frame.contains(point) }
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        let point = convert(event.locationInWindow, from: nil)
        if let pressed, pressed.frame.contains(point) { _ = pressed.accessibilityPerformPress() }
    }
}

/// The header's name: an optional glyph and the text, 12 pt semibold in the
/// quiet color, as typed. With a command it lights under the pointer and
/// the click runs it (the branch switches branch).
@MainActor
final class SidebarHeaderTitle: NSView {
    var onPress: ((String) -> Void)?
    var colors = SidebarColors() { didSet { restyle() } }
    let label = NSTextField(labelWithString: "")
    private let glyph = NSImageView()
    private var command: String?
    private var hovering = false { didSet { restyle() } }
    private static var inset: CGFloat { UILooks.pt(4) }
    private static var glyphSide: CGFloat { UILooks.pt(13) }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        label.font = UILooks.font(12, weight: .semibold)
        label.lineBreakMode = .byTruncatingMiddle
        for view in [glyph, label] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarHeaderTitle is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }

    func set(_ title: SidebarTitle) {
        label.stringValue = title.text
        glyph.image = title.icon?.fittedImage(size: Self.glyphSide)
        glyph.isHidden = title.icon == nil
        command = title.command
        toolTip = title.tip
        setAccessibilityLabel(title.text)
        if command == nil { hovering = false }
        restyle()
        needsLayout = true
    }

    /// The glyph, the text and the insets, before any cut.
    var preferredWidth: CGFloat {
        let glyphWidth = glyph.isHidden ? 0 : Self.glyphSide + UILooks.pt(4)
        // The cell's size: the intrinsic one (35.5 for "cadex") is short of
        // what it draws (39) and cut it to "c…ex" (2026-10-22).
        let text = label.cell?.cellSize.width ?? label.intrinsicContentSize.width
        return Self.inset * 2 + glyphWidth + ceil(text)
    }

    override func layout() {
        super.layout()
        var x = Self.inset
        if !glyph.isHidden {
            glyph.frame = NSRect(x: x, y: (bounds.height - Self.glyphSide) / 2, width: Self.glyphSide, height: Self.glyphSide)
            x += Self.glyphSide + UILooks.pt(4)
        }
        let height = label.intrinsicContentSize.height
        label.frame = NSRect(x: x, y: (bounds.height - height) / 2, width: max(bounds.width - x - Self.inset, 0), height: height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = command != nil }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard let command, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?(command)
    }

    private func restyle() {
        layer?.backgroundColor = hovering ? colors.fill.withAlphaComponent(0.5).cgColor : nil
        label.textColor = hovering ? colors.text : colors.secondary
        glyph.contentTintColor = label.textColor
    }
}
