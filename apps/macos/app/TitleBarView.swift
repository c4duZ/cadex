import AppKit
import Icons
import Tabs

/// The title bar, drawn by the app inside the window's title area as in
/// Terax: room for the window buttons, sidebar and palette buttons, the
/// space's name, its tabs, "+", and on the right the search and settings.
/// Every button runs a command by id (ADR 0005).
///
/// One height (26 pt) for every control and the tabs, one icon size per
/// role, and gaps on a 4/8/12 pt scale; the bar mixed 16 and 13 pt icons
/// and 4 to 14 pt gaps with no rule (UI review, 2026-10-19).
final class TitleBarView: NSView {
    /// Matches the title area of a window with a unified compact toolbar,
    /// where macOS centers the window buttons.
    static let height: CGFloat = 38
    /// Space the close, minimize and zoom buttons take on the left.
    /// The first icon stays where it was: its 28 pt area starts 6 pt earlier.
    private static let windowButtonsWidth: CGFloat = 72

    private let run: (String) -> Void
    private let sidebarButton = TitleBarButton(icon: .sidebar, tip: "Painel lateral (⌘B)")
    private let paletteButton = TitleBarButton(icon: .command, tip: "Paleta de comandos (⌘K)")
    /// The space's name; clicking it switches spaces (docs/spec/spaces.md).
    private let spaceButton = TitleBarButton(icon: .stack, title: "", tip: "Trocar de space (⇧⌘S)")
    private let newTabButton = TitleBarButton(icon: .plus, tip: "Nova aba (⌘T)")
    private let searchButton = TitleBarSearch()
    private let settingsButton = TitleBarButton(icon: .gearSix, tip: "Configurações (⌘,)")
    /// The shown space's tabs; swapped when the space changes.
    private(set) var tabBar: TabBarView?
    private var tabBarConstraints: [NSLayoutConstraint] = []
    private var textColor = NSColor.labelColor
    private var secondaryColor = NSColor.secondaryLabelColor

    init(run: @escaping (String) -> Void) {
        self.run = run
        super.init(frame: .zero)
        sidebarButton.onPress = { [weak self] in self?.run("view.toggle-sidebar") }
        paletteButton.onPress = { [weak self] in self?.run("palette.open") }
        spaceButton.onPress = { [weak self] in self?.run("space.switch") }
        newTabButton.onPress = { [weak self] in self?.run("tab.new") }
        searchButton.onPress = { [weak self] in self?.run("palette.open") }
        settingsButton.onPress = { [weak self] in self?.run("settings.open") }
        spaceButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let views: [NSView] = [sidebarButton, paletteButton, spaceButton, newTabButton, searchButton, settingsButton]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            sidebarButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.windowButtonsWidth),
            paletteButton.leadingAnchor.constraint(equalTo: sidebarButton.trailingAnchor, constant: 4),
            spaceButton.leadingAnchor.constraint(equalTo: paletteButton.trailingAnchor, constant: 8),
            spaceButton.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            searchButton.leadingAnchor.constraint(greaterThanOrEqualTo: newTabButton.trailingAnchor, constant: 12),
            searchButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
            // Wide when there is room; the tabs give way before it shrinks.
            searchButton.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            searchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ] + views.map { $0.centerYAnchor.constraint(equalTo: centerYAnchor) })
        // Under the tabs' hold: in a narrow window the search shrinks first.
        let wide = searchButton.widthAnchor.constraint(equalToConstant: 280)
        wide.priority = NSLayoutConstraint.Priority(200)
        wide.isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarView is created in code") }

    /// The space, quiet: the stack icon alone with one space, its name and
    /// a caret with more. The name before the tabs weighed as much as them
    /// (owner, 2026-10-19).
    private var spaceTitle = ""
    private var spaceCount = 1
    func setSpace(name: String, count: Int) {
        spaceTitle = name
        spaceCount = count
        guard count > 1 else { return spaceButton.setTitle(NSAttributedString()) }
        let title = NSMutableAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryColor,
        ])
        title.append(NSAttributedString(string: " ▾", attributes: [
            .font: NSFont.systemFont(ofSize: 9), .foregroundColor: secondaryColor.withAlphaComponent(0.7),
        ]))
        spaceButton.setTitle(title)
    }

    /// Puts a space's tab bar between its name and "+".
    func setTabBar(_ bar: TabBarView) {
        guard bar !== tabBar else { return }
        tabBar?.removeFromSuperview()
        NSLayoutConstraint.deactivate(tabBarConstraints)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        tabBarConstraints = [
            bar.leadingAnchor.constraint(equalTo: spaceButton.trailingAnchor, constant: 4),
            bar.heightAnchor.constraint(equalToConstant: 30),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: 4),
        ]
        NSLayoutConstraint.activate(tabBarConstraints)
        // The tab bar is as wide as its tabs and gives way first when the
        // window is narrow.
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        tabBar = bar
    }

    /// Empty parts of the bar drag the window, like a normal title bar.
    override var mouseDownCanMoveWindow: Bool { true }

    func setColors(text: NSColor, secondary: NSColor, field: NSColor) {
        textColor = text
        secondaryColor = secondary
        // The bar's own controls in near-full contrast: in the quiet gray
        // they disappeared next to the tabs (owner, 2026-10-19).
        let strong = text.withAlphaComponent(0.78)
        for button in [sidebarButton, paletteButton, newTabButton, settingsButton] { button.colors = (text, strong) }
        spaceButton.colors = (text, secondary)
        searchButton.setColors(text: text, secondary: secondary, field: field)
        setSpace(name: spaceTitle, count: spaceCount)
    }
}
