import AppKit
import StatusBar
import Tabs
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
    private let sidebar = SidebarView()
    private let contentPanel = PanelView()
    private var sidebarWidth: NSLayoutConstraint!
    private var contentLeading: NSLayoutConstraint!
    private(set) var sidebarVisible = true

    init(tabs: TabsController, run: @escaping (String) -> Void) {
        titleBar = TitleBarView(tabBar: tabs.bar, run: run)
        super.init(frame: .zero)
        for view in [titleBar, statusBar, sidebarPanel, contentPanel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        fill(sidebarPanel, with: sidebar)
        fill(contentPanel, with: tabs.view)

        let gap = Self.gap
        sidebarWidth = sidebarPanel.widthAnchor.constraint(equalToConstant: Self.sidebarWidth)
        contentLeading = contentPanel.leadingAnchor.constraint(equalTo: sidebarPanel.trailingAnchor, constant: gap)
        NSLayoutConstraint.activate([
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

    private func apply(_ theme: Theme) {
        let ui = theme.interface
        // The chrome color goes on the window, not on this view's layer: a
        // filled layer here covered the close, minimize and zoom buttons in
        // the transparent title bar (2026-10-19).
        window?.backgroundColor = ui.chrome.nsColor
        window?.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
        sidebarPanel.setColors(fill: ui.panel.nsColor, border: ui.panelBorder.nsColor)
        contentPanel.setColors(fill: theme.terminal.background.nsColor, border: ui.panelBorder.nsColor)
        sidebar.setColors(secondary: ui.secondaryText.nsColor)
        titleBar.setColors(text: ui.text.nsColor, secondary: ui.secondaryText.nsColor, field: ui.field.nsColor)
        statusBar.style = .init(text: ui.text.nsColor, secondaryText: ui.secondaryText.nsColor)
        (titleBar.subviews.first { $0 is TabBarView } as? TabBarView)?.style = .init(
            activeFill: ui.tabActive.nsColor, hoverFill: ui.tabActive.color(alpha: 0.5),
            text: ui.text.nsColor, secondaryText: ui.secondaryText.nsColor)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply(ThemeStore.shared.current)
    }
}
