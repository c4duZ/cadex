import AppKit
import Icons
import Tabs

/// The title bar, drawn by the app inside the window's title area as in
/// Terax: room for the window buttons, sidebar and palette buttons, the
/// tabs, "+", and on the right the search field. Every button runs a
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
    private var textColor = NSColor.labelColor
    private var secondaryColor = NSColor.secondaryLabelColor
    private var fieldColor = NSColor.controlBackgroundColor

    init(tabBar: TabBarView, run: @escaping (String) -> Void) {
        self.run = run
        sidebarButton = Self.iconButton(.sidebar, "Painel lateral")
        paletteButton = Self.iconButton(.command, "Paleta de comandos (⌘K)")
        newTabButton = Self.iconButton(.plus, "Nova aba (⌘T)")
        super.init(frame: .zero)
        sidebarButton.target = self
        sidebarButton.action = #selector(toggleSidebar)
        paletteButton.target = self
        paletteButton.action = #selector(openPalette)
        newTabButton.target = self
        newTabButton.action = #selector(newTab)
        searchButton.isBordered = false
        searchButton.image = Icon.magnifyingGlass.image(size: 13)
        searchButton.imagePosition = .imageLeading
        searchButton.imageHugsTitle = true
        searchButton.target = self
        searchButton.action = #selector(openPalette)
        searchButton.wantsLayer = true
        searchButton.layer?.cornerRadius = 6

        let views: [NSView] = [sidebarButton, paletteButton, tabBar, newTabButton, searchButton]
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            sidebarButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.windowButtonsWidth),
            paletteButton.leadingAnchor.constraint(equalTo: sidebarButton.trailingAnchor, constant: 6),
            tabBar.leadingAnchor.constraint(equalTo: paletteButton.trailingAnchor, constant: 12),
            tabBar.heightAnchor.constraint(equalToConstant: 30),
            newTabButton.leadingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: 4),
            searchButton.leadingAnchor.constraint(greaterThanOrEqualTo: newTabButton.trailingAnchor, constant: 12),
            searchButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            searchButton.widthAnchor.constraint(equalToConstant: 200),
            searchButton.heightAnchor.constraint(equalToConstant: 26),
        ] + views.map { $0.centerYAnchor.constraint(equalTo: centerYAnchor) })
        // The tab bar is as wide as its tabs and gives way first when the
        // window is narrow.
        tabBar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tabBar.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarView is created in code") }

    /// Empty parts of the bar drag the window, like a normal title bar.
    override var mouseDownCanMoveWindow: Bool { true }

    func setColors(text: NSColor, secondary: NSColor, field: NSColor) {
        textColor = text
        secondaryColor = secondary
        fieldColor = field
        for button in [sidebarButton, paletteButton, newTabButton] { button.contentTintColor = secondary }
        searchButton.layer?.backgroundColor = field.cgColor
        searchButton.contentTintColor = secondary
        let title = NSMutableAttributedString(string: " Buscar", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondary,
        ])
        title.append(NSAttributedString(string: "   ⌘K", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: secondary.withAlphaComponent(0.7),
        ]))
        searchButton.attributedTitle = title
        searchButton.alignment = .left
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
}
