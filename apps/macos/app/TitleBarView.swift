import AppKit
import Icons
import Tabs

/// The title bar, drawn by the app inside the window's title area as in
/// Terax: room for the window buttons, sidebar and palette buttons, the
/// space's name, its tabs, "+", and on the right the search field. Every button runs a
/// command by id (ADR 0005).
final class TitleBarView: NSView {
    /// Matches the title area of a window with a unified compact toolbar,
    /// where macOS centers the window buttons.
    static let height: CGFloat = 38
    /// Space the close, minimize and zoom buttons take on the left.
    private static let windowButtonsWidth: CGFloat = 78

    private let run: (String) -> Void
    private let sidebarButton: NSButton
    private let paletteButton: NSButton
    private let newTabButton: NSButton
    private let searchButton = NSButton()
    private let settingsButton: NSButton
    /// The space's name; clicking it switches spaces (docs/spec/spaces.md).
    private let spaceButton = NSButton(title: "", target: nil, action: nil)
    /// The shown space's tabs; swapped when the space changes.
    private(set) var tabBar: TabBarView?
    private var tabBarConstraints: [NSLayoutConstraint] = []
    private var textColor = NSColor.labelColor
    private var secondaryColor = NSColor.secondaryLabelColor
    private var fieldColor = NSColor.controlBackgroundColor

    init(run: @escaping (String) -> Void) {
        self.run = run
        sidebarButton = Self.iconButton(.sidebar, "Painel lateral")
        paletteButton = Self.iconButton(.command, "Paleta de comandos (⌘K)")
        newTabButton = Self.iconButton(.plus, "Nova aba (⌘T)")
        settingsButton = Self.iconButton(.gearSix, "Configurações (⌘,)")
        super.init(frame: .zero)
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar)
        paletteButton.target = self
        paletteButton.action = #selector(openPalette)
        newTabButton.target = self
        newTabButton.action = #selector(newTab)
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        searchButton.isBordered = false
        searchButton.image = Icon.magnifyingGlass.image(size: 13)
        searchButton.imagePosition = .imageLeading
        searchButton.imageHugsTitle = true
        searchButton.target = self
        searchButton.action = #selector(openPalette)
        spaceButton.isBordered = false
        spaceButton.toolTip = "Trocar de space (⇧⌘S)"
        spaceButton.target = self
        spaceButton.action = #selector(switchSpace)
        spaceButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let views: [NSView] = [sidebarButton, paletteButton, spaceButton, newTabButton, searchButton, settingsButton]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            sidebarButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.windowButtonsWidth),
            paletteButton.leadingAnchor.constraint(equalTo: sidebarButton.trailingAnchor, constant: 6),
            spaceButton.leadingAnchor.constraint(equalTo: paletteButton.trailingAnchor, constant: 12),
            spaceButton.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            searchButton.leadingAnchor.constraint(greaterThanOrEqualTo: newTabButton.trailingAnchor, constant: 12),
            searchButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -14),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ] + views.map { $0.centerYAnchor.constraint(equalTo: centerYAnchor) })
    }

    /// The space as a breadcrumb before its tabs, "Space 1 ›", quiet as in
    /// Terax ("Default ›"); the bold name competed with the tabs (2026-10-19).
    private var spaceTitle = ""
    var spaceName: String {
        get { spaceTitle }
        set {
            spaceTitle = newValue
            let title = NSMutableAttributedString(string: newValue, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryColor,
            ])
            title.append(NSAttributedString(string: "  ›", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondaryColor.withAlphaComponent(0.6),
            ]))
            spaceButton.attributedTitle = title
        }
    }

    /// Puts a space's tab bar between its name and "+".
    func setTabBar(_ bar: TabBarView) {
        guard bar !== tabBar else { return }
        tabBar?.removeFromSuperview()
        NSLayoutConstraint.deactivate(tabBarConstraints)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        tabBarConstraints = [
            bar.leadingAnchor.constraint(equalTo: spaceButton.trailingAnchor, constant: 8),
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

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarView is created in code") }

    /// Empty parts of the bar drag the window, like a normal title bar.
    override var mouseDownCanMoveWindow: Bool { true }

    func setColors(text: NSColor, secondary: NSColor, field: NSColor) {
        textColor = text
        secondaryColor = secondary
        fieldColor = field
        for button in [sidebarButton, paletteButton, newTabButton, settingsButton] { button.contentTintColor = secondary }
        // No box: icon and words in the quiet color, as Terax's "Search (⌘F)".
        // The filled field had its text off the button's center (2026-10-19).
        searchButton.contentTintColor = secondary
        searchButton.attributedTitle = NSAttributedString(string: " Buscar (⌘K)", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondary,
        ])
        spaceName = spaceTitle
    }

    private static func iconButton(_ icon: Icon, _ tip: String) -> NSButton {
        let button = NSButton(image: icon.image(size: 16), target: nil, action: nil)
        button.isBordered = false
        button.toolTip = tip
        button.setAccessibilityLabel(tip)
        return button
    }

    @objc private func toggleSidebar() { run("view.toggle-sidebar") }
    @objc private func openPalette() { run("palette.open") }
    @objc private func newTab() { run("tab.new") }
    @objc private func switchSpace() { run("space.switch") }
    @objc private func openSettings() { run("settings.open") }
}
