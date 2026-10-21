import AppKit
import Icons
import Menus
import SSH
import StatusBar
import Strings

/// The status bar's SSH and Ports items in this window (docs/spec/ssh.md,
/// docs/spec/status-bar.md). SSH: "SSH 3/3" from ~/.ssh/config, a click
/// lists the hosts to connect to. Ports: what the programs in Cadex's
/// terminals listen on, a click opens one in the preview. Each reads only
/// while it shows.
extension WindowSession {
    func makeSSHItem() -> StatusItem {
        let label = StatusLabel(icon: .hardDrives, tip: "SSH")
        let item = StatusItem(id: "ssh", title: "SSH", subtitle: T("Hosts of ~/.ssh/config that answer, tested on open and every 10 min",
                                                                  "Hosts do ~/.ssh/config que respondem, testados ao abrir e a cada 10 min"),
                              icon: .hardDrives, side: .right, view: label)
        label.onClick = { [weak self, weak label] in
            guard let self, let label else { return }
            PopupMenu.show(self.sshEntries(), above: label)
        }
        var token: UUID?
        item.onVisible = { [weak label] visible in
            if visible {
                token = SSHController.shared.watch { if let label { Self.showSSH(on: label) } }
            } else if let id = token {
                SSHController.shared.stop(id)
                token = nil
            }
        }
        return item
    }

    private static func showSSH(on label: StatusLabel) {
        let ssh = SSHController.shared
        let counts = ssh.counts
        label.text = ssh.hosts.isEmpty || counts.tested == 0 ? "SSH" : "SSH \(counts.up)/\(counts.tested)"
        label.tint = counts.tested == 0 ? nil : counts.up == counts.tested ? .systemGreen : .systemOrange
        let lines = ssh.hosts.map { "\($0.alias): " + SSHCommands.describe(ssh.reach[$0.alias] ?? .unknown, host: $0) }
        label.setTip(lines.isEmpty ? T("No hosts in ~/.ssh/config", "Nenhum host no ~/.ssh/config") : lines.joined(separator: "\n"))
    }

    private func sshEntries() -> [MenuEntry] {
        let ssh = SSHController.shared
        guard !ssh.hosts.isEmpty else { return [MenuEntry(T("No hosts in ~/.ssh/config", "Nenhum host no ~/.ssh/config"), isEnabled: false) {}] }
        var entries = ssh.hosts.map { host in
            MenuEntry(host.alias, icon: .terminalWindow, shortcut: SSHCommands.describe(ssh.reach[host.alias] ?? .unknown, host: host)) { [weak self] in
                self?.connectSSH(host.alias)
            }
        }
        entries.append(.separator)
        entries.append(MenuEntry(T("Test Again", "Testar de novo"), icon: .arrowClockwise) { [weak self] in _ = self?.commands.run("ssh.test-again") })
        return entries
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
        label.onClick = { [weak self, weak label] in
            guard let self, let label else { return }
            let entries = self.ports.isEmpty
                ? [MenuEntry(T("No program is listening", "Nenhum programa ouvindo"), isEnabled: false) {}]
                : self.ports.map { port in MenuEntry("localhost:\(port)", icon: .globe) { [weak self] in self?.openPreview("http://localhost:\(port)") } }
            PopupMenu.show(entries, above: label)
        }
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

    /// Only terminals running a program are asked: a shell at its prompt
    /// listens on nothing, and with none running nothing is read.
    func readPorts(into label: StatusLabel) {
        let groups = (spaces?.spaces ?? []).flatMap { $0.tabs.allTerminals }.map(\.foregroundGroup).filter { $0 > 0 }
        ports = groups.isEmpty ? [] : ListeningPorts.ports(inGroups: groups)
        label.text = "\(ports.count)"
        label.setTip(ports.isEmpty ? T("No program is listening", "Nenhum programa ouvindo") : ports.map { ":\($0)" }.joined(separator: " "))
    }
}
