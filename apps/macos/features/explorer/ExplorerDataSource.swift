import AppKit
import Strings
import CCadex
import Icons

/// The outline's rows, cells and drag and drop. Dragging rows out gives
/// file URLs, which the terminal turns into quoted paths and the Finder
/// copies; dropping rows on a folder of the tree moves them there.
extension ExplorerController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    private func node(_ item: Any?) -> FileNode {
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
        row.accent = style.accent
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
        label.font = .systemFont(ofSize: 12)
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
        imageView?.frame = NSRect(x: 2, y: mid - 7, width: 14, height: 14)
        let height = textField?.intrinsicContentSize.height ?? 17
        let markWidth: CGFloat = mark.stringValue.isEmpty ? 0 : 16
        textField?.frame = NSRect(x: 22, y: mid - height / 2, width: max(bounds.width - 26 - markWidth, 0), height: height)
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
    func show(_ node: FileNode, title: String? = nil, expanded: Bool, style: ExplorerStyle, git: Character? = nil) {
        mark.stringValue = git.map { node.isFolder ? "•" : String($0) } ?? ""
        if let git { mark.textColor = Self.gitColor(git) }
        textField?.stringValue = title ?? node.name
        textField?.isEditable = false
        if node.isNote {
            imageView?.image = nil
            textField?.font = NSFontManager.shared.convert(.systemFont(ofSize: 11), toHaveTrait: .italicFontMask)
            textField?.textColor = style.secondaryText
            return
        }
        textField?.font = .systemFont(ofSize: 12)
        // The Material Icon Theme's drawing when it knows the name (Docker,
        // Python, src, tests...; docs/adr/0011), in its own colors; else the
        // Phosphor glyph, folders in the theme's accent (with them gray, a
        // theme changed only the background, owner, 2026-10-19).
        let link = node.entry?.kind == .symlink
        if !link, let material = node.isFolder ? FileIcons.folderImage(named: node.name) : FileIcons.image(forFileNamed: node.name) {
            imageView?.image = material
            imageView?.contentTintColor = nil
        } else {
            imageView?.image = FileTypeIcon.icon(name: node.name, entry: node.entry, expanded: expanded).image(size: 14)
            imageView?.contentTintColor = node.isFolder ? style.accent : FileIcons.color(forFileNamed: node.name) ?? style.secondaryText
        }
        textField?.textColor = git.map { node.isFolder ? style.text : Self.gitColor($0) } ?? style.text
        alphaValue = node.isHidden || node.entry?.ignored == true ? 0.55 : 1
        toolTip = node.entry?.kind == .symlink && !cadex_workspace_is_authorized(node.path) ? T("Points outside the open folder", "Aponta para fora da pasta aberta") : nil
    }
}

/// A row of the tree, drawn as in VS Code: a light fill under the pointer,
/// thin indent guides while the pointer is over the tree, and the selection
/// in the theme's accent, with a 1 pt border when the tree has the keyboard.
/// The system's gray selection barely showed without focus, and its blue
/// ignored the theme (owner, 2026-10-19).
final class ExplorerRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("explorer.row")
    var accent: NSColor = .controlAccentColor { didSet { needsDisplay = true } }
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

    override func drawSelection(in dirtyRect: NSRect) {
        accent.withAlphaComponent(isEmphasized ? 0.28 : 0.16).setFill()
        bounds.fill()
        guard isEmphasized else { return }
        accent.withAlphaComponent(0.8).setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
    }

    /// The text stays in its own colors on the light fill.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
