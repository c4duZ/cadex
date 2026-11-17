import AppKit
import Icons
import Menus
import UILooks

/// A row of the wiki's outline: a folder or a page. A class, because the
/// outline keeps its rows by identity.
final class MemoryNode: NSObject {
    let folder: MemoryFolder?
    let page: MemoryPage?
    let children: [MemoryNode]

    init(folder: MemoryFolder) {
        self.folder = folder
        page = nil
        children = folder.folders.map(MemoryNode.init(folder:)) + folder.pages.map(MemoryNode.init(page:))
    }

    init(page: MemoryPage) {
        folder = nil
        self.page = page
        children = []
    }

    /// Kept open across refreshes by the folder's path.
    var key: String { folder?.relative ?? page?.relative ?? "" }
}

/// The wiki as a tree (folders, then pages newest first): only the rows
/// on screen are drawn, as a wiki of sessions grows to hundreds of pages.
/// A click on a page opens it; the right click lists what to do with it.
@MainActor
final class MemoryWikiOutline: NSOutlineView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// The account of a session, by id, when the History knows it.
    var accountOf: (String) -> String? = { _ in nil }
    var onOpen: ((MemoryPage) -> Void)?
    var menuFor: ((MemoryPage) -> [MenuEntry])?
    private var roots: [MemoryNode] = []
    private var expanded: Set<String> = []

    init() {
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: .init("main"))
        addTableColumn(column)
        outlineTableColumn = column
        headerView = nil
        backgroundColor = .clear
        style = .plain
        indentationPerLevel = UILooks.pt(DesignTokens.Inspector.Tree.indent)
        dataSource = self
        delegate = self
        target = self
        action = #selector(clicked)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The folders' caret dim, as in Files (components.inspector.tree.chevron).
    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        let view = super.makeView(withIdentifier: identifier, owner: owner)
        if identifier == NSOutlineView.disclosureButtonIdentifier, let button = view as? NSButton {
            button.image = Self.carets.closed
            button.alternateImage = Self.carets.open
            button.contentTintColor = DesignTokens.Inspector.Tree.chevronColor
        }
        return view
    }

    private static let carets = (closed: Icon.caretRight.image(size: UILooks.pt(DesignTokens.Inspector.Tree.chevron)),
                                 open: Icon.caretDown.image(size: UILooks.pt(DesignTokens.Inspector.Tree.chevron)))

    /// The wiki again, keeping open what was open.
    func show(_ tree: MemoryFolder?) {
        roots = tree.map { MemoryNode(folder: $0).children } ?? []
        reloadData()
        for node in roots { restore(node) }
    }

    private func restore(_ node: MemoryNode) {
        guard node.folder != nil, expanded.contains(node.key) else { return }
        expandItem(node)
        for child in node.children { restore(child) }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? MemoryNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? MemoryNode)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? MemoryNode)?.folder != nil }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? MemoryNode { expanded.insert(node.key) }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let node = notification.userInfo?["NSObject"] as? MemoryNode { expanded.remove(node.key) }
    }

    typealias M = DesignTokens.Inspector.Memory

    /// A folder is a wiki row (components.inspector.memory.wikiRow); a page, a title over its origin.
    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        (item as? MemoryNode)?.page == nil ? UILooks.rowHeight(M.WikiRow.height) : Self.pageHeight
    }

    /// Worked out once: the title and the origin lines, as the cards (the zoom is set at launch).
    static let pageHeight: CGFloat = {
        let lines = NSLayoutManager().defaultLineHeight(for: UILooks.font(DesignTokens.FontSize.body))
            + NSLayoutManager().defaultLineHeight(for: UILooks.font(M.Card.Meta.fontSize))
        return ceil(lines) + UILooks.pt(M.Card.padding.top)
    }()

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? MemoryNode else { return nil }
        if let folder = node.folder { return folderRow(folder) }
        guard let page = node.page else { return nil }
        let account = page.sessionID.flatMap(accountOf)
        let title = MemoryText.label(page.title, size: DesignTokens.FontSize.body, color: M.WikiRow.color)
        let detail = MemoryText.label(MemoryStatusText.origin(page, account: account), size: M.Card.Meta.fontSize, color: M.Card.Meta.color)
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        let view = cell(stack, top: 2)
        view.toolTip = [page.relative, page.summary].compactMap { $0 }.joined(separator: "\n")
        return view
    }

    /// "◆ Decisions  48": the kind's mark, the name, the count on the right (the mockup's WIKI).
    private func folderRow(_ folder: MemoryFolder) -> NSView {
        let mark = MemoryText.label(Self.mark(of: folder.name), size: DesignTokens.FontSize.body, color: M.Label.color)
        mark.alignment = .center
        // One width for every mark: ◆ and ! are not as wide, and the names went out of line.
        mark.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Inspector.Tree.icon)).isActive = true
        let shown = folder.name.hasPrefix("_") ? String(folder.name.dropFirst()) : folder.name
        let name = MemoryText.label(shown.capitalized, size: DesignTokens.FontSize.body, color: M.WikiRow.color)
        name.setContentHuggingPriority(.init(1), for: .horizontal)
        let count = MemoryText.label("\(folder.count)", size: M.Label.fontSize, color: M.Label.color)
        count.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = NSStackView(views: [mark, name, count])
        row.spacing = UILooks.pt(M.WikiRow.gap)
        row.distribution = .fill
        let cell = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            row.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    /// The marks the mockup gives the wiki's kinds; another folder gets the plain one.
    static func mark(of folder: String) -> String {
        switch folder.lowercased() {
        case "decisions": "◆"
        case "gotchas": "!"
        case "concepts": "◇"
        case "sessions": "≡"
        default: "▸"
        }
    }

    private func cell(_ content: NSView, top: CGFloat) -> NSView {
        let cell = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            content.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            content.topAnchor.constraint(equalTo: cell.topAnchor, constant: top),
        ])
        return cell
    }

    private func page(at row: Int) -> MemoryPage? {
        guard row >= 0 else { return nil }
        return (item(atRow: row) as? MemoryNode)?.page
    }

    @objc private func clicked() {
        let row = clickedRow
        if let page = page(at: row) { onOpen?(page); return }
        guard row >= 0, let node = item(atRow: row) as? MemoryNode, node.folder != nil else { return }
        if isItemExpanded(node) { collapseItem(node) } else { expandItem(node) }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard let page = page(at: row), let entries = menuFor?(page) else { return }
        selectRowIndexes([row], byExtendingSelection: false)
        PopupMenu.show(entries, at: point, in: self)
    }
}

@MainActor
enum MemoryText {
    static func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, wraps: Bool = false) -> NSTextField {
        let field = wraps ? NSTextField(wrappingLabelWithString: string) : NSTextField(labelWithString: string)
        field.font = UILooks.font(size, weight: weight)
        field.textColor = color
        if !wraps { field.lineBreakMode = .byTruncatingTail }
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }
}
