import AppKit
import Explorer
import SourceControl
import StatusBar
import Tabs
import Terminal
import Themes

/// The window's content, laid out like Terax: the title bar with the tabs,
/// a collapsible sidebar and the terminal area as rounded panels, and the
/// status bar at the bottom (docs/plans/3-window-and-theme.md, fase A).
final class WorkspaceView: NSView {
    static let sidebarWidth: CGFloat = 240
    /// Space around and between the panels, as in Terax.
    static let gap: CGFloat = 6

    let titleBar: TitleBarView
    let statusBar = StatusBarView()
    private let sidebarPanel = PanelView()
    private let sidebar: SidebarView
    private let explorer: ExplorerController
    private let contentPanel = PanelView()
    private var sidebarWidth: NSLayoutConstraint!
    private var contentLeading: NSLayoutConstraint!
    private(set) var sidebarVisible = true
    private let backdrop = WindowBackdrop()
    /// The frosted frame, shown only with vibrancy on.
    private let frost = NSVisualEffectView()
    private var backgroundImage: WindowBackdrop.Image?
    private var vibrancy = false
    private var tabBarStyle: TabBarView.Style?
    /// The shown space's tabs in the content panel.
    private weak var tabsView: NSView?

    init(explorer: ExplorerController, git: SourceControlController, run: @escaping (String) -> Void) {
        titleBar = TitleBarView(run: run)
        self.explorer = explorer
        sidebar = SidebarView(files: explorer.view, git: git.view, run: run)
        super.init(frame: .zero)
        frost.blendingMode = .behindWindow
        frost.material = .underWindowBackground
        frost.state = .active
        frost.isHidden = true
        for view in [frost, titleBar, statusBar, sidebarPanel, contentPanel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        fill(sidebarPanel, with: sidebar)

        let gap = Self.gap
        sidebarWidth = sidebarPanel.widthAnchor.constraint(equalToConstant: Self.sidebarWidth)
        contentLeading = contentPanel.leadingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: gap)
        NSLayoutConstraint.activate([
            frost.topAnchor.constraint(equalTo: topAnchor),
            frost.bottomAnchor.constraint(equalTo: bottomAnchor),
            frost.leadingAnchor.constraint(equalTo: leadingAnchor),
            frost.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBar.topAnchor.constraint(equalTo: topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: TitleBarView.height),
            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: StatusBarView.height),
            sidebarPanel.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            sidebarPanel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: gap),
            sidebarPanel.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebarWidth,
            contentPanel.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            contentLeading,
            contentPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -gap),
            contentPanel.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
        ])
        ThemeStore.shared.observe { [weak self] theme in self?.apply(theme) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkspaceView is created in code") }

    /// A space's tabs come into the window (docs/spec/spaces.md).
    func show(_ tabs: TabsController) {
        guard tabs.view !== tabsView else { return }
        tabsView?.removeFromSuperview()
        fill(contentPanel, with: tabs.view)
        tabsView = tabs.view
        titleBar.setTabBar(tabs.bar)
        if let tabBarStyle { tabs.bar.style = tabBarStyle }
    }

    /// Shows the sidebar on a page (explorer.focus, git.show).
    func showSidebar(_ page: SidebarView.Page = .files) {
        if !sidebarVisible { toggleSidebar() }
        sidebar.show(page)
    }

    /// The view.toggle-sidebar command.
    func toggleSidebar() {
        sidebarVisible.toggle()
        sidebarPanel.isHidden = !sidebarVisible
        sidebarWidth.constant = sidebarVisible ? Self.sidebarWidth : 0
        contentLeading.constant = sidebarVisible ? Self.gap : 0
    }

    private func fill(_ panel: NSView, with view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: panel.topAnchor),
            view.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
        ])
    }

    /// The background image and vibrancy from settings.
    func setLooks(image: WindowBackdrop.Image?, vibrancy: Bool) {
        backgroundImage = image
        self.vibrancy = vibrancy
        apply(ThemeStore.shared.current)
    }

    private func apply(_ theme: Theme) {
        let term = theme.terminal
        let picture = backgroundImage.flatMap { backdrop.image(for: $0) }
        contentPanel.layer?.contents = picture
        contentPanel.layer?.contentsGravity = .resizeAspectFill
        let colors = TerminalAppearance(
            background: term.background.value, foreground: term.foreground.value, cursor: term.cursor.value,
            selection: term.selection.value, ansi: term.ansi.map(\.value),
            backgroundAlpha: picture == nil ? 1 : 1 - (backgroundImage?.opacity ?? 0))
        if TerminalAppearance.current != colors { TerminalAppearance.current = colors }
        EditorLooks.refresh()
        let ui = theme.interface
        // The chrome color goes on the window, not on this view's layer: a
        // filled layer here covered the close, minimize and zoom buttons in
        // the transparent title bar (2026-10-19). With vibrancy the window is
        // clear and the frost shows the desktop through, tinted by the chrome.
        frost.isHidden = !vibrancy
        window?.isOpaque = !vibrancy
        window?.backgroundColor = vibrancy ? ui.chrome.color(alpha: 0.55) : ui.chrome.nsColor
        raiseWindowButtons()
        window?.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
        sidebarPanel.setColors(fill: ui.panel.nsColor, border: ui.panelBorder.nsColor)
        contentPanel.setColors(fill: theme.terminal.background.nsColor, border: ui.panelBorder.nsColor)
        explorer.style = .init(text: ui.text.nsColor, secondaryText: ui.secondaryText.nsColor, accent: ui.accent.nsColor)
        titleBar.setColors(text: ui.text.nsColor, secondary: ui.secondaryText.nsColor, field: ui.field.nsColor)
        sidebar.setColors(text: ui.text.nsColor, secondary: ui.secondaryText.nsColor, fill: ui.tabActive.nsColor, accent: ui.accent.nsColor)
        statusBar.style = .init(text: ui.text.nsColor, secondaryText: ui.secondaryText.nsColor)
        let style = TabBarView.Style(
            activeFill: ui.tabActive.nsColor, hoverFill: ui.tabActive.color(alpha: 0.5),
            text: ui.text.nsColor, secondaryText: ui.secondaryText.nsColor, accent: ui.accent.nsColor)
        tabBarStyle = style
        titleBar.tabBar?.style = style
    }

    /// The frost is a layer over the title area and hid the close, minimize
    /// and zoom buttons (2026-10-19). Their container sits in the window's
    /// frame view next to this one; putting it back on top shows them.
    private func raiseWindowButtons() {
        guard let container = window?.standardWindowButton(.closeButton)?.superview?.superview,
              let frameView = container.superview else { return }
        frameView.addSubview(container, positioned: .above, relativeTo: nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply(ThemeStore.shared.current)
    }
}
