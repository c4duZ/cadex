import AppKit
import Icons
import Strings
import Menus
import UILooks

/// The status bar's Agent usage item (docs/spec/agents.md; the new frame's StatusBar): the
/// account of the agent in the focused terminal, or the last one shown, as "Claude bkdg 84% ·
/// resets 3h", the amber chip from 80% (plan 26 phase B; the logo and the session's bar of
/// before left with the new frame's mockup).
/// The pointer over it opens a popover with every account of every
/// provider (the owner, 2026-10-21). The app watches the usage while the
/// item shows and says which account the terminal's agent uses.
@MainActor
public final class AgentUsageStrip: NSView {
    public var onClick: (() -> Void)?
    /// A click on an account in the card: open its agent (the app's), as the Accounts page did
    /// before it left the sidebar (plan 26 phase E).
    public var onLaunch: ((AgentAccount) -> Void)?

    /// agents.show-accounts: the card at once, without the pointer over the item.
    public func openCard() { card?.openPinned() }
    /// The right click's choice of the active account (docs/spec/agents.md,
    /// Contas gerenciadas: chosen in this item and in ⌘K, plan 18).
    public var onSetActive: ((AgentAccount) -> Void)?
    public var colors = AgentColors() { didSet { render() } }
    /// The focused terminal's agent account, by folder; nil keeps the last.
    /// Set at every output of the focused terminal: drawn again only when
    /// the account changes, or the item flickered as an agent wrote (the
    /// owner, 2026-10-22).
    public var focused: String? {
        didSet {
            if let focused { last = focused }
            if focused != oldValue && (focused != nil || oldValue == nil) { render() }
        }
    }
    private(set) var last: String?
    private let stack = NSStackView()
    private let chip = NSView()
    private var card: HoverCard?

    public init() {
        super.init(frame: .zero)
        HoverHighlight.attach(self)
        // The amber fill on its own view: the hover highlight paints and clears this view's layer,
        // which took the chip's fill away after a hover (review of 2026-11-17).
        chip.wantsLayer = true
        chip.layer?.cornerRadius = UILooks.pt(DesignTokens.StatusBar.UsageChip.radius)
        stack.spacing = UILooks.pt(DesignTokens.StatusBar.iconGap)
        for view in [chip, stack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: leadingAnchor),
            chip.trailingAnchor.constraint(equalTo: trailingAnchor),
            chip.topAnchor.constraint(equalTo: topAnchor),
            chip.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(DesignTokens.StatusBar.UsageChip.padding.left)),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(DesignTokens.StatusBar.UsageChip.padding.right)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: UILooks.pt(DesignTokens.StatusBar.itemHeight)),
        ])
        render()
        card = HoverCard(over: self) { [weak self] in
            AgentUsageCard.make(colors: self?.colors ?? AgentColors()) { account in self?.card?.close(); self?.onLaunch?(account) }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentUsageStrip is created in code") }

    /// Which account shows: the focused one, the last one, else the first
    /// with numbers.
    func shown() -> AgentAccount? {
        let usage = AgentUsageController.shared
        let accounts = usage.visibleAccounts()
        let wanted = focused ?? last
        return accounts.first { $0.dir == wanted } ?? accounts.first { usage.states[$0.dir]?.usage != nil }
    }

    public func render() {
        if !stack.arrangedSubviews.isEmpty, window != nil { fade() }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let line = Self.line(for: shown())
        let text = AgentText.label(line.text, size: DesignTokens.StatusBar.fontSize, color: DesignTokens.StatusBar.color)
        text.font = UILooks.monospacedDigits(DesignTokens.StatusBar.fontSize, weight: line.warn ? Chip.weight : .regular)
        text.textColor = line.warn ? Chip.color : DesignTokens.StatusBar.color
        // A long account name is cut, not pushing the bar (the owner, 2026-10-22).
        text.lineBreakMode = .byTruncatingMiddle
        text.widthAnchor.constraint(lessThanOrEqualToConstant: UILooks.pt(DesignTokens.Tab.maxTitle) * 2).isActive = true
        stack.addArrangedSubview(text)
        chip.layer?.backgroundColor = line.warn ? Chip.bg.cgColor : nil
        card?.refresh()
    }

    typealias Chip = DesignTokens.StatusBar.UsageChip

    /// "Claude bkdg 84% · resets 3h": the account and its 5 hour session, as the mockup writes
    /// it; `warn` from the chip's threshold (80%), when the item becomes the amber chip
    /// (docs/spec/status-bar.md).
    static func line(for account: AgentAccount?, usage: AgentUsageController = .shared) -> (text: String, warn: Bool) {
        guard let account else { return (T("Usage", "Uso"), false) }
        let who = (account.provider == .codex ? "Codex " : "Claude ") + account.name
        guard let numbers = usage.states[account.dir]?.usage, let window = numbers.session ?? numbers.week else {
            return (who + " –", false)
        }
        let percent = Int(window.percent.rounded())
        let resets = window.resets.map { T(" · resets ", " · reinicia ") + AgentResetTime.text($0) } ?? ""
        return ("\(who) \(percent)%\(resets)", window.percent > Chip.showAbovePercent)
    }

    /// The account's switch fades in, as the bar's other texts do.
    private func fade() {
        stack.wantsLayer = true
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.18
        stack.layer?.add(fade, forKey: "fade")
    }

    /// "New sessions use": the Claude accounts in use, the active one checked.
    func activeMenu() -> [MenuEntry] {
        let usage = AgentUsageController.shared
        let accounts = usage.visibleAccounts().filter { $0.provider == .claude }
        let active = usage.activeAccount ?? accounts.first { $0.isDefault }?.dir
        var entries = [MenuEntry(T("New Sessions Use", "Sessões novas usam"), isEnabled: false) {}]
        entries += accounts.map { account in
            MenuEntry(account.name, icon: account.dir == active ? .check : nil) { [weak self] in self?.onSetActive?(account) }
        }
        return entries
    }

    public override func rightMouseDown(with event: NSEvent) {
        card?.close()
        PopupMenu.show(activeMenu(), at: convert(event.locationInWindow, from: nil), in: self, upward: true)
    }

    public override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            card?.close()
            onClick?()
        }
    }
}
