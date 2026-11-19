import AppKit
import Strings
import UILooks

/// A screen of a project (plan 40 D): the page's scroll, the trail on top and a column of parts as
/// wide as the page (components.memoryPanel.page). Each screen fills it; a click that goes
/// somewhere calls `go` (the app runs memory.show-panel with the place, ADR 0005).
@MainActor
class PanelScreen: NSView {
    let go: (PanelPlace) -> Void
    let scroll = NSScrollView()
    let pageBox = PanelFlipped()
    let column = PanelText.column([], gap: MP.Page.gap)

    init(go: @escaping (PanelPlace) -> Void) {
        self.go = go
        super.init(frame: .zero)
        scroll.documentView = pageBox
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        pageBox.translatesAutoresizingMaskIntoConstraints = false
        pageBox.hold(column, padding: MP.Page.padding)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageBox.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            pageBox.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            pageBox.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelScreen is created in code") }

    /// The parts, top to bottom, each as wide as the column.
    func fill(_ views: [NSView]) {
        column.setViews(views, in: .top)
        for view in views { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
    }

    /// The trail, with the screen's links at its right ("← Sessões de claude-code", "Recuperações").
    func trail(_ crumbs: [PanelCrumb], links: [NSView] = []) -> NSView {
        var views: [NSView] = []
        for (index, crumb) in crumbs.enumerated() {
            if index > 0 { views.append(PanelText.line("›", size: MP.Breadcrumb.fontSize, color: MP.Breadcrumb.separator)) }
            let last = index == crumbs.count - 1
            let label = PanelText.line(crumb.title, size: MP.Breadcrumb.fontSize, color: last ? MP.Breadcrumb.current : MP.Breadcrumb.color)
            // A page's path is long: the trail cuts it at its end (the board's "decisions/cadex-decisoes…"),
            // never the project before it.
            if crumb.place != nil || !last {
                label.widthAnchor.constraint(lessThanOrEqualToConstant: UILooks.pt(MP.Aside.width + MP.Page.padding.left)).isActive = true
            }
            guard let place = crumb.place else { views.append(label); continue }
            let press = PanelPress()
            press.hold(label, padding: NSEdgeInsets())
            press.onPress = { [weak self] in self?.go(place) }
            press.setAccessibilityElement(true)
            press.setAccessibilityRole(.link)
            press.setAccessibilityLabel(crumb.title)
            views.append(press)
        }
        let row = PanelText.row(views + [PanelText.spring()] + links, gap: MP.Chip.gap)
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        row.setAccessibilityLabel(T("Breadcrumb", "Trilha"))
        return row
    }

    /// The title, and the screen's buttons at its right.
    func heading(_ title: String, buttons: [NSView] = []) -> NSView {
        let label = PanelText.line(title, size: MP.Head.Title.fontSize, color: DesignTokens.Color.textPrimary, weight: MP.Head.Title.weight)
        label.setAccessibilityRole(.staticText)
        label.setAccessibilityLabel(title)
        return PanelText.row([label, PanelText.spring()] + buttons, gap: MP.Head.gap)
    }

    /// "PÁGINAS", "SESSÕES": the small label over a part (components.memoryPanel.label).
    static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.attributedStringValue = NSAttributedString(string: text.uppercased(), attributes: [
            .font: UILooks.font(MP.Label.fontSize, weight: MP.Label.weight), .foregroundColor: MP.Label.color,
            .kern: UILooks.pt(MP.Label.fontSize) * MP.Label.tracking,
        ])
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    /// A box of the page (components.memoryPanel.box) around `content`.
    static func box(_ content: NSView, padding: NSEdgeInsets = MP.Box.padding) -> FrameBox {
        let box = FrameBox()
        box.box(bg: MP.Box.bg, border: MP.Box.border, radius: MP.Box.radius)
        box.hold(content, padding: padding)
        return box
    }

    /// A line of the meta's color, wrapping.
    static func note(_ text: String, color: NSColor = MP.Head.meta) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = UILooks.font(DesignTokens.FontSize.meta)
        label.textColor = color
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// A thin rule as wide as its column.
    static func rule(_ color: NSColor = MP.Box.Row.divider) -> NSView {
        let rule = NSView()
        rule.wantsLayer = true
        rule.layer?.backgroundColor = color.cgColor
        rule.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline).isActive = true
        return rule
    }

    // MARK: Back and forward within the page (⌘[ and ⌘], as a browser; the panes' own ⌘[ wins
    // only with a split, where the shortcut's command is available).

    var onBack: (() -> Void)?
    var onForward: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let window, let responder = window.firstResponder as? NSView, responder.isDescendant(of: self) else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "[": onBack?()
        case "]": onForward?()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override var acceptsFirstResponder: Bool { true }
}

/// The project's tabs in the segmented selector (components.memoryPanel.tabs).
@MainActor
final class PanelTabsView: FrameBox {
    typealias TB = MP.Tabs
    private var buttons: [PanelPress] = []

    init(_ titles: [String], chosen: Int, pick: @escaping (Int) -> Void) {
        super.init(frame: .zero)
        box(bg: TB.bg, border: TB.border, radius: TB.radius)
        for (index, title) in titles.enumerated() {
            let on = index == chosen
            let label = PanelText.line(title, size: TB.Tab.fontSize, color: on ? TB.On.color : TB.Tab.color, weight: on ? TB.On.weight : TB.Tab.weight)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            let button = PanelPress()
            button.box(bg: on ? TB.On.bg : nil, border: nil, radius: TB.Tab.radius)
            button.hold(PanelText.row([label], gap: 0), padding: TB.Tab.padding)
            button.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(TB.Tab.height)).isActive = true
            button.onPress = { pick(index) }
            button.setAccessibilityElement(true)
            button.setAccessibilityRole(.radioButton)
            button.setAccessibilityLabel(title)
            button.setAccessibilityValue(on ? 1 : 0)
            buttons.append(button)
        }
        let p = TB.padding
        hold(PanelText.row(buttons, gap: TB.gap), padding: NSEdgeInsets(top: p, left: p, bottom: p, right: p))
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelTabsView is created in code") }

    /// For tests.
    func press(_ index: Int) { buttons[index].onPress?() }
}
