import AppKit
import Menus
import Strings
import UILooks

/// The status bar's SSH item (docs/spec/ssh.md): a dot and "SSH 3/3". The
/// dot is green when every host answers under 100 ms, yellow when one is
/// slower, red when one is down, grey before the first test; it breathes
/// while yellow, red or testing, and stays still when all is well (an
/// animation that never stops costs a little, so only when it asks to be
/// seen; the owner's idea, 2026-10-21). The pointer over it, or a click,
/// opens a card with each host: a click on one connects, "Test Again"
/// tests them now. No menu: the card is the way (the owner, 2026-10-21).
@MainActor
public final class SSHStrip: NSView {
    public enum Level: Equatable { case good, slow, down, unknown }

    /// The slow line: above it a host is yellow.
    static let slowMs = 100

    /// A host picked in the card: the app opens `ssh <alias>` in a tab.
    public var onConnect: ((String) -> Void)?
    public var text: NSColor = .labelColor { didSet { render() } }
    public var secondary: NSColor = .secondaryLabelColor { didSet { render() } }
    private let dot = StatusDot()
    private let label = NSTextField(labelWithString: "SSH")
    private var card: HoverCard?

    public init() {
        super.init(frame: .zero)
        HoverHighlight.attach(self)
        label.font = UILooks.monospacedDigits(11)
        let stack = NSStackView(views: [dot, label])
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: UILooks.pt(20)),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("SSH")
        card = HoverCard(over: self) { [weak self] in self?.cardContent() ?? NSView() }
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SSHStrip is created in code") }

    public override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        card?.openNow()
    }

    /// The level of one host.
    static func level(_ reach: SSHController.Reach) -> Level {
        switch reach {
        case .up(let ms): ms > slowMs ? .slow : .good
        case .down: .down
        default: .unknown
        }
    }

    /// The bar's level: the worst host decides.
    static func level(of reaches: [SSHController.Reach]) -> Level {
        let levels = reaches.map(level)
        if levels.contains(.down) { return .down }
        if levels.contains(.slow) { return .slow }
        return levels.contains(.good) ? .good : .unknown
    }

    static func color(_ level: Level) -> NSColor {
        switch level {
        case .good: .systemGreen
        case .slow: .systemYellow
        case .down: .systemRed
        case .unknown: .systemGray
        }
    }

    public func render() {
        let ssh = SSHController.shared
        let reaches = ssh.hosts.compactMap { ssh.reach[$0.alias] }
        let level = Self.level(of: reaches)
        let testing = reaches.contains(.testing)
        dot.set(color: Self.color(level), breathing: testing || level == .slow || level == .down)
        let counts = ssh.counts
        label.stringValue = counts.tested == 0 ? "SSH" : "SSH \(counts.up)/\(counts.tested)"
        label.textColor = level == .down ? Self.color(.down) : secondary
        card?.refresh()
    }

    /// Each host: its dot, the alias, the address and how it answered.
    func cardContent() -> NSView {
        let ssh = SSHController.shared
        let title = NSTextField(labelWithString: T("SSH hosts", "Hosts SSH"))
        title.font = UILooks.font(12, weight: .semibold)
        title.textColor = text
        var rows: [NSView] = [title]
        if ssh.hosts.isEmpty {
            rows.append(small(T("No hosts in ~/.ssh/config", "Nenhum host no ~/.ssh/config")))
        }
        for host in ssh.hosts {
            let reach = ssh.reach[host.alias] ?? .unknown
            let mark = StatusDot()
            mark.set(color: host.proxy == nil ? Self.color(Self.level(reach)) : .systemGray, breathing: reach == .testing)
            let name = NSTextField(labelWithString: host.alias)
            name.font = UILooks.font(12, weight: .medium)
            name.textColor = text
            let address = small(host.hostName + (host.port == 22 ? "" : ":\(host.port)"))
            let names = NSStackView(views: [name, address])
            names.orientation = .vertical
            names.alignment = .leading
            names.spacing = 1
            let answer = small(SSHCommands.describe(reach, host: host))
            answer.font = UILooks.monospacedDigits(11)
            if case .down = reach { answer.textColor = Self.color(.down) }
            answer.setContentCompressionResistancePriority(.required, for: .horizontal)
            let line = NSStackView(views: [mark, names, NSView(), answer])
            line.spacing = 8
            line.alignment = .centerY
            let row = HoverRow(line)
            row.setAccessibilityLabel(T("Connect to ", "Conectar a ") + host.alias)
            row.toolTip = T("Connect: ssh ", "Conectar: ssh ") + host.alias
            row.onClick = { [weak self] in
                self?.card?.close()
                self?.onConnect?(host.alias)
            }
            rows.append(row)
            row.widthAnchor.constraint(equalToConstant: UILooks.pt(272)).isActive = true
        }
        let again = NSTextField(labelWithString: T("Test Again", "Testar de novo"))
        again.font = UILooks.font(11, weight: .medium)
        again.textColor = text
        let button = HoverRow(again)
        button.setAccessibilityLabel(T("Test Again", "Testar de novo"))
        button.onClick = { SSHController.shared.testNow() }
        let note = small(T("Click a host to connect", "Clique num host para conectar"))
        note.toolTip = T("Tested on open and every 10 min", "Testado ao abrir e a cada 10 min")
        let footer = NSStackView(views: [note, NSView(), button])
        footer.alignment = .centerY
        footer.widthAnchor.constraint(equalToConstant: UILooks.pt(272)).isActive = true
        rows.append(footer)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(8, after: title)
        return stack
    }

    private func small(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = UILooks.font(11)
        label.textColor = secondary
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

/// A small round mark that may breathe: its opacity eases between full and
/// a third, slowly, on the render server (no timer of the app's).
@MainActor
final class StatusDot: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let side = UILooks.pt(7)
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: side), heightAnchor.constraint(equalToConstant: side)])
        layer?.cornerRadius = side / 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("StatusDot is created in code") }

    func set(color: NSColor, breathing: Bool) {
        layer?.backgroundColor = color.cgColor
        let key = "breathe"
        if breathing, layer?.animation(forKey: key) == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.3
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(pulse, forKey: key)
        } else if !breathing {
            layer?.removeAnimation(forKey: key)
        }
    }

    var isBreathing: Bool { layer?.animation(forKey: "breathe") != nil }
}
