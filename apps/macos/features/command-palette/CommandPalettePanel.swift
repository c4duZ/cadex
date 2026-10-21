import AppKit
import UILooks
import Icons

/// The palette window: the field with the list's icon, the rows in
/// sections under it and the footer with the keys, at the top of the app
/// window, in the theme's colors (docs/spec/command-palette.md). Made once
/// and reused, so ⌘K shows it in the same frame.
final class CommandPalettePanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static var width: CGFloat { UILooks.pt(640) }
    static var rowHeight: CGFloat { UILooks.rowHeight(36) }
    static var headerHeight: CGFloat { UILooks.rowHeight(30) }
    static var listMaxHeight: CGFloat { UILooks.pt(400) }
    private static var fieldHeight: CGFloat { UILooks.rowHeight(54) }
    private static var footerHeight: CGFloat { UILooks.rowHeight(36) }

    var onQuery: ((String) -> Void)?
    var onChoose: ((Int, PaletteChoice) -> Void)?
    var onDismiss: (() -> Void)?
    var style = PaletteStyle.system { didSet { applyStyle() } }

    private let background = NSView()
    private let fieldIcon = NSImageView()
    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    /// A short note from the source on the right of the field ("Indexando…").
    private let statusLabel = NSTextField(labelWithString: "")
    private let topLine = NSView()
    private let bottomLine = NSView()
    private let footer = PaletteFooterView()
    private var items: [PaletteItem] = []
    private var rows: [PaletteRows.Row] = []

    var query: String { field.stringValue }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 120),
                   styleMask: [.borderless], backing: .buffered, defer: true)
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        buildContent()
        applyStyle()
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        // Clicking outside closes without running (docs/spec/command-palette.md).
        if isVisible { onDismiss?() }
    }

    func show(over parent: NSWindow) {
        let frame = parent.frame
        setFrameTopLeftPoint(NSPoint(x: frame.midX - Self.width / 2, y: frame.maxY - 56))
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
    }

    /// A new source: empty field, its placeholder and icon, and its first list.
    func prepare(placeholder: String, emptyText: String, icon: Icon) {
        field.stringValue = ""
        setLook(placeholder: placeholder, emptyText: emptyText, icon: icon)
        statusLabel.stringValue = ""
        onQuery?("")
    }

    /// The list on screen changed without a new field (a prefix typed).
    func setLook(placeholder: String, emptyText: String, icon: Icon) {
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: UILooks.font(18), .foregroundColor: style.secondaryText.withAlphaComponent(0.7),
        ])
        emptyLabel.stringValue = emptyText
        fieldIcon.image = icon.image(size: 18)
    }

    func show(items newItems: [PaletteItem], status: String?, hints: [PaletteHint]) {
        statusLabel.stringValue = status ?? ""
        items = newItems
        rows = PaletteRows.rows(for: newItems)
        table.reloadData()
        emptyLabel.isHidden = !items.isEmpty
        footer.show(hints, style: style)
        if let first = rows.firstIndex(where: { if case .item = $0 { true } else { false } }) {
            table.selectRowIndexes([first], byExtendingSelection: false)
        }
        table.scrollRowToVisible(0)
        resizeToFit()
    }

    // MARK: Layout

    private func buildContent() {
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        contentView = background

        field.font = UILooks.font(18)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self

        table.addTableColumn(NSTableColumn(identifier: .init("item")))
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        // The default (inset) style pads the list, which pushed the last row
        // out of the panel sized for its rows.
        table.style = .plain
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        emptyLabel.isHidden = true
        emptyLabel.font = UILooks.font(13)
        statusLabel.font = UILooks.font(12)
        statusLabel.alignment = .right
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        for line in [topLine, bottomLine] { line.wantsLayer = true }

        for view in [fieldIcon, field, statusLabel, topLine, scroll, emptyLabel, bottomLine, footer] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            fieldIcon.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            fieldIcon.centerYAnchor.constraint(equalTo: background.topAnchor, constant: Self.fieldHeight / 2),
            fieldIcon.widthAnchor.constraint(equalToConstant: 18),
            fieldIcon.heightAnchor.constraint(equalToConstant: 18),
            field.leadingAnchor.constraint(equalTo: fieldIcon.trailingAnchor, constant: 12),
            field.centerYAnchor.constraint(equalTo: fieldIcon.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            statusLabel.centerYAnchor.constraint(equalTo: fieldIcon.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: statusLabel.leadingAnchor, constant: -8),
            topLine.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.fieldHeight),
            topLine.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            topLine.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: topLine.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: bottomLine.topAnchor, constant: -6),
            emptyLabel.topAnchor.constraint(equalTo: topLine.bottomAnchor, constant: 14),
            emptyLabel.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            bottomLine.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            bottomLine.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            bottomLine.heightAnchor.constraint(equalToConstant: 1),
            bottomLine.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.footerHeight),
            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            footer.centerYAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.footerHeight / 2),
        ])
    }

    private func applyStyle() {
        background.layer?.backgroundColor = style.background.cgColor
        background.layer?.borderColor = style.border.cgColor
        for line in [topLine, bottomLine] { line.layer?.backgroundColor = style.border.cgColor }
        field.textColor = style.text
        fieldIcon.contentTintColor = style.accent
        statusLabel.textColor = style.secondaryText
        emptyLabel.textColor = style.secondaryText
        appearance = NSAppearance(named: style.background.isDark ? .darkAqua : .aqua)
        table.reloadData()
    }

    private func resizeToFit() {
        let list = rows.isEmpty ? Self.rowHeight : min(rows.reduce(0) { $0 + height(of: $1) }, Self.listMaxHeight)
        let total = Self.fieldHeight + 1 + 6 + list + 6 + 1 + Self.footerHeight
        var frame = self.frame
        frame.origin.y += frame.height - total
        frame.size.height = total
        setFrame(frame, display: true)
    }

    private func height(of row: PaletteRows.Row) -> CGFloat {
        if case .header = row { return Self.headerHeight }
        return Self.rowHeight
    }

    // MARK: Keys in the field

    func controlTextDidChange(_ obj: Notification) {
        onQuery?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)): chooseSelected(Self.choice(NSApp.currentEvent?.modifierFlags ?? []))
        // ⌥↩ in a text field (docs/spec/command-palette.md: open beside).
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)): chooseSelected(.option)
        case #selector(NSResponder.cancelOperation(_:)): onDismiss?()
        default: return false
        }
        return true
    }

    /// ⌘↩ never reaches the field: the menus would take it first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command) {
            chooseSelected(.command)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static func choice(_ flags: NSEvent.ModifierFlags) -> PaletteChoice {
        if flags.contains(.command) { return .command }
        if flags.contains(.option) { return .option }
        return .primary
    }

    private func moveSelection(_ step: Int) {
        guard let next = PaletteRows.next(from: table.selectedRow, by: step, in: rows) else { return }
        table.selectRowIndexes([next], byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    private func chooseSelected(_ choice: PaletteChoice) {
        let row = table.selectedRow
        guard row >= 0, row < rows.count, case .item(let index) = rows[row],
              items[index].unavailableReason == nil else { return }
        onChoose?(index, choice)
    }

    @objc private func rowClicked() {
        chooseSelected(.primary)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { height(of: rows[row]) }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .item = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = PaletteRowBackground()
        view.fill = style.selection
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title):
            let view = PaletteHeaderView()
            view.show(title, style: style)
            return view
        case .item(let index):
            let view = tableView.makeView(withIdentifier: PaletteRowView.identifier, owner: nil) as? PaletteRowView ?? PaletteRowView()
            view.show(items[index], style: style, selected: tableView.selectedRow == row)
            return view
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selected = table.selectedRow
        table.enumerateAvailableRowViews { rowView, row in
            (rowView.view(atColumn: 0) as? PaletteRowView)?.setSelected(row == selected)
        }
    }
}

private extension NSColor {
    /// Whether text on this fill should be light.
    var isDark: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return true }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent < 0.5
    }
}
