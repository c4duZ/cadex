import AppKit
import UILooks
import Icons
import Menus
import Strings
import Tabs

/// The top bar (docs/adr/0039-sidebar-with-work-and-files.md, plan 38 phase E; components.titleBar
/// and components.place): after the window buttons, the sidebar's button, the place ("project ›
/// task ▾"), the place's tabs and "+", Review in a task; on the right the needs-you pill (sidebar
/// closed), the account (its usage; the click switches) and the search (⌘K), and the settings. The
/// account and the settings came back on 2026-11-20 (the owner: with them gone there was no way to
/// switch accounts or open the settings). Every control runs a command by id (ADR 0005).
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
    /// The gaps around "project › task", closed when it says nothing (tabs right after the search).
    private var locationLeading: NSLayoutConstraint!
    private var tabsLeading: NSLayoutConstraint?

    private let run: (String) -> Void
    private let search = TitleBarSearch()
    private let newTabButton = TitleBarButton(
        icon: .plus, tip: T("Open a terminal, file, preview or git graph", "Abrir terminal, arquivo, preview ou grafo do git"), kind: .add)
    /// The needs-you pill, with the sidebar closed (ADR 0039: the bell became the sidebar's queue).
    let needs = TitleBarNeeds()
    /// The settings window (settings.open, ⌘,).
    private let settingsButton = TitleBarButton(icon: .gearSix, tip: T("Settings ⌘,", "Configurações ⌘,"))
    /// The focused agent's account (else the active one) and its usage; a click switches accounts.
    private let account = TitleBarAccount()
    /// The sidebar's button (view.toggle-sidebar, ⌘B) at the leading edge, lit while it is open.
    private let panelButton = TitleBarButton(icon: .sidebarSimple, tip: T("Sidebar ⌘B", "Barra lateral ⌘B"))
    /// Where you are; the click opens the place's menu (`placeMenu`, the app's).
    let place = TitleBarPlace()
    /// Review, only inside a task, after a divider.
    let review = TitleBarReview()
    private let divider = NSView()
    var placeMenu: (() -> [MenuEntry])?
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
        needs.onPress = { [weak self] in self?.run("agents.go-to-request") }
        panelButton.onPress = { [weak self] in self?.run("view.toggle-sidebar") }
        settingsButton.onPress = { [weak self] in self?.run("settings.open") }
        account.onPress = { [weak self] in self?.run("agents.switch-account") }
        place.onPress = { [weak self] in self?.showPlaceMenu() }
        review.onPress = { [weak self] in self?.run("git.review-open") }
        review.isHidden = true
        divider.wantsLayer = true
        divider.layer?.backgroundColor = DesignTokens.Place.Divider.color.cgColor
        divider.isHidden = true
        trailing.setViews([needs, account, search, settingsButton], in: .leading)
        trailing.spacing = UILooks.pt(Look.gap)


        wantsLayer = true
        hairline.wantsLayer = true
        for view in [panelButton, place, newTabButton, divider, review, trailing, hairline] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        searchLeading = panelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.searchStart(fullScreen: false))
        locationLeading = place.leadingAnchor.constraint(equalTo: panelButton.trailingAnchor, constant: UILooks.pt(Look.gap))
        place.setContentCompressionResistancePriority(.defaultHigh - 1, for: .horizontal)
        NSLayoutConstraint.activate([
            searchLeading,
            locationLeading,
            divider.leadingAnchor.constraint(equalTo: newTabButton.trailingAnchor, constant: UILooks.pt(DesignTokens.Place.Divider.margin.left)),
            divider.widthAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Place.Divider.width)),
            divider.heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.Place.Divider.height)),
            review.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: UILooks.pt(DesignTokens.Place.Divider.margin.right)),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: review.trailingAnchor, constant: UILooks.pt(Look.gap)),
            trailing.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(Look.padding.right)),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
        ] + [panelButton, place, newTabButton, divider, review, trailing].map { $0.centerYAnchor.constraint(equalTo: centerYAnchor) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TitleBarView is created in code") }

    /// After the window buttons and the mockup's gap; at the bar's own padding in full screen,
    /// where macOS hides the buttons (owner, 2026-10-19).
    private static func searchStart(fullScreen: Bool) -> CGFloat {
        fullScreen ? UILooks.pt(Look.padding.left) : windowButtonsEnd + UILooks.pt(Look.gap + Look.afterTrafficLights)
    }

    private static var locationGap: CGFloat { UILooks.pt(Look.gap + DesignTokens.Tab.groupMarginLeft) }
    private static var tabsGap: CGFloat { UILooks.pt(DesignTokens.Breadcrumb.marginRight + DesignTokens.Tab.groupGap) }

    private func showPlaceMenu() {
        guard let entries = placeMenu?(), !entries.isEmpty else { return }
        PopupMenu.show(entries, below: place)
    }

    /// Review shows inside a task only (ADR 0039).
    func setReviewShown(_ shown: Bool) {
        review.isHidden = !shown || tabsHidden
        divider.isHidden = review.isHidden
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

    /// The account's place, for its card (the same as the status bar's usage).
    var accountView: NSView { account }
    /// The account shown on the right: its name and how much of its limit it used.
    func setAccount(name: String?, used: Int?, provider: ProviderLogo) { account.show(name: name, used: used, provider: provider) }

    /// Where the requests' list opens when the sidebar's queue is not in sight: the search.
    var bellAnchor: NSView { search }
    /// No "+" beside a page's tabs (the board, a project's overview).
    func setNewTabHidden(_ hidden: Bool) { newTabButton.isHidden = hidden || tabsHidden }
    func setInspectorOpen(_ open: Bool) { panelButton.isOn = open }

    /// The needs-you pill: who waits, or nil to hide it (it shows only with the sidebar closed).
    func setNeeds(_ text: String?) { needs.say(text) }

    /// The home screen shows no terminal tabs and no "+" (the Home mockup).
    private var tabsHidden = false
    func setTabsHidden(_ hidden: Bool) {
        tabsHidden = hidden
        tabBar?.isHidden = hidden
        newTabButton.isHidden = hidden
        // No project, no place (ADR 0039: nothing open is the home screen).
        place.isHidden = hidden
        if hidden { setReviewShown(false) }
    }

    /// Puts a project's tab bar after where you are, "+" right after its tabs.
    func setTabBar(_ bar: TabBarView) {
        guard bar !== tabBar else { return }
        tabBar?.removeFromSuperview()
        NSLayoutConstraint.deactivate(tabBarConstraints)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        let leading = bar.leadingAnchor.constraint(equalTo: place.trailingAnchor, constant: UILooks.pt(Look.gap))
        tabsLeading = leading
        tabBarConstraints = [
            leading,
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
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification, CadexWindow.ownFullScreenDidChange] {
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
        let full = window?.isAnyFullScreen == true
        searchLeading.constant = Self.searchStart(fullScreen: full)
        centerWindowButtons()
    }

    /// Deferred to the end of the run loop's turn, once for many notices: called at once, it ran
    /// inside AppKit's own tiling of the buttons, which then put the last one (zoom) back 2 pt
    /// higher than the other two (the owner's print, 2026-11-19; logged: our move, then AppKit's).
    @objc private func buttonMoved() {
        guard !centerPending else { return }
        centerPending = true
        DispatchQueue.main.async { [weak self] in
            self?.centerPending = false
            self?.centerWindowButtons()
        }
    }

    private var centerPending = false

    override func layout() {
        super.layout()
        centerWindowButtons()
        // The room the tabs have: up to the "+" before the buttons on the right (plan 36 D: the
        // tabs that do not fit go under "» N"; the strip itself is only as wide as its tabs).
        if let bar = tabBar, trailing.frame.width > 0 {
            let reviewRoom = review.isHidden ? 0 : review.frame.width + UILooks.pt(DesignTokens.Place.Divider.margin.left + DesignTokens.Place.Divider.margin.right)
            bar.room = trailing.frame.minX - UILooks.pt(Look.gap) - newTabButton.frame.width
                - UILooks.pt(DesignTokens.Tab.groupGap) - reviewRoom - bar.frame.minX
        }
    }

    /// The compact toolbar centers the window buttons in 38 pt; the new frame's bar is 44, so
    /// they move down to its middle, or they sit 3 pt above every other control (2026-11-17).
    /// macOS lays them out again on many events: this runs after each move of theirs.
    private func centerWindowButtons() {
        guard let window, !window.isAnyFullScreen else { return }
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
