import AppKit
import Strings
import UILooks

/// The usage part of an account's card: the plan, a bar for the 5 hour
/// session and one for the week, each with its share and when it resets;
/// the bar warns from 70% and alarms from 90% (docs/spec/agents.md).
extension AgentsView {
    func usageLines(_ account: AgentAccount) -> [NSView] {
        let plan = usage.plans[account.dir].map { $0.capitalized }
        var lines: [NSView] = []
        switch usage.states[account.dir] ?? .loading {
        case .loading:
            lines.append(line(T("Reading…", "Lendo…")))
        case .expired:
            lines.append(line(T("Login expired. Run claude with this account to renew it.", "Login vencido. Rode o claude com esta conta para renovar.")))
        case .noLogin:
            lines.append(line(T("No login found for this account.", "Nenhum login encontrado para esta conta.")))
        case .ready(let numbers, _):
            lines += bars(numbers, dim: false)
        case .failed(let numbers, let at):
            if let numbers { lines += bars(numbers, dim: true) }
            let when = at.map { T("updated ", "atualizado há ") + AgentTime.short(since: $0) } ?? T("could not read", "não deu para ler")
            lines.append(line(T("No connection or the service refused; ", "Sem conexão ou o serviço recusou; ") + when))
        }
        if let plan { lines.insert(line(plan), at: 0) }
        return lines
    }

    private func line(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = UILooks.font(11)
        label.textColor = colors.secondary
        return label
    }

    private func bars(_ numbers: AgentUsage, dim: Bool) -> [NSView] {
        var views: [NSView] = []
        if let session = numbers.session { views.append(bar(T("Session · 5 h", "Sessão · 5 h"), session, dim: dim)) }
        if let week = numbers.week { views.append(bar(T("Week", "Semana"), week, dim: dim)) }
        if let sonnet = numbers.sonnetWeek, sonnet.percent > 0 { views.append(bar(T("Week · Sonnet", "Semana · Sonnet"), sonnet, dim: dim)) }
        return views
    }

    private func bar(_ title: String, _ window: AgentUsage.Window, dim: Bool) -> NSView {
        let percent = Int(window.percent.rounded())
        let resets = window.resets.map { T(" · resets ", " · reinicia ") + AgentResetTime.text($0) } ?? ""
        let left = AgentText.label(title, size: 11, color: colors.secondary)
        let right = AgentText.label("\(percent)%\(resets)", size: 11, color: colors.secondary)
        right.setContentCompressionResistancePriority(.required, for: .horizontal)
        let top = NSStackView(views: [left, NSView(), right])
        let meter = AgentMeter(share: window.percent / 100, color: AgentMeter.color(window.percent, accent: colors.accent), track: colors.secondary)
        meter.alphaValue = dim ? 0.45 : 1
        let stack = NSStackView(views: [top, meter])
        stack.orientation = .vertical
        stack.spacing = 3
        stack.alignment = .leading
        top.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        meter.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: UILooks.pt(200)).isActive = true
        return stack
    }
}

/// A thin rounded bar filled to a share.
@MainActor
final class AgentMeter: NSView {
    private let share: Double
    private let color: NSColor
    private let track: NSColor

    init(share: Double, color: NSColor, track: NSColor) {
        self.share = min(max(share, 0), 1)
        self.color = color
        self.track = track
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 5).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentMeter is created in code") }

    /// The accent below 70%, orange from 70, red from 90.
    static func color(_ percent: Double, accent: NSColor) -> NSColor {
        percent >= 90 ? .systemRed : percent >= 70 ? .systemOrange : accent
    }

    override func draw(_ dirtyRect: NSRect) {
        track.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 2.5, yRadius: 2.5).fill()
        guard share > 0 else { return }
        color.setFill()
        let width = max(bounds.width * share, 5)
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height), xRadius: 2.5, yRadius: 2.5).fill()
    }
}

/// "16:30" today, "Oct 28" another day.
enum AgentResetTime {
    static func text(_ date: Date, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Strings.language == .pt ? "pt_BR" : "en_US")
        if Calendar.current.isDate(date, inSameDayAs: now) {
            f.dateStyle = .none
            f.timeStyle = .short
        } else {
            f.setLocalizedDateFormatFromTemplate("MMM d")
        }
        return f.string(from: date)
    }
}

/// The status bar's Agent usage item: per shown account with numbers, its
/// name, a small bar of the 5 hour session and "2% 5h · 94% wk". Expired
/// logins stay out. The app makes it an item and watches the usage while
/// the item shows.
@MainActor
public final class AgentUsageStrip: NSView {
    public var onClick: (() -> Void)?
    public var colors = AgentColors() { didSet { render() } }
    private let stack = NSStackView()

    public init() {
        super.init(frame: .zero)
        stack.spacing = UILooks.pt(14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: UILooks.pt(20)),
        ])
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentUsageStrip is created in code") }

    public override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    public func render() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let usage = AgentUsageController.shared
        for account in usage.accounts() {
            guard let numbers = usage.states[account.dir]?.usage else { continue }
            let name = AgentText.label(account.name, size: 11, color: colors.text)
            var views: [NSView] = [name]
            if let session = numbers.session {
                let meter = AgentMeter(share: session.percent / 100, color: AgentMeter.color(session.percent, accent: colors.accent), track: colors.secondary)
                meter.widthAnchor.constraint(equalToConstant: UILooks.pt(30)).isActive = true
                views.append(meter)
            }
            let five = numbers.session.map { "\(Int($0.percent.rounded()))% 5h" }
            let week = numbers.week.map { "\(Int($0.percent.rounded()))% wk" }
            let text = AgentText.label([five, week].compactMap { $0 }.joined(separator: " · "), size: 11, color: colors.secondary)
            text.font = UILooks.monospacedDigits(11)
            views.append(text)
            let part = NSStackView(views: views)
            part.spacing = 5
            part.toolTip = account.name + ": " + [five, week].compactMap { $0 }.joined(separator: ", ")
            stack.addArrangedSubview(part)
        }
        if stack.arrangedSubviews.isEmpty { stack.addArrangedSubview(AgentText.label(T("Usage", "Uso"), size: 11, color: colors.secondary)) }
    }
}
