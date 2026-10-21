import AppKit
import Icons
import Strings
import Menus
import UILooks

/// The status bar's Agent usage item (docs/spec/agents.md, Accounts): the
/// account of the agent in the focused terminal, or the last one shown,
/// with its logo, name, a bar of the 5 hour session that takes the free room and "5h · wk".
/// The pointer over it opens a popover with every account of every
/// provider (the owner, 2026-10-21). The app watches the usage while the
/// item shows and says which account the terminal's agent uses.
@MainActor
public final class AgentUsageStrip: NSView {
    public var onClick: (() -> Void)?
    public var colors = AgentColors() { didSet { render() } }
    /// The focused terminal's agent account, by folder; nil keeps the last.
    public var focused: String? { didSet { if let focused { last = focused }; render() } }
    private(set) var last: String?
    private let stack = NSStackView()
    private var card: HoverCard?

    public init() {
        super.init(frame: .zero)
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: UILooks.pt(20)),
        ])
        render()
        card = HoverCard(over: self) { [weak self] in AgentUsageCard.make(colors: self?.colors ?? AgentColors()) }
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
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let usage = AgentUsageController.shared
        guard let account = shown() else {
            stack.addArrangedSubview(AgentText.label(T("Usage", "Uso"), size: 11, color: colors.secondary))
            return
        }
        let logo = NSImageView(image: account.logo.image(size: UILooks.pt(12)))
        logo.contentTintColor = colors.secondary
        stack.addArrangedSubview(logo)
        stack.addArrangedSubview(AgentText.label(account.name, size: 11, color: colors.text))
        guard let numbers = usage.states[account.dir]?.usage else {
            stack.addArrangedSubview(AgentText.label("–", size: 11, color: colors.secondary))
            return
        }
        if let session = numbers.session {
            let meter = AgentMeter(share: session.percent / 100, color: AgentMeter.color(session.percent, accent: colors.accent), track: colors.secondary)
            fit(meter)
            stack.addArrangedSubview(meter)
        }
        let text = AgentText.label(Self.short(numbers), size: 11, color: colors.secondary)
        text.font = UILooks.monospacedDigits(11)
        stack.addArrangedSubview(text)
        card?.refresh()
    }

    /// The bar takes the status bar's free room, from 40 pt up to half the
    /// popover's bars (136 pt): at 30 pt it was too small to read (the
    /// owner, 2026-10-21). Below the other items' resistance, so it gives
    /// way first when the window narrows.
    private func fit(_ meter: NSView) {
        let wide = meter.widthAnchor.constraint(equalToConstant: UILooks.pt(136))
        wide.priority = NSLayoutConstraint.Priority(240)
        NSLayoutConstraint.activate([
            wide,
            meter.widthAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(40)),
            meter.widthAnchor.constraint(lessThanOrEqualToConstant: UILooks.pt(136)),
        ])
        meter.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(240), for: .horizontal)
    }

    /// "19% 5h · 97% wk"
    static func short(_ numbers: AgentUsage) -> String {
        [numbers.session.map { "\(Int($0.percent.rounded()))% 5h" }, numbers.week.map { "\(Int($0.percent.rounded()))% wk" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    public override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            card?.close()
            onClick?()
        }
    }
}
