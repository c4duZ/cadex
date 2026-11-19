import AppKit
import Menus
import Strings
import UILooks

/// The side column's Sessions page (plan 36 phase C; docs/adr/0038-rail-and-side-column.md): the
/// chosen project's conversations under "Today", "This week" and "Earlier", newest first, with a
/// search; the click opens the project page's Sessions on it, with the summary and Resume. The app
/// gives the rows (the history) only while the page shows.
@MainActor
public final class SessionsColumnView: NSView {
    typealias M = DesignTokens.Inspector.Memory
    /// A line clicked: its session's id.
    public var onPick: ((String) -> Void)?
    /// A line's right click: the app's menu for that session.
    public var menuFor: ((String) -> [MenuEntry])?
    private let search = NSTextField()
    private let list = NSStackView()
    private let scroll = NSScrollView()
    private var groups: [(title: String, items: [PageListItem])] = []
    private let empty = FrameField.text("", color: DesignTokens.Color.textTertiary)

    public init() {
        super.init(frame: .zero)
        search.placeholderString = T("Search sessions", "Buscar sessões")
        search.font = UILooks.font(DesignTokens.FontSize.panel)
        search.isBezeled = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.delegate = self
        let box = FrameBox()
        box.box(bg: M.Search.bg, border: M.Search.border, radius: M.Search.radius)
        box.hold(search, padding: M.Search.padding)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        let flipped = FlippedClip()
        flipped.drawsBackground = false
        scroll.contentView = flipped
        scroll.documentView = list
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        for view in [box, scroll, empty] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        list.translatesAutoresizingMaskIntoConstraints = false
        let pad = UILooks.pt(M.padding.left)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(M.padding.top) + pad),
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            box.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            scroll.topAnchor.constraint(equalTo: box.bottomAnchor, constant: UILooks.pt(M.learnedGap)),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            empty.centerXAnchor.constraint(equalTo: centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SessionsColumnView is created in code") }

    /// The sessions, grouped; redrawn with the search applied. `loading`: what to say while the
    /// history is still being read (an empty list then is not "no sessions").
    public func show(_ groups: [(title: String, items: [PageListItem])], loading: String? = nil) {
        self.groups = groups
        self.loading = loading
        redraw()
    }

    private var loading: String?

    private func redraw() {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        var shown = 0
        for group in groups {
            let items = group.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query) }
            guard !items.isEmpty else { continue }
            let label = FrameField.text(group.title.uppercased(), size: M.Label.fontSize, color: M.Label.color, weight: M.Label.weight)
            let holder = NSStackView(views: [label])
            holder.edgeInsets = NSEdgeInsets(top: UILooks.pt(M.gap) / 2, left: UILooks.pt(M.padding.left), bottom: UILooks.pt(M.learnedGap) / 2, right: 0)
            list.addArrangedSubview(holder)
            for item in items {
                let row = SessionRowView(item: item)
                row.onPress = { [weak self] in self?.onPick?(item.id) }
                row.rightMenu = { [weak self] in self?.menuFor?(item.id) ?? [] }
                list.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
                shown += 1
            }
        }
        empty.stringValue = groups.allSatisfy(\.items.isEmpty)
            ? loading ?? T("No sessions in this project yet", "Nenhuma sessão neste projeto ainda")
            : T("Nothing matches", "Nada encontrado")
        empty.isHidden = shown > 0
    }

    var rowTitles: [String] { list.arrangedSubviews.compactMap { ($0 as? SessionRowView)?.item.title } }
    func setQuery(_ text: String) { search.stringValue = text; redraw() }
}

extension SessionsColumnView: NSTextFieldDelegate {
    public func controlTextDidChange(_ notification: Notification) { redraw() }
}

/// A clip view that lays its document from the top.
private final class FlippedClip: NSClipView {
    override var isFlipped: Bool { true }
}

/// One conversation: the title, under it the account, the task and when; lit under the pointer.
@MainActor
final class SessionRowView: NSView {
    typealias M = DesignTokens.Inspector.Memory
    let item: PageListItem
    var onPress: (() -> Void)?
    /// The right click's entries, given by the app (each runs a command or the same thing as a click);
    /// cards and rows had none (UX audit, 2026-11-18).
    var rightMenu: (() -> [MenuEntry])?
    override func rightMouseDown(with event: NSEvent) {
        guard let entries = rightMenu?(), !entries.isEmpty else { return super.rightMouseDown(with: event) }
        PopupMenu.show(entries, at: convert(event.locationInWindow, from: nil), in: self)
    }
    private var hovering = false { didSet { layer?.backgroundColor = hovering ? DesignTokens.Color.bgSelected.cgColor : nil } }

    init(item: PageListItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(M.Card.radius)
        let title = FrameField.text(item.title, size: DesignTokens.FontSize.panel, color: DesignTokens.Color.textRow)
        let note = FrameField.text(item.note, size: M.Card.Meta.fontSize, color: M.Card.Meta.color)
        let stack = FrameField.column([title, note], gap: M.Card.gap)
        addSubview(stack)
        let pad = UILooks.pt(M.Card.padding.left)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(M.Card.padding.top)),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(M.Card.padding.bottom)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -pad),
        ])
        toolTip = item.title
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SessionRowView is created in code") }

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
