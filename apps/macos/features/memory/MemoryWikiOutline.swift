import AppKit
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
    var colors = MemoryColors() { didSet { reloadData() } }
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
        indentationPerLevel = 12
        dataSource = self
        delegate = self
        target = self
        action = #selector(clicked)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

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

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        (item as? MemoryNode)?.page == nil ? UILooks.pt(22) : UILooks.pt(36)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? MemoryNode else { return nil }
        if let folder = node.folder {
            return cell(MemoryText.label("\(folder.name)  \(folder.count)", size: 12, weight: .semibold, color: colors.text), top: 3)
        }
        guard let page = node.page else { return nil }
        let account = page.sessionID.flatMap(accountOf)
        let title = MemoryText.label(page.title, size: 12, color: colors.text)
        let detail = MemoryText.label(MemoryStatusText.origin(page, account: account), size: 11, color: colors.secondary)
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        let view = cell(stack, top: 2)
        view.toolTip = [page.relative, page.summary].compactMap { $0 }.joined(separator: "\n")
        return view
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

/// The page's colors, from the theme (the app sets them).
public struct MemoryColors {
    public var text: NSColor
    public var secondary: NSColor
    public var accent: NSColor

    public init(text: NSColor = .labelColor, secondary: NSColor = .secondaryLabelColor, accent: NSColor = .controlAccentColor) {
        self.text = text
        self.secondary = secondary
        self.accent = accent
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
