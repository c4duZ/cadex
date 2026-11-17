import AppKit
import UILooks
import Icons
import Menus
import Strings
import Tabs

/// The title bar of the new frame (docs/adr/0035-work-frame.md; screens.md, TitleBar;
/// components.titleBar): the window buttons, the search (the palette, ⌘K), where you are
/// ("project › task"), the tabs of what is open and "+", and on the right the bell. Every
/// control runs a command by id (ADR 0005); the sidebar, the space and the settings left the bar
/// (⌘B, ⇧⌘S and ⌘, in the palette, the shortcuts and the menu).
final class TitleBarView: NSView {
    typealias Look = DesignTokens.TitleBar
    /// Zoomed but never compact: macOS places the window buttons itself (plan 15, phase D).
    static var height: CGFloat { UILooks.pt(Look.height) }
    /// Where the close, minimize and zoom buttons end, measured in a capture (2026-10-19).
    private static let windowButtonsEnd: CGFloat = 68 // token-exempt: where the mockup's window buttons end
    /// The window buttons' centers in the TitleBar mockup: 12 pt circles, 8 apart, 16 in. Where
    /// macOS put them they sat 2.5 pt right, and the search with them (measured 2026-11-17).
    private static let windowButtonMids: [CGFloat] = [22, 42, 62] // token-exempt: macOS's own buttons
    private var searchLeading: NSLayoutConstraint!

    private let run: (String) -> Void
    private let search = TitleBarSearch()
    /// "cadex › orchestration-e": the project, then the task when one is selected.
    private let location = NSTextField(labelWithString: "")
    private let newTabButton = TitleBarButton(
        icon: .plus, tip: T("Open a terminal, file, preview or git graph", "Abrir terminal, arquivo, preview ou grafo do git"), kind: .add)
    /// The bell: the requests waiting for you, its count on the badge (docs/spec/agents.md).
    private let bellButton = TitleBarButton(icon: .bell, tip: T("Needs you", "Precisa de você"))
    /// The right panel's button (inspector.toggle), lit while the panel is open.
    private let panelButton = TitleBarButton(icon: .sidebarSimple, tip: T("Right panel", "Painel da direita"), mirrored: true)
    private let trailing = NSStackView()
    /// The line under the bar.
    private let hairline = NSView()
    /// The shown project's tabs; swapped when the project changes.
    private(set) var tabBar: TabBarView?
    private var tabBarConstraints: [NSLayoutConstraint] = []

    /// The "+" menu (the openers, built by the app); without it, "+" is a new tab.
    var newMenu: (() -> [MenuEntry])?

    init(run: @escaping (String) -> Void) {
        self.run = run
        super.init(frame: .zero)
        search.onPress = { [weak self] in self?.run("palette.open") }
        newTabButton.onPress = { [weak self] in self?.showNewMenu() }
        bellButton.onPress = { [weak self] in self?.run("agents.show-attention") }
        panelButton.onPress = { [weak self] in self?.run("inspector.toggle") }
        trailing.setViews([bellButton, panelButton], in: .leading)
        trailing.spacing = UILooks.pt(Look.gap)

        location.font = UILooks.font(DesignTokens.Breadcrumb.fontSize)
        location.textColor = DesignTokens.Breadcrumb.color
        location.lineBreakMode = .byTruncatingMiddle
        location.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        wantsLayer = true
        hairline.wantsLayer = true
        for view in [search, location, newTabButton, trailing, hairline] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        searchLeading = search.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.searchStart(fullScreen: false))
        NSLayoutConstraint.activate([
            searchLeading,
            // The bar's gap and the tabs group's margin, as the mockup lays them out.
            location.leadingAnchor.constraint(equalTo: search.trailingAnchor,
                                              constant: UILooks.pt(Look.gap + DesignTokens.Tab.groupMarginLeft)),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: newTabButton.trailingAnchor, constant: UILooks.pt(Look.gap)),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(Look.padding.right)),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
        ] + [search, location, newTabButton, trailing].map { $0.centerYAnchor.constraint(equalTo: centerYAnchor) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarView is created in code") }

    /// After the window buttons and the mockup's gap; at the bar's own padding in full screen,
    /// where macOS hides the buttons (owner, 2026-10-19).
    private static func searchStart(fullScreen: Bool) -> CGFloat {
        fullScreen ? UILooks.pt(Look.padding.left) : windowButtonsEnd + UILooks.pt(Look.gap + Look.afterTrafficLights)
    }

    private func showNewMenu() {
        guard let entries = newMenu?(), !entries.isEmpty else { return run("tab.new") }
        PopupMenu.show(entries, below: newTabButton)
    }

    /// The project and the task a folder stands for: `<repo>.worktrees/<branch>` (where New Task
    /// puts a task, plan 19) is the repository's project and that task; anything else, its name.
    static func location(of root: String) -> (project: String, task: String?) {
        let url = URL(fileURLWithPath: root)
        let parent = url.deletingLastPathComponent().lastPathComponent
        if parent.hasSuffix(".worktrees") {
            return (String(parent.dropLast(".worktrees".count)), url.lastPathComponent)
        }
        return (url.lastPathComponent, nil)
    }

    /// Where you are: the project, and the task when one is selected.
    func setLocation(project: String, task: String?) {
        location.stringValue = [project, task].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " › ")
    }

    /// The bell, where its popover opens; lit while it is open.
    var bellAnchor: NSView { bellButton }
    func setBellOpen(_ open: Bool) { bellButton.isOn = open }
    func setInspectorOpen(_ open: Bool) { panelButton.isOn = open }

    /// The bell's count: what needs you, and finished agents you have not seen.
    func setBell(count: Int) {
        bellButton.setBadge(count)
    }

    /// Puts a project's tab bar after where you are, "+" right after its tabs.
    func setTabBar(_ bar: TabBarView) {
        guard bar !== tabBar else { return }
        tabBar?.removeFromSuperview()
        NSLayoutConstraint.deactivate(tabBarConstraints)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        tabBarConstraints = [
            bar.leadingAnchor.constraint(equalTo: location.trailingAnchor,
                                         constant: UILooks.pt(DesignTokens.Breadcrumb.marginRight + DesignTokens.Tab.groupGap)),
            bar.heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Tab.height)),
            bar.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.leadingAnchor.constraint(equalTo: bar.trailingAnchor, constant: UILooks.pt(DesignTokens.Tab.groupGap)),
        ]
        NSLayoutConstraint.activate(tabBarConstraints)
        // The strip is as wide as its tabs and gives way first when the window is narrow.
        bar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        tabBar = bar
    }

    // MARK: The window

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let center = NotificationCenter.default
        center.removeObserver(self)
        guard let window else { return }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            center.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
        }
        // AppKit tiles the window buttons again on many events (resize, focus, a screen or scale
        // change, un-minimizing, an appearance change): following their own frame catches every
        // one (review of 2026-11-17). Moving them posts again, but the second time they are
        // already in place and nothing moves.
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind) else { continue }
            button.postsFrameChangedNotifications = true
            center.addObserver(self, selector: #selector(buttonMoved), name: NSView.frameDidChangeNotification, object: button)
        }
        windowChanged()
    }

    @objc private func windowChanged() {
        let full = window?.styleMask.contains(.fullScreen) == true
        searchLeading.constant = Self.searchStart(fullScreen: full)
        centerWindowButtons()
    }

    @objc private func buttonMoved() { centerWindowButtons() }

    override func layout() {
        super.layout()
        centerWindowButtons()
    }

    /// The compact toolbar centers the window buttons in 38 pt; the new frame's bar is 44, so
    /// they move down to its middle, or they sit 3 pt above every other control (2026-11-17).
    /// macOS lays them out again on many events: this runs after each move of theirs.
    private func centerWindowButtons() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        for (kind, mid) in zip([NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton], Self.windowButtonMids) {
            guard let button = window.standardWindowButton(kind), let container = button.superview else { continue }
            let middle = Self.height / 2
            let fromTop = container.isFlipped ? button.frame.midY : container.bounds.height - button.frame.midY
            let delta = middle - fromTop
            let across = UILooks.pt(mid) - button.frame.midX
            guard abs(delta) > 0.5 || abs(across) > 0.5 else { continue }
            var origin = button.frame.origin
            origin.y += container.isFlipped ? delta : -delta
            origin.x += across
            button.setFrameOrigin(origin)
        }
    }

    /// Empty parts of the bar drag the window, like a normal title bar.
    override var mouseDownCanMoveWindow: Bool { true }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Look.bg.cgColor
        hairline.layer?.backgroundColor = Look.borderBottom.cgColor
    }
}
