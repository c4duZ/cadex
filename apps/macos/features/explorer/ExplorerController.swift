import AppKit
import Icons

/// Colors of the tree, from the theme (the app fills them; this feature
/// does not depend on themes).
public struct ExplorerStyle: Equatable {
    public var text: NSColor
    public var secondaryText: NSColor
    public var accent: NSColor

    public init(text: NSColor, secondaryText: NSColor, accent: NSColor) {
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
    }
}

/// The file tree in the sidebar (docs/spec/explorer.md): the workspace
/// folder at the top, folders read when opened, live updates from the
/// core's watcher. Every action is a command (ExplorerCommands); keys,
/// buttons and the context menu run them by id.
@MainActor
public final class ExplorerController: NSObject {
    public let view = NSView()
    let outline = ExplorerOutline()
    private let header = NSTextField(labelWithString: "")
    private let message = NSTextField(labelWithString: "")
    private var messageTimer: Timer?
    private var buttons: [NSButton] = []
    private(set) var root: FileNode
    private var watcher: FileWatcher?
    /// The row whose name is being edited (ExplorerRename.swift).
    var renaming: FileNode?
    /// Runs a command by id through the registry; false when unavailable.
    let run: (String) -> Bool

    /// Hidden files (names starting with ".") in the tree, dimmed.
    public var showHidden = true {
        didSet { if showHidden != oldValue { reloadOutline() } }
    }
    /// The explorer.toggle-hidden command changed showHidden: save it.
    public var onShowHiddenChange: ((Bool) -> Void)?
    /// Takes the focused terminal to a folder (explorer.open-in-terminal).
    public var openInTerminal: ((String) -> Void)?
    /// Makes the sidebar visible (explorer.focus with the sidebar hidden).
    public var revealSidebar: (() -> Void)?
    public var style = ExplorerStyle(text: .labelColor, secondaryText: .secondaryLabelColor, accent: .controlAccentColor) {
        didSet { applyStyle() }
    }

    public init(root path: String, run: @escaping (String) -> Bool) {
        root = FileNode(path: path, entry: nil)
        self.run = run
        super.init()
        buildView()
        setRoot(path)
    }

    /// Shows another folder: the workspace changed.
    public func setRoot(_ path: String) {
        root = FileNode(path: path, entry: nil)
        root.load()
        header.stringValue = (path as NSString).lastPathComponent
        header.toolTip = path
        outline.reloadData()
        watcher = FileWatcher(path: path) { [weak self] changes in self?.apply(changes) }
    }

    // MARK: Selection

    var selectedNodes: [FileNode] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? FileNode }.filter { !$0.isNote }
    }

    /// Where new and pasted items go: the selected folder, the selected
    /// file's folder, or the root.
    func targetFolder() -> FileNode {
        guard let node = selectedNodes.last else { return root }
        if node.isFolder { return node }
        return (outline.parent(forItem: node) as? FileNode) ?? root
    }

    /// Opens the folders down to `path` (inside the root) and selects it.
    func select(path: String) {
        var folder = root
        while let next = folder.children?.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) {
            if next.path == path { break }
            if !next.isLoaded { next.load() }
            outline.expandItem(next)
            folder = next
        }
        guard let node = root.find(path) else { return }
        let row = outline.row(forItem: node)
        guard row >= 0 else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        outline.scrollRowToVisible(row)
    }

    // MARK: Reloading

    /// Reads `node` again and redraws its rows, keeping open folders open.
    func reload(_ node: FileNode) {
        let selected = selectedNodes.map(\.path)
        node.load()
        outline.reloadItem(node === root ? nil : node, reloadChildren: true)
        restoreSelection(selected)
    }

    /// Every loaded folder, read again (explorer.refresh).
    func reloadAll() {
        root.loadedFolders().forEach { $0.load() }
        reloadOutline()
    }

    private func reloadOutline() {
        let selected = selectedNodes.map(\.path)
        outline.reloadData()
        restoreSelection(selected)
    }

    private func restoreSelection(_ paths: [String]) {
        let rows = paths.compactMap { root.find($0) }.map { outline.row(forItem: $0) }.filter { $0 >= 0 }
        outline.selectRowIndexes(IndexSet(rows), byExtendingSelection: false)
    }

    /// A batch from the watcher: the loaded folders among the changed ones
    /// are read again. Others are read when opened.
    private func apply(_ changes: [FileWatcher.Change]) {
        var folders: [FileNode] = []
        for change in changes {
            guard let node = root.find(change.path), node.isLoaded else { continue }
            folders += change.subtree ? node.loadedFolders() : [node]
        }
        guard !folders.isEmpty else { return }
        if folders.count > 20 || folders.contains(where: { $0 === root }) {
            folders.forEach { $0.load() }
            reloadOutline()
        } else {
            folders.forEach(reload)
        }
    }

    // MARK: Messages

    /// A short note under the tree ("Já existe um item com esse nome").
    func showMessage(_ text: String) {
        message.stringValue = text
        message.isHidden = false
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.message.isHidden = true }
        }
    }

    // MARK: View

    private func buildView() {
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.lineBreakMode = .byTruncatingMiddle
        message.font = .systemFont(ofSize: 11)
        message.isHidden = true
        message.lineBreakMode = .byWordWrapping
        outline.configure(controller: self)
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        buttons = [
            button(.filePlus, "explorer.new-file", "Novo arquivo"),
            button(.folderPlus, "explorer.new-folder", "Nova pasta"),
            button(.arrowsClockwise, "explorer.refresh", "Recarregar"),
        ]
        let bar = NSStackView(views: [header] + buttons)
        bar.spacing = 2
        bar.setHuggingPriority(.defaultLow, for: .horizontal)
        header.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [bar, scroll, message] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            bar.heightAnchor.constraint(equalToConstant: 24),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: message.topAnchor, constant: -4),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            message.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
        applyStyle()
    }

    private func button(_ icon: Icon, _ command: String, _ tip: String) -> NSButton {
        let b = NSButton(image: icon.image(size: 14), target: self, action: #selector(runButton(_:)))
        b.isBordered = false
        b.identifier = NSUserInterfaceItemIdentifier(command)
        b.toolTip = tip
        b.widthAnchor.constraint(equalToConstant: 22).isActive = true
        return b
    }

    @objc private func runButton(_ sender: NSButton) {
        _ = run(sender.identifier?.rawValue ?? "")
    }

    private func applyStyle() {
        header.textColor = style.text
        message.textColor = style.secondaryText
        buttons.forEach { $0.contentTintColor = style.secondaryText }
        outline.reloadData()
    }
}
