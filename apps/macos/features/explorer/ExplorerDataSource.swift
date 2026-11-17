import AppKit
import UILooks
import Strings
import CCadex
import Icons

/// The outline's rows, cells and drag and drop. Dragging rows out gives
/// file URLs, which the terminal turns into quoted paths and the Finder
/// copies; dropping rows on a folder of the tree moves them there.
extension ExplorerController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func node(_ item: Any?) -> FileNode {
        (item as? FileNode) ?? root
    }

    /// A row's children are its chain's last folder's (ExplorerCompact.swift).
    private func contents(_ item: Any?) -> FileNode {
        item == nil ? root : tail(of: node(item))
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        contents(item).visibleChildren(showHidden: showHidden).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let child = contents(item).visibleChildren(showHidden: showHidden)[index]
        register(child)
        return child
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        node(item).isFolder
    }

    /// Folders are read the first time they open.
    public func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        loadChain(from: node(item))
        return true
    }

    public func outlineViewItemDidExpand(_ notification: Notification) {
        redrawIcon(notification)
        saveExpanded()
    }

    public func outlineViewItemDidCollapse(_ notification: Notification) {
        redrawIcon(notification)
        saveExpanded()
    }

    private func redrawIcon(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] else { return }
        let row = outline.row(forItem: item)
        if row >= 0 { outline.reloadData(forRowIndexes: [row], columnIndexes: [0]) }
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !node(item).isNote
    }

    public func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = (outlineView.makeView(withIdentifier: ExplorerRowView.identifier, owner: nil) as? ExplorerRowView) ?? ExplorerRowView()
        row.guide = style.secondaryText.withAlphaComponent(0.25)
        return row
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let file = node(item)
        let cell = (outlineView.makeView(withIdentifier: ExplorerCell.identifier, owner: nil) as? ExplorerCell) ?? ExplorerCell()
        cell.show(file, title: title(of: file), expanded: outlineView.isItemExpanded(item), style: style, git: gitMark(for: file))
        cell.textField?.delegate = self
        return cell
    }

    // MARK: Drag and drop

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        let file = node(item)
        return file.isNote ? nil : URL(fileURLWithPath: file.path) as NSURL
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                            proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        // Only rows of this tree move; files from elsewhere are not copied
        // in yet (the core copies within the workspace).
        guard info.draggingSource as? NSOutlineView === outline else { return [] }
        var target = node(item)
        if !target.isFolder { target = (outline.parent(forItem: target) as? FileNode) ?? root }
        if target === root { outlineView.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex) }
        else { outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex) }
        return .move
    }

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        move(urls.map(\.path), into: node(item))
        return !urls.isEmpty
    }
}

/// A row: icon and name; hidden files dimmed, notes in italics.
final class ExplorerCell: NSTableCellView {
    typealias Tree = DesignTokens.Inspector.Tree

    /// The drawing's colors (components.inspector.tree.mark), as Changes: green new, red deleted
    /// or in conflict, dim renamed, amber changed.
    static func gitColor(_ letter: Character) -> NSColor {
        switch letter {
        case "A", "?": Tree.Mark.added
        case "D", "U": DesignTokens.Color.accentRedText
        case "R", "C": DesignTokens.Color.textTertiary
        default: Tree.Mark.modified
        }
    }

    static let identifier = NSUserInterfaceItemIdentifier("explorer.cell")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        let icon = NSImageView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.font = UILooks.font(Tree.Name.fontSize)
        label.cell?.isScrollable = true
        addSubview(icon)
        addSubview(label)
        imageView = icon
        textField = label
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ExplorerCell is created in code") }

    /// Laid out by hand: with constraints, cells the outline reused after a
    /// reload kept a 2-point-wide name, so the tree showed only icons
    /// (2026-10-19).
    override func layout() {
        super.layout()
        let mid = bounds.midY
        let icon = UILooks.pt(Tree.icon)
        imageView?.frame = NSRect(x: UILooks.labelInset, y: mid - icon / 2, width: icon, height: icon)
        let height = textField?.intrinsicContentSize.height ?? 17
        let markWidth: CGFloat = mark.stringValue.isEmpty ? 0 : UILooks.pt(Tree.indent)
        // The text field draws its text 2 pt in: start it 2 pt early so the name sits where the
        // drawing has it (measured 2026-11-17).
        let x = icon + UILooks.pt(Tree.gap)
        let right = UILooks.pt(Tree.listPadding.right + Tree.padding.right)
        textField?.frame = NSRect(x: x, y: mid - height / 2, width: max(bounds.width - x - right - markWidth, 0), height: height)
        // Centered on its own height: on the name's, the smaller letter sat 1.5 pt high.
        let markHeight = mark.intrinsicContentSize.height
        mark.frame = NSRect(x: bounds.width - markWidth - right, y: mid - markHeight / 2, width: markWidth, height: markHeight)
    }

    /// The git change of a file (its letter) or a dot on a folder holding
    /// changes, in the change's color (docs/spec/source-control.md).
    private var mark: NSTextField {
        if let existing = subviews.first(where: { $0.identifier == Self.markIdentifier }) as? NSTextField { return existing }
        let field = NSTextField(labelWithString: "")
        field.identifier = Self.markIdentifier
        field.font = UILooks.font(Tree.Mark.fontSize, weight: Tree.Mark.weight)
        field.alignment = .right
        addSubview(field)
        return field
    }
    private static let markIdentifier = NSUserInterfaceItemIdentifier("explorer.git-mark")

    @MainActor
    func show(_ node: FileNode, title: String? = nil, expanded: Bool, style: ExplorerStyle, git: Character? = nil) {
        mark.stringValue = node.isFolder ? "" : git.map(String.init) ?? ""
        if let git { mark.textColor = Self.gitColor(git) }
        textField?.stringValue = title ?? node.name
        textField?.isEditable = false
        if node.isNote {
            imageView?.image = nil
            textField?.font = NSFontManager.shared.convert(UILooks.font(11), toHaveTrait: .italicFontMask)
            textField?.textColor = style.secondaryText
            return
        }
        textField?.font = UILooks.font(Tree.Name.fontSize)
        // The Files drawing (plan 26 C2b, redone 2026-11-17): one calm color per kind, folders
        // blue, sources amber, docs pale blue, the rest gray; the Material icons each in their own
        // colors made the tree look like a patchwork next to the drawing (owner, 2026-11-17).
        imageView?.image = FileTypeIcon.icon(name: node.name, entry: node.entry, expanded: expanded).image(size: UILooks.pt(Tree.icon))
        imageView?.contentTintColor = FileTypeIcon.color(name: node.name, entry: node.entry)
        // A changed file's name in amber (the drawing), a new one green; folders keep the row's.
        textField?.textColor = node.isFolder ? Tree.Name.color : git.map { $0 == "M" ? Tree.Name.changed : Self.gitColor($0) } ?? Tree.Name.color
        alphaValue = node.isHidden || node.entry?.ignored == true ? 0.55 : 1
        toolTip = node.entry?.kind == .symlink && !cadex_workspace_is_authorized(node.path) ? T("Points outside the open folder", "Aponta para fora da pasta aberta") : nil
    }
}

/// A row of the tree: a light fill under the pointer, thin indent guides while the pointer is over
/// the tree, and the selection as the Files drawing has it (plan 26 C2b), the same with or without
/// the keyboard. The system's gray selection barely showed without focus (owner, 2026-10-19).
final class ExplorerRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("explorer.row")
    var guide: NSColor = .separatorColor

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ExplorerRowView is created in code") }

    private var outline: ExplorerOutline? { superview as? ExplorerOutline }

    override func drawBackground(in dirtyRect: NSRect) {
        guard let outline else { return }
        let row = outline.row(for: self)
        guard row >= 0 else { return }
        if !isSelected, row == outline.hoveredRow {
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            bounds.fill()
        }
        guard outline.pointerInside else { return }
        guide.setFill()
        for x in outline.guideXs(row: row) {
            NSRect(x: x.rounded(.down), y: 0, width: 1, height: bounds.height).fill()
        }
    }

    /// The chosen row as the drawing has it (components.inspector.tree.selected): the raised fill,
    /// rounded, with its 1 pt line inside; the same with or without the keyboard.
    override func drawSelection(in dirtyRect: NSRect) {
        typealias Tree = DesignTokens.Inspector.Tree
        let radius = UILooks.pt(Tree.radius)
        let box = bounds.insetBy(dx: UILooks.pt(Tree.listPadding.left), dy: 0)
        Tree.Selected.bg.setFill()
        NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius).fill()
        guard let line = Tree.Selected.shadow.first else { return }
        line.color.setStroke()
        let border = NSBezierPath(roundedRect: box.insetBy(dx: line.spread / 2, dy: line.spread / 2), xRadius: radius, yRadius: radius)
        border.lineWidth = line.spread
        border.stroke()
    }

    /// The text stays in its own colors on the light fill.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
