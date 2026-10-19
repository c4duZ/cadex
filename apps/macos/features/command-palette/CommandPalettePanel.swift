import AppKit

/// The palette window: a search field and the list under it, at the top of
/// the app window. Made once and reused, so ⌘K shows it in the same frame.
final class CommandPalettePanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    static let width: CGFloat = 560
    static let rowHeight: CGFloat = 30
    static let visibleRows = 10

    var onQuery: ((String) -> Void)?
    var onChoose: ((Int) -> Void)?
    var onDismiss: (() -> Void)?

    private let field = NSTextField()
    private let table = NSTableView()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "Nenhum comando encontrado")
    private var items: [PaletteItem] = []

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 60),
                   styleMask: [.borderless], backing: .buffered, defer: true)
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        buildContent()
    }

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        // Clicking outside closes without running (docs/spec/command-palette.md).
        if isVisible { onDismiss?() }
    }

    func show(over parent: NSWindow) {
        field.stringValue = ""
        let frame = parent.frame
        let top = frame.maxY - 60
        setFrameTopLeftPoint(NSPoint(x: frame.midX - Self.width / 2, y: top))
        makeKeyAndOrderFront(nil)
        makeFirstResponder(field)
        onQuery?("")
    }

    func show(items newItems: [PaletteItem]) {
        items = newItems
        table.reloadData()
        emptyLabel.isHidden = !items.isEmpty
        if !items.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        table.scrollRowToVisible(0)
        resizeToFit()
    }

    // MARK: Layout

    private func buildContent() {
        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        contentView = background

        field.placeholderString = "Digite um comando"
        field.font = .systemFont(ofSize: 17)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self

        table.addTableColumn(NSTableColumn(identifier: .init("item")))
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        // The default (inset) style pads the list, which pushed the last row
        // out of the panel sized for rows × rowHeight.
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        for view in [field, scroll, emptyLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            field.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -6),
            emptyLabel.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 12),
            emptyLabel.leadingAnchor.constraint(equalTo: field.leadingAnchor),
        ])
    }

    private func resizeToFit() {
        let rows = items.isEmpty ? 1 : min(items.count, Self.visibleRows)
        // Margins around the field and the list, as laid out in buildContent.
        let height = 14 + field.intrinsicContentSize.height + 10 + CGFloat(rows) * Self.rowHeight + 6
        var frame = self.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        setFrame(frame, display: true)
    }

    // MARK: Keys in the field

    func controlTextDidChange(_ obj: Notification) {
        onQuery?(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): moveSelection(1)
        case #selector(NSResponder.moveUp(_:)): moveSelection(-1)
        case #selector(NSResponder.insertNewline(_:)): chooseSelected()
        case #selector(NSResponder.cancelOperation(_:)): onDismiss?()
        default: return false
        }
        return true
    }

    private func moveSelection(_ step: Int) {
        guard !items.isEmpty else { return }
        let row = min(max(table.selectedRow + step, 0), items.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    private func chooseSelected() {
        let row = table.selectedRow
        guard row >= 0, row < items.count, items[row].unavailableReason == nil else { return }
        onChoose?(row)
    }

    @objc private func rowClicked() {
        chooseSelected()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = tableView.makeView(withIdentifier: PaletteRowView.identifier, owner: nil) as? PaletteRowView ?? PaletteRowView()
        view.show(items[row])
        return view
    }
}

/// A palette row: the title with the matched letters in bold, and the
/// shortcut, or the reason a command is unavailable, on the right.
final class PaletteRowView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("palette-row")
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        for view in [title, detail] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.lineBreakMode = .byTruncatingTail
            addSubview(view)
        }
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 12),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaletteRowView is created in code") }

    func show(_ item: PaletteItem) {
        let available = item.unavailableReason == nil
        let color: NSColor = available ? .labelColor : .tertiaryLabelColor
        let text = NSMutableAttributedString(string: item.title, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: color,
        ])
        for range in item.bold {
            text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(range, in: item.title))
        }
        title.attributedStringValue = text
        detail.stringValue = item.unavailableReason ?? item.shortcut ?? ""
        detail.font = available ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
    }
}
