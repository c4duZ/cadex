import AppKit
import CCadex

/// The outline's rows, cells and drag and drop. Dragging rows out gives
/// file URLs, which the terminal turns into quoted paths and the Finder
/// copies; dropping rows on a folder of the tree moves them there.
extension ExplorerController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    private func node(_ item: Any?) -> FileNode {
        (item as? FileNode) ?? root
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        node(item).visibleChildren(showHidden: showHidden).count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(item).visibleChildren(showHidden: showHidden)[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        node(item).isFolder
    }

    /// Folders are read the first time they open.
    public func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        let folder = node(item)
        if !folder.isLoaded { folder.load() }
        return true
    }

    public func outlineViewItemDidExpand(_ notification: Notification) {
        redrawIcon(notification)
    }

    public func outlineViewItemDidCollapse(_ notification: Notification) {
        redrawIcon(notification)
    }

    private func redrawIcon(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] else { return }
        let row = outline.row(forItem: item)
        if row >= 0 { outline.reloadData(forRowIndexes: [row], columnIndexes: [0]) }
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !node(item).isNote
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let file = node(item)
        let cell = (outlineView.makeView(withIdentifier: ExplorerCell.identifier, owner: nil) as? ExplorerCell) ?? ExplorerCell()
        cell.show(file, expanded: outlineView.isItemExpanded(item), style: style, git: gitMark(for: file))
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
    /// Same colors as the Git lists: green new, red deleted or in conflict,
    /// blue renamed, orange changed.
    static func gitColor(_ letter: Character) -> NSColor {
        switch letter {
        case "A", "?": .systemGreen
        case "D", "U": .systemRed
        case "R", "C": .systemBlue
        default: .systemOrange
        }
    }

    static let identifier = NSUserInterfaceItemIdentifier("explorer.cell")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        let icon = NSImageView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.font = .systemFont(ofSize: 13)
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
        imageView?.frame = NSRect(x: 2, y: mid - 8, width: 16, height: 16)
        let height = textField?.intrinsicContentSize.height ?? 17
        let markWidth: CGFloat = mark.stringValue.isEmpty ? 0 : 16
        textField?.frame = NSRect(x: 24, y: mid - height / 2, width: max(bounds.width - 28 - markWidth, 0), height: height)
        mark.frame = NSRect(x: bounds.width - markWidth - 4, y: mid - height / 2, width: markWidth, height: height)
    }

    /// The git change of a file (its letter) or a dot on a folder holding
    /// changes, in the change's color (docs/spec/source-control.md).
    private var mark: NSTextField {
        if let existing = subviews.first(where: { $0.identifier == Self.markIdentifier }) as? NSTextField { return existing }
        let field = NSTextField(labelWithString: "")
        field.identifier = Self.markIdentifier
        field.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        field.alignment = .right
        addSubview(field)
        return field
    }
    private static let markIdentifier = NSUserInterfaceItemIdentifier("explorer.git-mark")

    @MainActor
    func show(_ node: FileNode, expanded: Bool, style: ExplorerStyle, git: Character? = nil) {
        mark.stringValue = git.map { node.isFolder ? "•" : String($0) } ?? ""
        if let git { mark.textColor = Self.gitColor(git) }
        textField?.stringValue = node.name
        textField?.isEditable = false
        if node.isNote {
            imageView?.image = nil
            textField?.font = NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
            textField?.textColor = style.secondaryText
            return
        }
        textField?.font = .systemFont(ofSize: 13)
        imageView?.image = FileTypeIcon.icon(name: node.name, entry: node.entry, expanded: expanded).image(size: 15)
        imageView?.contentTintColor = node.isFolder ? style.accent : style.secondaryText
        textField?.textColor = git.map { node.isFolder ? style.text : Self.gitColor($0) } ?? style.text
        alphaValue = node.isHidden || node.entry?.ignored == true ? 0.55 : 1
        toolTip = node.entry?.kind == .symlink && !cadex_workspace_is_authorized(node.path) ? "Aponta para fora da pasta aberta" : nil
    }
}
