import AppKit
import Explorer
import Inspector
import Sidebar
import StatusBar
import Tabs
import Terminal
import Themes
import UILooks

/// The window's content, laid out as: the title bar with the tabs,
/// a collapsible sidebar and the terminal area as rounded panels, and the
/// status bar at the bottom (docs/plans/3-window-and-theme.md, fase A).
final class WorkspaceView: NSView {
    /// The tree's width (components.sidebar.width).
    static var sidebarWidth: CGFloat { UILooks.pt(DesignTokens.Sidebar.width) }
    /// Between the columns and the center: none. The center runs from the tree's line to the
    /// panel's, and its 8 pt around the panes are the pane layout's (components.pane.outerPadding).
    static let gap: CGFloat = 0

    let titleBar: TitleBarView
    let statusBar = StatusBarView()
    /// The work's tree (plan 27 phase B): a column flush with the window's left edge, its own line
    /// on the right (components.sidebar), as the right panel is on the other side.
    let tree: WorkTreeView
    /// The right panel (plan 26 phase C): a column flush with the window's right edge, its own
    /// line on the left (components.inspector), not a rounded panel.
    let inspector: InspectorView
    private var inspectorWidth: NSLayoutConstraint!
    /// The center ends at the panel, or at the window's edge with it closed: the panel keeps its
    /// width hidden, since 0 pt could not hold its rows (review of 2026-11-17).
    private var contentToInspector: NSLayoutConstraint!
    private var contentToEdge: NSLayoutConstraint!
    private(set) var inspectorVisible = true
    /// The panel's width (inspector.width), dragged by its edge.
    private(set) var inspectorPoints = UILooks.pt(DesignTokens.Inspector.width)
    /// The sidebar was folded to make room for the panel in a narrow window: it comes back when
    /// the panel closes (docs/spec/inspector.md, "Janela estreita").
    private var sidebarFoldedForInspector = false
    /// Below this the center is too narrow for the sidebar and the panel side by side (the spec).
    static let narrowWindow: CGFloat = 1000
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

    init(explorer: ExplorerController, tree: WorkTreeView, inspector: InspectorView, run: @escaping (String) -> Void) {
        titleBar = TitleBarView(run: run)
        self.explorer = explorer
        self.tree = tree
        self.inspector = inspector
        super.init(frame: .zero)
        frost.blendingMode = .behindWindow
        frost.material = .underWindowBackground
        frost.state = .active
        frost.isHidden = true
        for view in [frost, titleBar, statusBar, tree, contentPanel, inspector] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let gap = Self.gap
        sidebarWidth = tree.widthAnchor.constraint(equalToConstant: Self.sidebarWidth)
        contentLeading = contentPanel.leadingAnchor.constraint(equalTo: tree.trailingAnchor, constant: gap)
        inspectorWidth = inspector.widthAnchor.constraint(equalToConstant: inspectorPoints)
        contentToInspector = contentPanel.trailingAnchor.constraint(equalTo: inspector.leadingAnchor, constant: -gap)
        contentToEdge = contentPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -gap)
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
            tree.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            tree.leadingAnchor.constraint(equalTo: leadingAnchor),
            tree.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            sidebarWidth,
            contentPanel.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            contentLeading,
            contentToInspector,
            contentPanel.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            inspector.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            inspector.trailingAnchor.constraint(equalTo: trailingAnchor),
            inspector.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            inspectorWidth,
        ])
        ThemeStore.shared.observe { [weak self] theme in self?.apply(theme) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkspaceView is created in code") }

    /// The frame's colors as this window last painted them: the palette is the app's, and each
    /// window repaints from its own, so a second window changes too.
    private var paintedWith = DesignTokens.themedColors()

    /// A space's tabs come into the window (docs/spec/projects.md).
    func show(_ tabs: TabsController) {
        hideHome()
        guard tabs.view !== tabsView else { return }
        tabsView?.removeFromSuperview()
        fill(contentPanel, with: tabs.view)
        tabsView = tabs.view
        titleBar.setTabBar(tabs.bar)
        if let tabBarStyle { tabs.bar.style = tabBarStyle }
    }

    /// The home screen in the center (plan 29; the Home mockup): over the tabs, the title bar
    /// without them, the right panel closed (it comes back with the tabs).
    private(set) weak var home: NSView?
    private var inspectorBeforeHome = false

    func showHome(_ view: NSView) {
        home?.removeFromSuperview()
        tabsView?.isHidden = true
        fill(contentPanel, with: view)
        home = view
        titleBar.setTabsHidden(true)
        if inspectorVisible {
            inspectorBeforeHome = true
            setInspector(visible: false)
        }
    }

    private var inspectorBeforeBoard: Bool?
    private weak var drawer: DrawerView?
    private var drawerHeight: NSLayoutConstraint?

    /// The terminal drawer over the center's bottom (the Drawer mockup), at its own height; nil
    /// takes it away.
    func showDrawer(_ next: DrawerView?) {
        if let next, next === drawer {
            drawerHeight?.constant = next.height
            return
        }
        drawer?.removeFromSuperview()
        drawer = next
        guard let next else { return }
        next.translatesAutoresizingMaskIntoConstraints = false
        addSubview(next, positioned: .above, relativeTo: contentPanel)
        let height = next.heightAnchor.constraint(equalToConstant: next.height)
        drawerHeight = height
        NSLayoutConstraint.activate([
            next.leadingAnchor.constraint(equalTo: contentPanel.leadingAnchor),
            next.trailingAnchor.constraint(equalTo: contentPanel.trailingAnchor),
            next.bottomAnchor.constraint(equalTo: contentPanel.bottomAnchor),
            height,
        ])
    }

    /// The board shows: the right panel closes, and comes back as it was when the board goes.
    func setBoardShown(_ shown: Bool) {
        if shown, inspectorBeforeBoard == nil {
            inspectorBeforeBoard = inspectorVisible
            if inspectorVisible { setInspector(visible: false) }
        } else if !shown, let before = inspectorBeforeBoard {
            inspectorBeforeBoard = nil
            if before, !inspectorVisible { setInspector(visible: true) }
        }
    }

    func hideHome() {
        guard let home else { return }
        home.removeFromSuperview()
        self.home = nil
        tabsView?.isHidden = false
        titleBar.setTabsHidden(false)
        if inspectorBeforeHome {
            inspectorBeforeHome = false
            setInspector(visible: true)
        }
    }

    /// Shows the work's tree (sidebar.show).
    func showTree() {
        if !sidebarVisible { toggleSidebar() }
    }

    /// Opens the right panel on a tab (git.show, explorer.focus, git.show-history, memory.show).
    func showInspector(_ tab: String) {
        if !inspectorVisible { setInspector(visible: true) }
        inspector.show(tab)
    }

    /// inspector.toggle and the saved inspector.visible. Closed, the panel is hidden, so no tab of
    /// it reads (docs/spec/inspector.md).
    /// `launching`: the saved state applied when the window opens, which folds the sidebar the
    /// same way in a narrow window (review of 2026-11-17: only a later open did).
    func setInspector(visible: Bool, launching: Bool = false) {
        let opening = visible && (!inspectorVisible || launching)
        let closing = !visible && inspectorVisible
        inspectorVisible = visible
        if opening, sidebarVisible, (window?.frame.width ?? .infinity) < Self.narrowWindow {
            setSidebar(visible: false)
            sidebarFoldedForInspector = true
        } else if closing, sidebarFoldedForInspector {
            setSidebar(visible: true)
            sidebarFoldedForInspector = false
        }
        inspector.isHidden = !visible
        contentToInspector.isActive = visible
        contentToEdge.isActive = !visible
        titleBar.setInspectorOpen(visible)
        // Opened again: its tab is announced, so a page that went while closed (History after a
        // folder change) comes back (review of 2026-11-17).
        if opening, let tab = inspector.tab { inspector.show(tab) }
    }

    /// The panel's width, within the settings' range and what the window leaves after the sidebar
    /// and a center of `minCenter` (a 640 pt panel in a 700 pt window squeezed the terminals to
    /// nothing: review of 2026-11-17).
    func setInspector(width: CGFloat) {
        var room = CGFloat.infinity
        if let window {
            room = window.frame.width - (sidebarVisible ? Self.sidebarWidth + Self.gap : 0) - Self.minCenter - Self.gap * 2
        }
        inspectorPoints = max(min(width, room), UILooks.pt(DesignTokens.Inspector.width) / 2)
        inspectorWidth.constant = inspectorPoints
    }

    /// The least the terminals keep beside the panel.
    static let minCenter: CGFloat = 320

    /// The view.toggle-sidebar command.
    func toggleSidebar() {
        // The owner chose: the panel no longer brings the sidebar back when it closes.
        sidebarFoldedForInspector = false
        setSidebar(visible: !sidebarVisible)
    }

    private func setSidebar(visible: Bool) {
        sidebarVisible = visible
        tree.isHidden = !sidebarVisible
        sidebarWidth.constant = sidebarVisible ? Self.sidebarWidth : 0
        // The center keeps its margin with the tree folded (it sat flush against the edge).
        contentLeading.constant = Self.gap
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

    /// The active tab's or space's color, over the accent (app/WorkColors.swift).
    var workColor: WorkColor? {
        didSet { if workColor != oldValue { apply(ThemeStore.shared.current) } }
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
        var ui = theme.interface
        if let workColor {
            ui.accent = workColor.rgb(in: theme)
            ui.tabActive = ui.chrome.mixed(ui.accent, 0.22)
        }
        // The chrome color goes on the window, not on this view's layer: a
        // filled layer here covered the close, minimize and zoom buttons in
        // the transparent title bar (2026-10-19). With vibrancy the window is
        // clear and the frost shows the desktop through, tinted by the chrome.
        frost.isHidden = !vibrancy
        window?.isOpaque = !vibrancy
        window?.backgroundColor = vibrancy ? ui.chrome.color(alpha: 0.55) : ui.chrome.nsColor
        raiseWindowButtons()
        window?.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
        // The center's ground is the window's (the Main mockup): the panes are the boxes on it.
        contentPanel.setColors(fill: DesignTokens.Color.bgWindow, border: .clear)
        explorer.style = .init(text: ui.text.nsColor, secondaryText: ui.secondaryText.nsColor, accent: ui.accent.nsColor)
        let style = TabBarView.Style(
            activeFill: ui.tabActive.nsColor, hoverFill: ui.tabActive.color(alpha: 0.5),
            text: ui.textOnTabActive.nsColor, secondaryText: ui.secondaryText.nsColor, accent: ui.accent.nsColor)
        tabBarStyle = style
        titleBar.tabBar?.style = style
        // The new frame in the theme's colors (owner, 2026-11-17: every theme looked like Cadex
        // Night): the tokens follow its frame color and text; Cadex Night keeps the mockups'.
        let mockups = theme.interface == Theme.cadexNight.interface
        DesignTokens.applyTheme(chrome: mockups ? nil : theme.interface.chrome.nsColor, text: mockups ? nil : theme.interface.text.nsColor)
        DesignTokens.repaint(self, from: paintedWith)
        paintedWith = DesignTokens.themedColors()
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
