import AppKit
import Customize
import Menus
import Strings
import UILooks

/// The bar at the bottom of the window, made of items the user picks and
/// drags between left and right (docs/spec/status-bar.md). With nothing
/// set, the bar from before: the folder trail on the left, the environment
/// on the right. Each item is told when it can be seen (shown, and the
/// window on screen), so a hidden one costs nothing.
@MainActor
public final class StatusBarView: NSView {
    public static var height: CGFloat { UILooks.rowHeight(26) }

    public struct Style {
        public var text: NSColor
        public var secondaryText: NSColor

        public init(text: NSColor, secondaryText: NSColor) {
            self.text = text
            self.secondaryText = secondaryText
        }
    }

    public var style = Style(text: .labelColor, secondaryText: .secondaryLabelColor) { didSet { restyle() } }
    /// The folder shown; nil while unknown.
    public var path: String? {
        get { folder.path }
        set { folder.path = newValue }
    }
    /// Whether picking a folder may move the terminal (the shell is idle).
    public var canNavigate: Bool {
        get { folder.canNavigate }
        set { folder.canNavigate = newValue }
    }
    /// A folder picked in a piece's menu.
    public var onNavigate: ((String) -> Void)? {
        get { folder.onNavigate }
        set { folder.onNavigate = newValue }
    }
    /// The sides changed here (right click, Customize); the app saves them.
    public var onLayoutChange: (([String], [String]) -> Void)?
    /// Runs a command by id (statusBar.customize from the right-click menu).
    public var run: ((String) -> Void)?
    public private(set) var left: [String] = []
    public private(set) var right: [String] = []
    private(set) var catalog: [StatusItem] = []
    private let folder = FolderTrail()
    private let environment = StatusLabel(icon: nil)
    private let leftStack = NSStackView()
    private let rightStack = NSStackView()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        environment.text = "Local"
        catalog = [
            StatusItem(id: "folder", title: T("Folder", "Pasta"), subtitle: T("The focused terminal's folder", "A pasta do terminal com foco"),
                       icon: .folder, side: .left, view: folder),
            StatusItem(id: "environment", title: T("Environment", "Ambiente"), subtitle: T("Where programs run", "Onde os programas rodam"),
                       icon: .terminalWindow, side: .right, view: environment),
        ]
        for stack in [leftStack, rightStack] {
            stack.orientation = .horizontal
            stack.spacing = UILooks.pt(16)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
        }
        leftStack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        rightStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            leftStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            leftStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftStack.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -16),
            rightStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rightStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setLayout(left: StatusBarLayout.defaultLeft, right: StatusBarLayout.defaultRight)
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("StatusBarView is created in code") }

    /// The items the app adds after the bar's own (Git branch, terminals, RAM...).
    public func add(_ items: [StatusItem]) {
        catalog += items.filter { item in !catalog.contains { $0.id == item.id } }
        restyle()
        setLayout(left: left, right: right)
    }

    public var known: [String] { catalog.map(\.id) }
    var catalogItems: [StatusItem] { catalog }

    /// statusBar.left and statusBar.right from settings; unknown ids are
    /// dropped (and returned).
    @discardableResult
    public func setLayout(left: [String], right: [String]) -> [String] {
        let placed = StatusBarLayout.placed(left: left, right: right, known: known)
        self.left = placed.left
        self.right = placed.right
        arrange(leftStack, placed.left)
        arrange(rightStack, placed.right)
        updateVisibility()
        return placed.problems
    }

    /// Shows or hides one item (statusBar.toggle-item, the right-click menu).
    public func toggle(_ id: String) {
        guard let item = catalog.first(where: { $0.id == id }) else { return }
        let sides = StatusBarLayout.toggled(left: left, right: right, id, side: item.side)
        change(sides.left, sides.right)
    }

    /// The Status Bar tab of the Customize window: Left and Right, the
    /// sides going back to statusBar.left and statusBar.right.
    public var customizePage: CustomizePage {
        CustomizePage(id: "statusBar", title: T("Status Bar", "Barra de status"), icon: .slidersHorizontal,
                      note: T("Drag between Left and Right. A hidden item measures nothing. Also on a right click on the bar.",
                              "Arraste entre Esquerda e Direita. Item escondido não mede nada. Também no botão direito na barra."),
                      entries: StatusBarLayout.entries(left: left, right: right, catalog: catalog)) { [weak self] entries in
            let sides = StatusBarLayout.sides(from: entries)
            self?.change(sides.left, sides.right)
        }
    }

    private func change(_ left: [String], _ right: [String]) {
        setLayout(left: left, right: right)
        onLayoutChange?(left, right)
    }

    private func arrange(_ stack: NSStackView, _ ids: [String]) {
        let views = ids.compactMap { id in catalog.first { $0.id == id }?.view }
        guard stack.arrangedSubviews != views else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach(stack.addArrangedSubview)
    }

    private func restyle() {
        folder.colors = (style.text, style.secondaryText)
        for item in catalog { (item.view as? StatusLabel)?.color = style.secondaryText }
    }

    // MARK: Seen or not

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: window)
        }
        updateVisibility()
    }

    @objc private func occlusionChanged() { updateVisibility() }

    /// An item is seen when it is in the bar and the window is on screen
    /// (not minimized, not hidden, not behind another Space).
    private func updateVisibility() {
        let onScreen = window?.occlusionState.contains(.visible) == true
        for item in catalog { item.setVisible(onScreen && (left.contains(item.id) || right.contains(item.id))) }
    }

    // MARK: Right click

    public override func rightMouseDown(with event: NSEvent) {
        let shown = Set(left + right)
        var entries = catalog.map { item in
            MenuEntry(item.title, icon: shown.contains(item.id) ? .check : nil) { [weak self] in self?.toggle(item.id) }
        }
        entries.append(.separator)
        entries.append(MenuEntry(T("Customize Status Bar…", "Personalizar a barra de status…"), icon: .slidersHorizontal) { [weak self] in
            self?.run?("statusBar.customize")
        })
        PopupMenu.show(entries, at: convert(event.locationInWindow, from: nil), in: self, upward: true)
    }
}
