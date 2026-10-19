import AppKit
import Icons

/// The sidebar: the explorer's tree or the Git view, switched by two icon
/// buttons on top (they run the sidebar.files and sidebar.git commands).
final class SidebarView: NSView {
    enum Page { case files, git }

    private let files: NSView
    private let git: NSView
    private let filesButton: NSButton
    private let gitButton: NSButton
    private(set) var page: Page = .files
    private let run: (String) -> Void

    init(files: NSView, git: NSView, run: @escaping (String) -> Void) {
        self.files = files
        self.git = git
        self.run = run
        filesButton = Self.button(.files, "Arquivos (⇧⌘E)")
        gitButton = Self.button(.gitBranch, "Git (⇧⌘G)")
        super.init(frame: .zero)
        filesButton.target = self
        filesButton.action = #selector(filesPressed)
        gitButton.target = self
        gitButton.action = #selector(gitPressed)
        let bar = NSStackView(views: [filesButton, gitButton, NSView()])
        bar.spacing = 2
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 0, right: 8)
        for v in [bar, files, git] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for content in [files, git] {
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: bar.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
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
        filesButton.contentTintColor = page == .files ? .controlAccentColor : .secondaryLabelColor
        gitButton.contentTintColor = page == .git ? .controlAccentColor : .secondaryLabelColor
    }

    private static func button(_ icon: Icon, _ tip: String) -> NSButton {
        let b = NSButton(image: icon.image(size: 15), target: nil, action: nil)
        b.isBordered = false
        b.toolTip = tip
        b.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return b
    }

    @objc private func filesPressed() { run("explorer.focus") }
    @objc private func gitPressed() { run("git.show") }
}
