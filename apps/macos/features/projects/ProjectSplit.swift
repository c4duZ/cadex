import AppKit
import Icons
import Strings
import UILooks

/// A section's list and, beside it, the chosen line's detail (the proposal's `.split`, `.list` and
/// `.det`; plan 34 D and E). Side by side, the list a little narrower; the detail is the app's
/// `PageDetail`, rendered.
@MainActor
enum ProjectSplit {
    static func view(items: [PageListItem], chosen: String?, search: ((String) -> Void)?, query: String,
                     detail: PageDetail?, empty: String, choose: @escaping (String) -> Void) -> NSView {
        let left = list(items, chosen: chosen, search: search, query: query, empty: empty, choose: choose)
        let right = detail.map(card) ?? NSView()
        let pair = NSStackView(views: [left, right])
        pair.alignment = .top
        pair.distribution = .fill
        right.setContentHuggingPriority(.required, for: .vertical)
        pair.spacing = UILooks.pt(16)
        right.widthAnchor.constraint(equalTo: left.widthAnchor, multiplier: 1.05).isActive = true
        return pair
    }

    // MARK: The list

    private static func list(_ items: [PageListItem], chosen: String?, search: ((String) -> Void)?, query: String, empty: String,
                             choose: @escaping (String) -> Void) -> NSView {
        var rows: [NSView] = []
        if let search { rows.append(SearchField(query: query, changed: search)) }
        var group: String?
        for item in items {
            if let title = item.group, title != group {
                group = title
                rows.append(groupLabel(title))
            }
            rows.append(row(item, on: item.id == chosen, choose: choose))
        }
        if items.isEmpty { rows.append(padded(pageLabel(empty, size: DesignTokens.FontSize.panel, color: DesignTokens.Color.textTertiary))) }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.wantsLayer = true
        stack.layer?.backgroundColor = DesignTokens.Color.bgSidebar.cgColor
        stack.layer?.borderColor = DesignTokens.Color.lineDefault.cgColor
        stack.layer?.borderWidth = DesignTokens.Stroke.hairline
        stack.layer?.cornerRadius = UILooks.pt(DesignTokens.Radius.pane)
        stack.layer?.masksToBounds = true
        for view in rows { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }

    private static func groupLabel(_ title: String) -> NSView {
        let label = pageLabel(title.uppercased(), size: DesignTokens.FontSize.caption, color: DesignTokens.Color.textTertiary, weight: .bold, tracking: 0.06)
        let box = PageBox()
        box.hold(label, padding: NSEdgeInsets(top: 10, left: 12, bottom: 4, right: 12))
        return box
    }

    private static func row(_ item: PageListItem, on: Bool, choose: @escaping (String) -> Void) -> NSView {
        let box = ListRow(chosen: on)
        box.onPress = { choose(item.id) }
        var lines: [NSView] = [pageLabel(item.title, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary, weight: .semibold)]
        if !item.note.isEmpty {
            let note = pageLabel(item.note, size: DesignTokens.FontSize.small, color: DesignTokens.Color.textTertiary)
            lines.append(item.noteLogo ? logoLine(note) : note)
        }
        var views: [NSView] = []
        if let tile = item.tile { views.append(kindTile(tile, item.tint ?? DesignTokens.Color.textSecondary)) }
        let words = vertical(lines, gap: 2)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        views.append(words)
        let line = NSStackView(views: views)
        line.spacing = UILooks.pt(10)
        line.alignment = .centerY
        box.hold(line, padding: NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        box.setAccessibilityElement(true)
        box.setAccessibilityRole(.button)
        box.setAccessibilityLabel(item.title)
        return box
    }

    // MARK: The detail

    private static func card(_ detail: PageDetail) -> NSView {
        var views: [NSView] = []
        if let chip = detail.chip { views.append(chipView(chip.text, chip.tint)) }
        views.append(wrapped(detail.title, size: 16, color: DesignTokens.Color.textPrimary, weight: .bold))
        if !detail.meta.isEmpty {
            let meta = pageLabel(detail.meta, size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textTertiary)
            views.append(detail.metaLogo ? logoLine(meta) : meta)
        }
        // The proposal's order: the summary, the tags, then the rest; a long page is cut, whole in
        // "View the Page" (a real session page put the buttons out of sight, 2026-11-18).
        var blocks = Array(detail.blocks.prefix(Self.shownBlocks))
        var tagsShown = detail.tags.isEmpty
        if case .paragraph(let first)? = blocks.first {
            views.append(wrapped(first, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textRow))
            blocks.removeFirst()
            if !detail.tags.isEmpty { views.append(tagRow(detail.tags)); tagsShown = true }
        }
        for block in blocks {
            switch block {
            case .heading(let text): views.append(pageLabel(text.uppercased(), size: DesignTokens.FontSize.caption, color: DesignTokens.Color.textTertiary, weight: .bold, tracking: 0.06))
            case .paragraph(let text): views.append(wrapped(text, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textRow))
            case .item(let text): views.append(wrapped("•  " + text, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textRow))
            }
        }
        if !tagsShown { views.append(tagRow(detail.tags)) }
        if detail.blocks.count > Self.shownBlocks {
            views.append(pageLabel(T("…the rest in View the Page", "…o resto em Ver a página"), size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textTertiary))
        }
        if !detail.related.isEmpty {
            views.append(pageLabel(detail.relatedTitle.uppercased(), size: DesignTokens.FontSize.caption, color: DesignTokens.Color.textTertiary, weight: .bold, tracking: 0.06))
            for related in detail.related {
                let line = NSStackView(views: [kindTile(related.tile, related.tint), pageLabel(related.text, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textRow)])
                line.spacing = UILooks.pt(8)
                views.append(line)
            }
        }
        if !detail.buttons.isEmpty {
            let buttons = NSStackView(views: detail.buttons.map { button -> NSView in
                let made = DesignButton.make(button.title, button.primary ? .primary : .secondary, action: button.action)
                // Delete in the failed state's red, as the proposal draws it.
                if button.danger {
                    made.attributedTitle = NSAttributedString(string: button.title, attributes: [
                        .font: made.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) ?? UILooks.font(DesignTokens.FontSize.body),
                        .foregroundColor: DesignTokens.Color.stateFailed])
                }
                return made
            })
            buttons.spacing = UILooks.pt(8)
            views.append(buttons)
        }
        let column = vertical(views, gap: 8)
        if views.count > 1, !detail.buttons.isEmpty { column.setCustomSpacing(UILooks.pt(16), after: views[views.count - 2]) }
        for view in views where view is NSTextField && (view as? NSTextField)?.maximumNumberOfLines == 0 {
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        let box = PageBox()
        box.box(bg: DesignTokens.Color.bgCard, border: DesignTokens.Color.lineDefault, radius: DesignTokens.Radius.pane)
        box.hold(column, padding: NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18))
        // As tall as what it says (it stretched down the whole page beside a long list).
        box.setContentHuggingPriority(.required, for: .vertical)
        column.setHuggingPriority(.required, for: .vertical)
        return box
    }

    // MARK: Pieces

    /// The body's lines shown beside the list; the whole page is the detail's own button.
    static let shownBlocks = 10

    private static func tagRow(_ tags: [String]) -> NSView {
        let row = NSStackView(views: tags.prefix(6).map { tag in chipView(tag, DesignTokens.Color.textSecondary, filled: true) })
        row.spacing = UILooks.pt(6)
        return row
    }

    static func kindTile(_ glyph: Icon, _ tint: NSColor) -> NSView {
        let tile = NSImageView(image: glyph.image(size: UILooks.pt(12)))
        tile.contentTintColor = tint
        tile.wantsLayer = true
        tile.layer?.backgroundColor = tint.withAlphaComponent(0.14).cgColor
        tile.layer?.cornerRadius = UILooks.pt(DesignTokens.Radius.tag)
        tile.widthAnchor.constraint(equalToConstant: UILooks.pt(20)).isActive = true
        tile.heightAnchor.constraint(equalToConstant: UILooks.pt(20)).isActive = true
        return tile
    }

    static func logoLine(_ text: NSView) -> NSView {
        let logo = NSImageView(image: ProviderLogo.claude.image(size: UILooks.pt(10)))
        logo.contentTintColor = ProviderLogo.claude.brandColor
        let line = NSStackView(views: [logo, text])
        line.spacing = UILooks.pt(4)
        return line
    }

    private static func chipView(_ text: String, _ tint: NSColor, filled: Bool = false) -> NSView {
        let label = pageLabel(filled ? text : text.uppercased(), size: filled ? DesignTokens.FontSize.caption : DesignTokens.FontSize.chip, color: tint,
                              weight: filled ? .regular : .bold)
        let box = PageBox()
        box.box(bg: filled ? DesignTokens.Color.bgSegment : tint.withAlphaComponent(0.14), border: .clear, radius: DesignTokens.Radius.tag)
        box.hold(label, padding: NSEdgeInsets(top: 2, left: 7, bottom: 2, right: 7))
        return box
    }

    private static func wrapped(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = UILooks.font(size, weight: weight)
        field.textColor = color
        field.maximumNumberOfLines = 0
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    private static func padded(_ view: NSView) -> NSView {
        let box = PageBox()
        box.hold(view, padding: NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
        return box
    }
}

/// A line of the list: the chosen one blue-gray with a blue bar on its left (the proposal's `.li.on`),
/// the others lit under the pointer; a line under each.
@MainActor
final class ListRow: PageBox {
    private let chosen: Bool
    private var hovering = false { didSet { restyle() } }

    init(chosen: Bool) {
        self.chosen = chosen
        super.init(frame: .zero)
        wantsLayer = true
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = DesignTokens.Color.lineDefault.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor), line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor), line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
        ])
        if chosen {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = DesignTokens.Color.stateWorking.cgColor
            bar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: leadingAnchor), bar.topAnchor.constraint(equalTo: topAnchor),
                bar.bottomAnchor.constraint(equalTo: bottomAnchor), bar.widthAnchor.constraint(equalToConstant: 2),
            ])
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ListRow is created in code") }

    private func restyle() {
        layer?.backgroundColor = chosen ? DesignTokens.Color.bgSidebar.blended(withFraction: 0.12, of: DesignTokens.Color.stateWorking)?.cgColor
            : hovering ? DesignTokens.Color.bgButton.cgColor : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}

/// The memory's search inside the list (the proposal's `.search`): typing filters the lines.
@MainActor
final class SearchField: PageBox, NSTextFieldDelegate {
    private let field = NSTextField()
    private let changed: (String) -> Void

    init(query: String, changed: @escaping (String) -> Void) {
        self.changed = changed
        super.init(frame: .zero)
        let icon = NSImageView(image: Icon.magnifyingGlass.image(size: UILooks.pt(13)))
        icon.contentTintColor = DesignTokens.Color.textTertiary
        field.stringValue = query
        field.placeholderString = T("Search memory", "Buscar na memória")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = UILooks.font(DesignTokens.FontSize.body)
        field.delegate = self
        let inner = NSStackView(views: [icon, field])
        inner.spacing = UILooks.pt(8)
        let frame = PageBox()
        frame.box(bg: DesignTokens.Color.bgCard, border: DesignTokens.Color.lineControl, radius: DesignTokens.Radius.row)
        frame.hold(inner, padding: NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10))
        hold(frame, padding: NSEdgeInsets(top: 10, left: 10, bottom: 6, right: 10))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SearchField is created in code") }

    func controlTextDidChange(_ obj: Notification) { changed(field.stringValue) }

    /// The list is drawn again at each key: the new field takes the keyboard back, the cursor at the end.
    func takeFocus() {
        guard let window else { return }
        window.makeFirstResponder(field)
        field.currentEditor()?.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
    }
}
