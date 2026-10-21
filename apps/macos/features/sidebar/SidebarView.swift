import AppKit
import Menus
import Strings
import UILooks

/// The sidebar (docs/spec/sidebar.md): the row of icons on top, the page's
/// title under it and the page itself. Which icons show, and in what
/// order, is sidebar.items; the app passes it in and saves what changes.
@MainActor
public final class SidebarView: NSView {
    /// The shown ids changed here (switch, drag); the app saves them.
    public var onItemsChange: (([String]) -> Void)?
    public private(set) var page: String?
    public private(set) var items: [String] = []
    private let catalog: [SidebarItem]
    private let run: (String) -> Void
    private let row = SidebarIconRow()
    private let title = NSTextField(labelWithString: "")
    private let content = NSView()
    private let empty: NSStackView
    private var titles: [String: String] = [:]
    private var panel: SidebarCustomizePanel?
    private var colors = SidebarColors()

    public init(catalog: [SidebarItem], run: @escaping (String) -> Void) {
        self.catalog = catalog
        self.run = run
        let emptyText = NSTextField(labelWithString: T("No pages. Customize to add one.", "Nenhuma página. Personalize para pôr uma."))
        emptyText.font = UILooks.font(12)
        emptyText.textColor = .secondaryLabelColor
        let emptyButton = NSButton(title: T("Customize…", "Personalizar…"), target: nil, action: nil)
        empty = NSStackView(views: [emptyText, emptyButton])
        empty.orientation = .vertical
        super.init(frame: .zero)
        emptyButton.target = self
        emptyButton.action = #selector(customizeFromEmpty)
        title.font = UILooks.font(12, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        row.onPress = { [weak self] id in self?.press(id) }
        row.onReorder = { [weak self] ids in self?.change(ids) }
        row.onCustomize = { [weak self] anchor in self?.customize(from: anchor) }
        row.onOverflow = { [weak self] ids, anchor in self?.overflow(ids, below: anchor) }
        for view in [row, title, content, empty] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for item in catalog {
            guard let view = item.view else { continue }
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = true
            content.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: content.topAnchor),
                view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            ])
        }
        let inset = UILooks.pt(8)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(6)),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            row.heightAnchor.constraint(equalToConstant: SidebarIconButton.size.height),
            title.topAnchor.constraint(equalTo: row.bottomAnchor, constant: UILooks.pt(8)),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset + UILooks.pt(4)),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: title.bottomAnchor, constant: UILooks.pt(4)),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            empty.centerXAnchor.constraint(equalTo: centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setItems(SidebarLayout.defaultItems)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarView is created in code") }

    var catalogItems: [SidebarItem] { catalog }

    /// The ids of every page and action the app knows.
    public var known: [String] { catalog.map(\.id) }

    /// sidebar.items from settings: unknown ids are dropped (and returned).
    @discardableResult
    public func setItems(_ saved: [String]) -> [String] {
        let (ids, problems) = SidebarLayout.shown(saved, known: known)
        items = ids
        row.setItems(ids.compactMap { id in catalog.first { $0.id == id } })
        row.select(page)
        let none = ids.isEmpty
        empty.isHidden = !none
        content.isHidden = none
        title.isHidden = none
        if page == nil, let first = ids.first(where: { id in catalog.first { $0.id == id }?.view != nil }) { show(first) }
        return problems
    }

    /// Shows a page; a page whose icon is hidden still shows (its shortcut).
    public func show(_ id: String) {
        guard let item = catalog.first(where: { $0.id == id }), item.view != nil else { return }
        page = id
        for other in catalog { other.view?.isHidden = other.id != id }
        row.select(id)
        title.stringValue = titles[id] ?? item.title
    }

    /// The text under the icons for a page: the folder's name for Files.
    public func setTitle(_ text: String?, for id: String) {
        titles[id] = text
        if page == id { title.stringValue = text ?? catalog.first { $0.id == id }?.title ?? "" }
    }

    /// The mark on an icon: a count, "" for a dot, nil for none.
    public func setBadge(_ badge: String?, for id: String) { row.setBadge(badge, for: id) }

    public func setColors(_ colors: SidebarColors) {
        self.colors = colors
        row.colors = colors
        title.textColor = colors.text
    }

    /// The sidebar.customize command: the panel under the customize button.
    public func customize() { customize(from: row.customize) }

    /// Shows or hides one page's icon (sidebar.toggle-page from ⌘K).
    public func toggle(_ id: String) {
        guard known.contains(id) else { return }
        change(SidebarLayout.toggled(items, id))
    }

    func press(_ id: String) {
        guard let item = catalog.first(where: { $0.id == id }) else { return }
        if item.view != nil, page == id, !isHidden {
            run("view.toggle-sidebar")
        } else {
            run(item.command)
        }
    }

    private func change(_ ids: [String]) {
        setItems(ids)
        onItemsChange?(ids)
    }

    private func customize(from anchor: NSView) {
        if let panel, panel.isVisible { return panel.makeKeyAndOrderFront(nil) }
        let panel = SidebarCustomizePanel(catalog: catalog, shown: items, colors: colors) { [weak self] ids in self?.change(ids) }
        panel.show(over: anchor.window)
        self.panel = panel
    }

    @objc private func customizeFromEmpty() { customize(from: empty) }

    private func overflow(_ ids: [String], below anchor: NSView) {
        let entries = ids.compactMap { id in catalog.first { $0.id == id } }.map { item in
            MenuEntry(item.title, icon: item.icon, shortcut: item.shortcut) { [weak self] in self?.press(item.id) }
        }
        PopupMenu.show(entries, below: anchor)
    }
}
