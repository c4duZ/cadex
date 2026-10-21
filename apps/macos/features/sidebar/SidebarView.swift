import AppKit
import Customize
import Menus
import Strings
import UILooks

/// The sidebar (docs/spec/sidebar.md): the row of icons on top, the page's
/// title under it and the page itself. Which icons show, and in what
/// order, is sidebar.items; the app passes it in and saves what changes.
@MainActor
public final class SidebarView: NSView {
    /// A page came into view: the app makes a page's content only then
    /// (Git History), so a page nobody opens costs nothing.
    public var onShow: ((String) -> Void)?
    /// The shown ids changed here (switch, drag); the app saves them.
    public var onItemsChange: (([String]) -> Void)?
    public private(set) var page: String?
    /// A page's sub-tab was picked (or the page came with one): the app
    /// switches the page's view.
    public var onSubtab: ((String, String) -> Void)?
    /// The sub-tab each page shows, the first until one is picked.
    public private(set) var subtab: [String: String] = [:]
    private let subtabs = SidebarSubtabs()
    public private(set) var items: [String] = []
    private let catalog: [SidebarItem]
    private let run: (String) -> Void
    private let row = SidebarIconRow()
    private let title = NSTextField(labelWithString: "")
    private let content = NSView()
    private let empty: NSStackView
    private var titles: [String: String] = [:]
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
        row.onCustomize = { [weak self] _ in self?.customize() }
        row.onOverflow = { [weak self] ids, anchor in self?.overflow(ids, below: anchor) }
        subtabs.onPick = { [weak self] index in self?.subtabPicked(index) }
        subtabs.isHidden = true
        for view in [row, title, subtabs, content, empty] as [NSView] {
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
            title.trailingAnchor.constraint(lessThanOrEqualTo: subtabs.leadingAnchor, constant: -UILooks.pt(6)),
            subtabs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            subtabs.centerYAnchor.constraint(equalTo: title.centerYAnchor),
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
        if none { subtabs.isHidden = true }
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
        showSubtabs(of: item)
        onShow?(id)
    }

    /// Picks a page's sub-tab from code (a command, a click elsewhere).
    public func select(subtab sub: String, of id: String) {
        guard let item = catalog.first(where: { $0.id == id }), item.subtabs.contains(where: { $0.id == sub }) else { return }
        subtab[id] = sub
        if page == id { showSubtabs(of: item) } else { onSubtab?(id, sub) }
    }

    private func showSubtabs(of item: SidebarItem) {
        subtabs.isHidden = item.subtabs.isEmpty
        guard !item.subtabs.isEmpty else { return }
        let current = subtab[item.id] ?? item.subtabs[0].id
        subtab[item.id] = current
        subtabs.set(item.subtabs.map(\.title), selected: item.subtabs.firstIndex { $0.id == current } ?? 0)
        onSubtab?(item.id, current)
    }

    private func subtabPicked(_ index: Int) {
        guard let page, let item = catalog.first(where: { $0.id == page }), item.subtabs.indices.contains(index) else { return }
        let sub = item.subtabs[index].id
        subtab[page] = sub
        onSubtab?(page, sub)
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
        subtabs.colors = colors
        title.textColor = colors.text
    }

    /// The customize button: the app opens the Customize window on the
    /// Sidebar tab (sidebar.customize).
    public var onCustomize: (() -> Void)?
    public func customize() { onCustomize?() }

    /// Shows or hides one page's icon (sidebar.toggle-page from ⌘K).
    public func toggle(_ id: String) {
        guard known.contains(id) else { return }
        change(SidebarLayout.toggled(items, id))
    }

    /// The icon at `position` (from 1): ⌃⌘1 to ⌃⌘9 (sidebar.page-N), as
    /// ⌘1 to ⌘9 pick the tabs (the owner, 2026-10-21; ⇧⌘3 to ⇧⌘5 are the
    /// system's screenshots). Runs its command and never hides the sidebar,
    /// as a click on the open page's icon does: the owner pressed the open
    /// page's keys and lost the sidebar (2026-10-21). False when none.
    @discardableResult
    public func press(position: Int) -> Bool {
        guard items.indices.contains(position - 1), let item = catalog.first(where: { $0.id == items[position - 1] }) else { return false }
        run(item.command)
        return true
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

    /// The window's list: every page, the shown ones first, in order.
    func customizeEntries() -> [CustomizeEntry] {
        let rows = SidebarLayout.customizeOrder(shown: items, known: known).compactMap { id in
            catalog.first { $0.id == id }.map {
                CustomizeEntry.row(CustomizeRow(id: $0.id, icon: $0.icon, title: $0.title, trailing: $0.shortcut, on: items.contains($0.id)))
            }
        }
        return [.header(T("Sidebar icons", "Ícones do painel lateral"))] + rows
    }

    @objc private func customizeFromEmpty() { customize() }

    /// The Sidebar tab of the Customize window: the shown ids go back to
    /// sidebar.items.
    public var customizePage: CustomizePage {
        CustomizePage(id: "sidebar", title: T("Sidebar", "Painel lateral"), icon: .sidebar,
                      note: T("Drag to reorder. Also in ⌘K: “Customize Sidebar”.",
                              "Arraste para reordenar. Também no ⌘K: “Personalizar o painel lateral”."),
                      entries: customizeEntries()) { [weak self] entries in
            self?.change(CustomizeLayout.sections(entries).flatMap { $0 }.filter(\.on).map(\.id))
        }
    }

    private func overflow(_ ids: [String], below anchor: NSView) {
        let entries = ids.compactMap { id in catalog.first { $0.id == id } }.map { item in
            MenuEntry(item.title, icon: item.icon, shortcut: item.shortcut) { [weak self] in self?.press(item.id) }
        }
        PopupMenu.show(entries, below: anchor)
    }
}
