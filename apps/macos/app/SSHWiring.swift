import AppKit
import Icons
import Menus
import SSH
import StatusBar
import Strings
import Themes
import UILooks

/// The status bar's SSH and Ports items in this window (docs/spec/ssh.md,
/// docs/spec/status-bar.md). SSH: "SSH 3/3" from ~/.ssh/config, a click
/// lists the hosts to connect to. Ports: what the programs in Cadex's
/// terminals listen on, a click opens one in the preview. Each reads only
/// while it shows.
extension WindowSession {
    func makeSSHItem() -> StatusItem {
        let strip = SSHStrip()
        let item = StatusItem(id: "ssh", title: "SSH", subtitle: T("Hosts of ~/.ssh/config that answer, tested on open and every 10 min",
                                                                  "Hosts do ~/.ssh/config que respondem, testados ao abrir e a cada 10 min"),
                              icon: .hardDrives, side: .right, view: strip)
        strip.onConnect = { [weak self] alias in self?.connectSSH(alias) }
        ThemeStore.shared.observe { [weak strip] theme in
            strip?.text = theme.interface.text.nsColor
            strip?.secondary = theme.interface.secondaryText.nsColor
        }
        var token: UUID?
        item.onVisible = { [weak strip] visible in
            if visible {
                token = SSHController.shared.watch { strip?.render() }
            } else if let id = token {
                SSHController.shared.stop(id)
                token = nil
            }
        }
        return item
    }

    /// ssh.connect: a new terminal tab typing `ssh <alias>` and Enter; the
    /// shell reads it once it is up.
    func connectSSH(_ alias: String) {
        guard let tabs else { return }
        tabs.newTab()
        let quoted = "'" + alias.replacingOccurrences(of: "'", with: "'\\''") + "'"
        tabs.activeTerminal?.session?.write("ssh \(quoted)\n")
    }

    func makePortsItem() -> StatusItem {
        let label = StatusLabel(icon: .plug, tip: T("Ports the programs in your terminals listen on", "Portas que os programas dos seus terminais ouvem"))
        let item = StatusItem(id: "ports", title: T("Ports", "Portas"),
                              subtitle: T("What your terminals' programs listen on, every 10 s while one runs",
                                          "O que os programas dos terminais ouvem, a cada 10 s com um rodando"),
                              icon: .plug, side: .right, view: label)
        // The card on hover (or a click): each port opens in the preview.
        let card = HoverCard(over: label) { [weak self] in self?.portsCardContent() ?? NSView() }
        label.onClick = { card.openNow() }
        portsCard = card
        var timer: Timer?
        item.onVisible = { [weak self, weak label] visible in
            timer?.invalidate()
            timer = nil
            guard visible, let label else { return }
            self?.readPorts(into: label)
            let tick = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { if let self, let label = self.portsLabel { self.readPorts(into: label) } }
            }
            tick.tolerance = 2
            RunLoop.main.add(tick, forMode: .common)
            timer = tick
        }
        portsLabel = label
        return item
    }

    private func portsCardContent() -> NSView {
        let ui = ThemeStore.shared.current.interface
        let title = NSTextField(labelWithString: T("Listening ports", "Portas ouvindo"))
        title.font = UILooks.font(12, weight: .semibold)
        title.textColor = ui.text.nsColor
        var rows: [NSView] = [title]
        if ports.isEmpty {
            let none = NSTextField(labelWithString: T("No program in your terminals is listening", "Nenhum programa dos terminais está ouvindo"))
            none.font = UILooks.font(11)
            none.textColor = ui.secondaryText.nsColor
            rows.append(none)
        }
        for port in ports {
            let name = NSTextField(labelWithString: "localhost:\(port)")
            name.font = UILooks.monospacedDigits(12)
            name.textColor = ui.text.nsColor
            let open = NSTextField(labelWithString: T("Open in preview", "Abrir no preview"))
            open.font = UILooks.font(11)
            open.textColor = ui.secondaryText.nsColor
            let line = NSStackView(views: [name, NSView(), open])
            let row = HoverRow(line)
            row.onClick = { [weak self] in
                self?.portsCard?.close()
                self?.openPreview("http://localhost:\(port)")
            }
            row.widthAnchor.constraint(equalToConstant: UILooks.pt(240)).isActive = true
            rows.append(row)
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.setCustomSpacing(8, after: title)
        return stack
    }

    /// Only terminals running a program are asked: a shell at its prompt
    /// listens on nothing, and with none running nothing is read.
    func readPorts(into label: StatusLabel) {
        let groups = (spaces?.spaces ?? []).flatMap { $0.tabs.allTerminals }.map(\.foregroundGroup).filter { $0 > 0 }
        ports = groups.isEmpty ? [] : ListeningPorts.ports(inGroups: groups)
        label.text = "\(ports.count)"
        portsCard?.refresh()
        label.setTip(ports.isEmpty ? T("No program is listening", "Nenhum programa ouvindo") : ports.map { ":\($0)" }.joined(separator: " "))
    }
}
