import AppKit
import Menus
import Strings
import UILooks

/// The "Tailnet" group the app puts in the SSH card, under the hosts of
/// ~/.ssh/config (docs/spec/machines.md): each machine's dot (green online
/// and direct, yellow through a relay, red offline, grey before its
/// ping), its name, system and answer. A click on an online one connects.
/// nil when there is nothing to show: no Tailscale, or machines.tailscale off.
@MainActor
public enum MachinesSection {
    public static func make(width: CGFloat, text: NSColor, secondary: NSColor,
                            connect: @escaping (Machine) -> Void) -> NSView? {
        let controller = MachinesController.shared
        guard controller.isEnabled, let status = controller.status else { return nil }
        let others = status.others
        let title = label(titleText(status), size: 12, weight: .semibold, color: text)
        var rows: [NSView] = [title]
        if !status.isRunning {
            rows.append(label(stateText(status.state), size: 11, color: secondary))
        } else if others.isEmpty {
            rows.append(label(T("No other machines on your tailnet", "Nenhuma outra máquina na sua tailnet"), size: 11, color: secondary))
        }
        for machine in status.isRunning ? others : [] {
            let ping = controller.pings[machine.id] ?? nil
            let pinging = controller.pings[machine.id] != nil && ping == nil
            let mark = Dot(color: color(machine, ping: ping), breathing: pinging)
            let name = label(machine.name, size: 12, weight: .medium, color: text)
            let detail = label([machine.os, machine.address].filter { !$0.isEmpty }.joined(separator: " · "), size: 11, color: secondary)
            let names = NSStackView(views: [name, detail])
            names.orientation = .vertical
            names.alignment = .leading
            names.spacing = 1
            let answer = label(describe(machine, ping: ping, pinging: pinging), size: 11, color: machine.online ? secondary : .systemRed)
            answer.font = UILooks.monospacedDigits(11)
            answer.setContentCompressionResistancePriority(.required, for: .horizontal)
            let line = NSStackView(views: [mark, names, NSView(), answer])
            line.spacing = 8
            line.alignment = .centerY
            let row = HoverRow(line)
            row.setAccessibilityLabel(T("Connect to ", "Conectar a ") + machine.name)
            row.toolTip = T("Connect: ssh ", "Conectar: ssh ") + machine.address
            if machine.online { row.onClick = { connect(machine) } }
            row.widthAnchor.constraint(equalToConstant: width).isActive = true
            rows.append(row)
        }
        if status.partial {
            rows.append(label(T("Some details could not be read from this Tailscale version", "Alguns detalhes não puderam ser lidos desta versão do Tailscale"),
                              size: 10, color: secondary))
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(8, after: title)
        return stack
    }

    /// "Tailnet 2/3": online of the other machines.
    static func titleText(_ status: TailnetStatus) -> String {
        let others = status.others
        guard status.isRunning, !others.isEmpty else { return "Tailnet" }
        return "Tailnet \(others.filter(\.online).count)/\(others.count)"
    }

    static func stateText(_ state: String) -> String {
        switch state {
        case "NeedsLogin", "NeedsMachineAuth": T("Tailscale needs you to log in", "O Tailscale pede que você entre")
        case "Stopped": T("Tailscale is turned off", "O Tailscale está desligado")
        default: T("Tailscale is starting…", "O Tailscale está começando…")
        }
    }

    static func color(_ machine: Machine, ping: MachinePing?) -> NSColor {
        guard machine.online else { return .systemRed }
        switch ping?.path ?? machine.path {
        case .direct: return .systemGreen
        case .relay: return .systemYellow
        case .idle: return ping?.error == nil && ping?.ms != nil ? .systemGreen : .systemGray
        }
    }

    /// "direct 12 ms", "relay (sao) 80 ms", "offline, seen 3h ago".
    public static func describe(_ machine: Machine, ping: MachinePing?, pinging: Bool = false, now: Date = Date()) -> String {
        guard machine.online else {
            guard let seen = machine.lastSeen else { return T("offline", "fora do ar") }
            return T("offline, seen ", "fora do ar, visto há ") + ago(seen, now: now) + T(" ago", "")
        }
        if pinging { return T("pinging…", "medindo…") }
        let ms = ping?.ms.map { " \($0) ms" } ?? ""
        switch ping?.path ?? machine.path {
        case .direct: return T("direct", "direto") + ms
        case .relay(let region): return "relay (\(region))" + ms
        case .idle: return ping?.error != nil ? T("no answer", "sem resposta") : T("online", "no ar") + ms
        }
    }

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 3600 { return "\(max(1, seconds / 60))min" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }

    private static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = UILooks.font(size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}

/// A small round mark, breathing while its machine is pinged.
@MainActor
final class Dot: NSView {
    init(color: NSColor, breathing: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        let side = UILooks.pt(7)
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: side), heightAnchor.constraint(equalToConstant: side)])
        layer?.cornerRadius = side / 2
        layer?.backgroundColor = color.cgColor
        if breathing {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.3
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            layer?.add(pulse, forKey: "breathe")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Dot is created in code") }
}
