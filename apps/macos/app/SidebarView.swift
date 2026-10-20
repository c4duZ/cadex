import AppKit
import Icons
import Menus
import Strings

/// The sidebar: the explorer's tree or the Git view, switched by two tabs
/// at the bottom, "Arquivos" and "Git", as in Terax (they run the
/// explorer.focus and git.show commands). The owner compared the two
/// side by side on 2026-10-19: loose icons on top read as decoration.
final class SidebarView: NSView {
    enum Page { case files, git }

    private let files: NSView
    private let git: NSView
    private let filesTab: SidebarTab
    private let gitTab: SidebarTab
    private(set) var page: Page = .files
    private let run: (String) -> Void

    init(files: NSView, git: NSView, run: @escaping (String) -> Void) {
        self.files = files
        self.git = git
        self.run = run
        filesTab = SidebarTab(icon: .files, title: T("Files", "Arquivos"), tip: T("Files (⇧⌘E)", "Arquivos (⇧⌘E)"))
        gitTab = SidebarTab(icon: .gitBranch, title: "Git", tip: "Git (⇧⌘G)")
        super.init(frame: .zero)
        filesTab.onPress = { [weak self] in self?.run("explorer.focus") }
        gitTab.onPress = { [weak self] in self?.run("git.show") }
        let bar = NSStackView(views: [filesTab, gitTab])
        bar.distribution = .fillEqually
        bar.spacing = 4
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
        for v in [files, git, bar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for content in [files, git] {
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: topAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -4),
            ])
        }
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            bar.heightAnchor.constraint(equalToConstant: 26),
        ])
        show(.files)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarView is created in code") }

    func show(_ page: Page) {
        self.page = page
        files.isHidden = page != .files
        git.isHidden = page != .git
        filesTab.selected = page == .files
        gitTab.selected = page == .git
    }

    /// The theme's colors: text, quiet text, the chosen tab's fill and its icon.
    func setColors(text: NSColor, secondary: NSColor, fill: NSColor, accent: NSColor) {
        for tab in [filesTab, gitTab] { tab.colors = (text, secondary, fill, accent) }
    }
}

/// One of the two tabs: icon and label, filled when chosen.
private final class SidebarTab: NSView {
    var onPress: (() -> Void)?
    var selected = false { didSet { restyle() } }
    var colors: (text: NSColor, secondary: NSColor, fill: NSColor, accent: NSColor) = (.labelColor, .secondaryLabelColor, .quaternaryLabelColor, .controlAccentColor) {
        didSet { restyle() }
    }
    private let icon: NSImageView
    private let label: NSTextField

    init(icon: Icon, title: String, tip: String) {
        self.icon = NSImageView(image: icon.image(size: 13))
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        HoverTip.attach(tip, to: self)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let content = NSStackView(views: [self.icon, label])
        content.spacing = 5
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: centerXAnchor),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarTab is created in code") }

    override func mouseDown(with event: NSEvent) { onPress?() }
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }

    private func restyle() {
        layer?.backgroundColor = selected ? colors.fill.cgColor : nil
        label.textColor = selected ? colors.text : colors.secondary
        icon.contentTintColor = selected ? colors.accent : colors.secondary
    }
}
