import AppKit
import Icons
import Strings
import UILooks

/// The Agents page of the sidebar (docs/spec/agents.md, Sessions): the live
/// sessions of every account, grouped by project, each with its sign, name,
/// time in that status and "account logo, status · account"; a click goes
/// to its terminal, its arrow unfolds its subagents, a project's title
/// folds the project (AgentSessionList.swift). It reads only while it
/// shows: hidden or out of a window it lets go of the controller.
@MainActor
public final class AgentsView: NSView {
    /// Whether a session runs in one of Cadex's terminals (its pid's group
    /// is a terminal's foreground group).
    public var isInCadex: (AgentSession) -> Bool = { _ in false }
    /// A click: its terminal, or its folder when outside Cadex.
    public var onOpen: ((AgentSession) -> Void)?
    /// "Turn On" when agents.sessions is off.
    public var onEnable: (() -> Void)?
    public var colors = AgentColors() { didSet { render() } }
    /// The list shown: "sessions" or "accounts" (AgentAccountsView.swift);
    /// each is its own sidebar page, so each has its own icon and shortcut.
    public var subtab = "sessions" { didSet { if subtab != oldValue { updateWatching(); render() } } }
    /// Rename an account (nil: back to its own name) or hide and show it;
    /// the app saves agents.accountNames and agents.hiddenAccounts.
    public var onRename: ((AgentAccount) -> Void)?
    public var onHide: ((AgentAccount, Bool) -> Void)?
    /// A click on an account: open its agent in the focused terminal (the app's).
    public var onLaunch: ((AgentAccount) -> Void)?

    let controller: AgentsController
    /// Usage is read while Accounts shows (AgentUsageController).
    var usage: AgentUsageController { .shared }
    private let stack = NSStackView()
    /// Projects folded by a click on their title, by root, while the app runs.
    var folded: Set<String> = []
    /// What to unfold once the page is drawn again: "session:<id>" or
    /// "project:<root>" (AgentSessionList.swift).
    var unfolding: String?
    /// The parts on the page that fold, by the same keys.
    var reveals: [String: AgentReveal] = [:]
    private let scroll = NSScrollView()
    private var token: UUID?
    private var usageToken: UUID?
    private var clock: Timer?

    public init(controller: AgentsController = .shared) {
        self.controller = controller
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 6, bottom: 10, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let document = Flipped()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentsView is created in code") }

    // MARK: Reading only while it shows

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWatching()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        updateWatching()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updateWatching()
    }

    func updateWatching() {
        let shows = window != nil && !isHiddenOrHasHiddenAncestor
        if shows, token == nil {
            token = controller.watch { [weak self] in self?.render() }
            // The "3m" ages move on while the page shows.
            let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.render() } }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        } else if !shows, let token {
            controller.stop(token)
            self.token = nil
            clock?.invalidate()
            clock = nil
        }
        // The plans' usage only while Accounts is the tab on screen.
        let accounts = shows && subtab == "accounts"
        if accounts, usageToken == nil {
            usageToken = usage.watch { [weak self] in if self?.subtab == "accounts" { self?.render() } }
        } else if !accounts, let usageToken {
            usage.stop(usageToken)
            self.usageToken = nil
        }
    }

    // MARK: Drawing the list

    func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        reveals = [:]
        guard controller.isEnabled else {
            return note(T("Agent sessions are off.", "As sessões de agentes estão desligadas."), button: T("Turn On", "Ligar"))
        }
        if subtab == "accounts" { return renderAccounts() }
        let groups = AgentsLayout.groups(controller.sessions)
        if groups.isEmpty {
            note(T("No agents running. Start one in a terminal: claude", "Nenhum agente rodando. Abra um num terminal: claude"))
        }
        renderGroups(groups)
        if controller.unreadable > 0 {
            note(T("Some sessions could not be read (a newer Claude Code?).", "Algumas sessões não foram lidas (Claude Code mais novo?)."))
        }
    }

    func add(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -12).isActive = true
    }

    func note(_ text: String, button: String? = nil) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = UILooks.font(12)
        label.textColor = colors.secondary
        var views: [NSView] = [label]
        if let button {
            let control = NSButton(title: button, target: self, action: #selector(enable))
            views.append(control)
        }
        let box = NSStackView(views: views)
        box.orientation = .vertical
        box.alignment = .leading
        box.edgeInsets = NSEdgeInsets(top: 12, left: 6, bottom: 4, right: 6)
        add(box)
    }

    @objc private func enable() { onEnable?() }
}

/// A view whose origin is the top left, so the list starts at the top.
private final class Flipped: NSView {
    override var isFlipped: Bool { true }
}
