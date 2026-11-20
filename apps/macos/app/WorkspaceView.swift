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
    /// Nothing at the left edge with the sidebar closed (ADR 0039; the narrow strip comes in plan 38 G).
    static let railWidth: CGFloat = 0
    /// Between the columns and the center: none. The center runs from the tree's line to the
    /// panel's, and its 8 pt around the panes are the pane layout's (components.pane.outerPadding).
    static let gap: CGFloat = 0

    let titleBar: TitleBarView
    let statusBar = StatusBarView()
    /// The sidebar (docs/adr/0039-sidebar-with-work-and-files.md, plan 38): flush with the window's
    /// left edge; ⌘B shows and hides it (`inspectorVisible`, the old name of the left column).
    let sidebar: WorkSidebarView
    /// The narrow window's strip (plan 38 G): the requests' box, the projects' squares, Files and the
    /// board; 0 pt wide and hidden in a wide window.
    let rail: RailView
    private var stripWidth: NSLayoutConstraint!
    private var sidebarAtEdge: NSLayoutConstraint!
    private var sidebarAtRail: NSLayoutConstraint!
    /// Under `narrowBelow`: the strip shows, and the sidebar opens over the center.
    private(set) var isNarrow = false
    /// Files and Changes, with their header and foot: the sidebar's Files view (it was the side
    /// column, and the right panel before ADR 0038).
    let inspector: InspectorView
    private var inspectorWidth: NSLayoutConstraint!
    /// The center starts at the sidebar, or at the window's edge with it closed: the sidebar keeps
    /// its width hidden, since 0 pt could not hold its rows (review of 2026-11-17).
    private var contentToInspector: NSLayoutConstraint!
    private var contentToRail: NSLayoutConstraint!
    private(set) var inspectorVisible = true
    /// The column's width (inspector.width), dragged by its edge.
    private(set) var inspectorPoints = UILooks.pt(DesignTokens.WorkSidebar.width)
    private let explorer: ExplorerController
    private let contentPanel = PanelView()
    private let backdrop = WindowBackdrop()
    /// The frosted frame, shown only with vibrancy on.
    private let frost = NSVisualEffectView()
    /// A translucent window's one tint, in the theme's ground color at the window's opacity,
    /// over the frost and under everything else (the grounds above it are see-through).
    private let glass = NSView()
    private var looks = WindowBackdrop.Looks()
    private var tabBarStyle: TabBarView.Style?
    /// The shown project's tabs in the content panel.
    private weak var tabsView: NSView?

    init(explorer: ExplorerController, sidebar: WorkSidebarView, rail: RailView, inspector: InspectorView, run: @escaping (String) -> Void) {
        titleBar = TitleBarView(run: run)
        self.explorer = explorer
        self.sidebar = sidebar
        self.rail = rail
        self.inspector = inspector
        sidebar.setFiles(inspector)
        sidebar.setFilesActions(inspector.actions)
        super.init(frame: .zero)
        frost.blendingMode = .behindWindow
        frost.material = .underWindowBackground
        frost.state = .active
        frost.isHidden = true
        glass.wantsLayer = true
        glass.isHidden = true
        rail.isHidden = true
        // The sidebar after the center, so it can lie over it in a narrow window.
        for view in [frost, glass, titleBar, statusBar, rail, contentPanel, sidebar] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let gap = Self.gap
        inspectorWidth = sidebar.widthAnchor.constraint(equalToConstant: inspectorPoints)
        contentToInspector = contentPanel.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: gap)
        contentToRail = contentPanel.leadingAnchor.constraint(equalTo: rail.trailingAnchor, constant: gap)
        stripWidth = rail.widthAnchor.constraint(equalToConstant: 0)
        sidebarAtEdge = sidebar.leadingAnchor.constraint(equalTo: leadingAnchor)
        sidebarAtRail = sidebar.leadingAnchor.constraint(equalTo: rail.trailingAnchor)
        NSLayoutConstraint.activate([
            frost.topAnchor.constraint(equalTo: topAnchor),
            frost.bottomAnchor.constraint(equalTo: bottomAnchor),
            frost.leadingAnchor.constraint(equalTo: leadingAnchor),
            frost.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBar.topAnchor.constraint(equalTo: topAnchor),
            titleBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleBar.heightAnchor.constraint(equalToConstant: TitleBarView.height),
            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: StatusBarView.height),
            sidebar.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            sidebarAtEdge,
            sidebar.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            rail.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            stripWidth,
            inspectorWidth,
            contentPanel.topAnchor.constraint(equalTo: titleBar.bottomAnchor),
            contentToInspector,
            contentPanel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -gap),
            contentPanel.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
        ])
        ThemeStore.shared.observe { [weak self] theme in self?.apply(theme) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkspaceView is created in code") }

    /// The frame's colors as this window last painted them: the palette is the app's, and each
    /// window repaints from its own, so a second window changes too.
    private var paintedWith = DesignTokens.themedColors()

    /// A project's tabs come into the window (docs/spec/projects.md).
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
    /// without them. The sidebar stays: with nothing open it lists the recents (plan 38 G).
    private(set) weak var home: NSView?

    func showHome(_ view: NSView) {
        home?.removeFromSuperview()
        tabsView?.isHidden = true
        fill(contentPanel, with: view)
        home = view
        titleBar.setTabsHidden(true)
    }

    /// The column closed because the window got narrow (ADR 0038): it comes back when the window
    /// is wide again, unless the owner opened or closed it meanwhile.
    private var closedByNarrow = false
    /// Below this the side column closes and the rail stays (ADR 0038: under 1000 pt, the terminals
    /// keep the room).
    static let narrowBelow: CGFloat = 1000

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitColumn(to: newSize.width)
    }

    /// A narrow window shows the strip in place of the sidebar, and gives the sidebar back when it
    /// widens (ADR 0039).
    func fitColumn(to width: CGFloat) {
        guard width > 0 else { return }
        // Opened by hand while already narrow, it stays (over the center); getting narrow closes it.
        let wasNarrow = isNarrow
        setNarrow(width < Self.narrowBelow)
        if width < Self.narrowBelow, inspectorVisible, !wasNarrow {
            setInspector(visible: false)
            closedByNarrow = true
        } else if width >= Self.narrowBelow, closedByNarrow {
            setInspector(visible: true)
        }
    }

    private func setNarrow(_ narrow: Bool) {
        guard narrow != isNarrow else { return }
        isNarrow = narrow
        rail.isHidden = !narrow
        stripWidth.constant = narrow ? UILooks.pt(DesignTokens.Rail.width) : 0
        statusBar.compact = narrow
        layoutSidebar()
    }

    /// Where the sidebar sits: at the edge pushing the center, or over the center after the strip.
    private func layoutSidebar() {
        sidebarAtEdge.isActive = !isNarrow
        sidebarAtRail.isActive = isNarrow
        contentToInspector.isActive = inspectorVisible && !isNarrow
        contentToRail.isActive = !(inspectorVisible && !isNarrow)
    }
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

    func hideHome() {
        guard let home else { return }
        home.removeFromSuperview()
        self.home = nil
        tabsView?.isHidden = false
        titleBar.setTabsHidden(false)
    }

    /// sidebar.show (⇧⌘J): the side column comes up (the tree it showed left with ADR 0038).
    func showTree() {
        if !inspectorVisible { setInspector(visible: true) }
    }

    /// Opens the side column on a page (git.show, explorer.focus, git.show-history, memory.show).
    func showInspector(_ tab: String) {
        if !inspectorVisible { setInspector(visible: true) }
        sidebar.setMode(.files)
        inspector.show(tab)
    }

    /// The sidebar's Work view (its switch, ⇧⌘1).
    func showWork() {
        if !inspectorVisible { setInspector(visible: true) }
        sidebar.setMode(.work)
    }

    /// ⌘B (view.toggle-sidebar) and the saved inspector.visible. Closed, the column is hidden, so no
    /// page of it reads (docs/spec/inspector.md); the rail stays (ADR 0038).
    /// `launching`: the saved state applied when the window opens.
    func setInspector(visible: Bool, launching: Bool = false) {
        let opening = visible && (!inspectorVisible || launching)
        closedByNarrow = false
        inspectorVisible = visible
        sidebar.isHidden = !visible
        layoutSidebar()
        titleBar.setInspectorOpen(visible)
        onSidebarShown?(visible)
        // Opened again: its page is announced, so a page that went while closed (History after a
        // folder change) comes back (review of 2026-11-17).
        if opening, let tab = inspector.tab { inspector.show(tab) }
    }

    /// The sidebar showed or hid (⌘B, a narrow window): the top bar's needs-you pill follows.
    var onSidebarShown: ((Bool) -> Void)?

    /// The column's width, within the settings' range and what the window leaves after the rail
    /// and a center of `minCenter` (a 640 pt panel in a 700 pt window squeezed the terminals to
    /// nothing: review of 2026-11-17).
    func setInspector(width: CGFloat) {
        var room = CGFloat.infinity
        if let window {
            room = window.frame.width - Self.railWidth - Self.minCenter - Self.gap * 2
        }
        inspectorPoints = max(min(width, room), UILooks.pt(DesignTokens.Inspector.width) / 2)
        inspectorWidth.constant = inspectorPoints
    }

    /// The least the terminals keep beside the column.
    static let minCenter: CGFloat = 320

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

    /// The background image, vibrancy and the window's opacity from settings.
    func setLooks(_ looks: WindowBackdrop.Looks) {
        self.looks = looks
        apply(ThemeStore.shared.current)
    }

    private func apply(_ theme: Theme) {
        let term = theme.terminal
        let picture = looks.image.flatMap { backdrop.image(for: $0) }
        contentPanel.layer?.contents = picture
        contentPanel.layer?.contentsGravity = .resizeAspectFill
        let colors = TerminalAppearance(
            background: term.background.value, foreground: term.foreground.value, cursor: term.cursor.value,
            selection: term.selection.value, ansi: term.ansi.map(\.value),
            // A translucent window: the terminal's own ground is clear, the glass shows under it.
            backgroundAlpha: looks.translucent ? 0 : picture == nil ? 1 : 1 - (looks.image?.opacity ?? 0))
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
        // Translucent (appearance.windowOpacity), the window is clear and one tint at that opacity
        // lies under the see-through grounds (DesignTokens.applyTheme glass).
        // Always frosted when translucent: a sharp wallpaper through a thin tint fought the text
        // (the owner's green illustration, 2026-11-18); blurred it is color under it, as in Orca.
        let vibrancy = looks.vibrancy, see = vibrancy || looks.translucent
        Glass.set(opacity: looks.translucent ? looks.opacity : nil)
        frost.isHidden = !see
        glass.isHidden = !looks.translucent
        glass.layer?.backgroundColor = ui.chrome.color(alpha: looks.opacity).cgColor
        window?.isOpaque = !see
        window?.backgroundColor = looks.translucent ? .clear : vibrancy ? ui.chrome.color(alpha: 0.55) : ui.chrome.nsColor
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
        DesignTokens.applyTheme(chrome: mockups ? nil : theme.interface.chrome.nsColor, text: mockups ? nil : theme.interface.text.nsColor,
                                glass: looks.translucent)
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
