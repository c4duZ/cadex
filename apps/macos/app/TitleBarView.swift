import AppKit
import Icons
import Tabs

/// The title bar: the window buttons, one group on the left with the
/// sidebar, the search (the palette, ⌘K) and the spaces, then the tabs,
/// "+", and the settings on the right. Every button runs a command by id
/// (ADR 0005).
///
/// The owner asked for the left icons together and for the tabs to lead
/// (2026-10-19): the palette button and the wide search field opened the
/// same palette, so they became one button that says ⌘K, and the tabs take
/// the room the field used. One height (26 pt) for every control, one icon
/// size per role, gaps on a 4/8/12 pt scale.
final class TitleBarView: NSView {
    /// Matches the title area of a window with a unified compact toolbar,
    /// where macOS centers the window buttons.
    static let height: CGFloat = 38
    /// Where the close, minimize and zoom buttons end, and the one gap used
    /// before and after the group: 6 and 12 pt there read as crooked.
    // Measured in a capture: the zoom button ends at 72 pt (2026-10-19).
    private static let windowButtonsEnd: CGFloat = 72
    private static let groupGap: CGFloat = 10
    /// The group's leading edge: after the window buttons, or at the edge in
    /// full screen, where macOS hides them (owner, 2026-10-19).
    private var groupLeading: NSLayoutConstraint!

    private let run: (String) -> Void
    private let sidebarButton = TitleBarButton(icon: .sidebar, tip: "Painel lateral (⌘B)")
    /// The palette is the search for everything (files, commands, ⌘K).
    private let searchButton = TitleBarButton(icon: .magnifyingGlass, title: "⌘K", tip: "Buscar arquivos e comandos (⌘K)")
    /// The space's name; clicking it switches spaces (docs/spec/spaces.md).
    private let spaceButton = TitleBarButton(icon: .stack, title: "", tip: "Trocar de space (⇧⌘S)")
    /// The three as one group on a light fill.
    private let group = NSView()
    private let newTabButton = TitleBarButton(icon: .plus, tip: "Nova aba (⌘T)")
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
        searchButton.onPress = { [weak self] in self?.run("palette.open") }
        spaceButton.onPress = { [weak self] in self?.run("space.switch") }
        newTabButton.onPress = { [weak self] in self?.run("tab.new") }
        settingsButton.onPress = { [weak self] in self?.run("settings.open") }

        group.wantsLayer = true
        group.layer?.cornerRadius = 8
        let inside = NSStackView(views: [sidebarButton, searchButton, spaceButton])
        inside.spacing = 0
        // 1 pt around 26 pt buttons: the group is 28 pt tall, as the tabs.
        inside.edgeInsets = NSEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        inside.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(inside)
        NSLayoutConstraint.activate([
            inside.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            inside.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            inside.topAnchor.constraint(equalTo: group.topAnchor),
            inside.bottomAnchor.constraint(equalTo: group.bottomAnchor),
        ])
        spaceButton.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let views: [NSView] = [group, newTabButton, settingsButton]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        groupLeading = group.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.windowButtonsEnd + Self.groupGap)
        NSLayoutConstraint.activate([
            groupLeading,
            spaceButton.widthAnchor.constraint(lessThanOrEqualToConstant: 160),
            settingsButton.leadingAnchor.constraint(greaterThanOrEqualTo: newTabButton.trailingAnchor, constant: 12),
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ] + views.map { $0.centerYAnchor.constraint(equalTo: centerYAnchor) })
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

    /// Puts a space's tab bar between the group and "+".
    func setTabBar(_ bar: TabBarView) {
        guard bar !== tabBar else { return }
        tabBar?.removeFromSuperview()
        NSLayoutConstraint.deactivate(tabBarConstraints)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        tabBarConstraints = [
            bar.leadingAnchor.constraint(equalTo: group.trailingAnchor, constant: Self.groupGap),
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self)
        guard let window else { return }
        center.addObserver(self, selector: #selector(fullScreenChanged), name: NSWindow.didEnterFullScreenNotification, object: window)
        center.addObserver(self, selector: #selector(fullScreenChanged), name: NSWindow.didExitFullScreenNotification, object: window)
        fullScreenChanged()
    }

    @objc private func fullScreenChanged() {
        let full = window?.styleMask.contains(.fullScreen) == true
        groupLeading.constant = full ? 8 : Self.windowButtonsEnd + Self.groupGap
    }

    /// Empty parts of the bar drag the window, like a normal title bar.
    override var mouseDownCanMoveWindow: Bool { true }

    func setColors(text: NSColor, secondary: NSColor, field: NSColor) {
        textColor = text
        secondaryColor = secondary
        // The bar's own controls in near-full contrast: in the quiet gray
        // they disappeared next to the tabs (owner, 2026-10-19).
        let strong = text.withAlphaComponent(0.78)
        for button in [sidebarButton, searchButton, spaceButton, newTabButton, settingsButton] { button.colors = (text, strong) }
        group.layer?.backgroundColor = text.withAlphaComponent(0.06).cgColor
        setSpace(name: spaceTitle, count: spaceCount)
    }
}
