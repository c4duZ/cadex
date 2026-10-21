import CommandPalette
import Icons
import Strings

/// The SSH commands (ADR 0005): connect to a host from ⌘K (the list of
/// ~/.ssh/config's hosts, each with how it answered) and test them again.
@MainActor
public enum SSHCommands {
    /// `connect` opens a terminal tab running `ssh <alias>` (the app's).
    public static func all(palette: CommandPaletteController, connect: @escaping @MainActor (String) -> Void) -> [Command] {
        [
            Command(id: "ssh.connect", title: T("Connect with SSH", "Conectar por SSH"),
                    keywords: ["ssh", "server", "vps", "host", "servidor", "conectar"], category: .terminal,
                    action: .run { palette.open(SSHHostSource(connect: connect)) }),
            Command(id: "ssh.test-again", title: T("Test SSH Hosts Again", "Testar os hosts SSH de novo"),
                    keywords: ["ssh", "ping", "vps", "server", "testar"], category: .terminal,
                    action: .run { SSHController.shared.testNow() },
                    unavailableReason: { SSHController.shared.hosts.isEmpty ? T("No hosts in ~/.ssh/config", "Nenhum host no ~/.ssh/config") : nil }),
        ]
    }

    /// "up 20 ms", "down", "via bastion".
    public static func describe(_ reach: SSHController.Reach, host: SSHHost) -> String {
        switch reach {
        case .up(let ms): T("up \(ms) ms", "no ar, \(ms) ms")
        case .down: T("down", "fora do ar")
        case .testing: T("testing…", "testando…")
        case .proxied: T("via ", "via ") + (host.proxy ?? "")
        case .unknown: ""
        }
    }
}

/// ⌘K's list of hosts; choosing one connects.
@MainActor
final class SSHHostSource: PaletteSource {
    private let connect: (String) -> Void

    init(connect: @escaping (String) -> Void) { self.connect = connect }

    var placeholder: String { T("Connect to a host", "Conectar a um host") }
    var emptyText: String { T("No such host in ~/.ssh/config", "Nenhum host assim no ~/.ssh/config") }
    var icon: Icon { .terminalWindow }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        // Hosts are listed without testing them: the palette asks nothing of the network.
        let controller = SSHController.shared
        let hosts = controller.hosts.isEmpty ? SSHConfig.hosts(at: controller.config, home: controller.home) : controller.hosts
        let items = hosts.filter { query.isEmpty || $0.alias.localizedCaseInsensitiveContains(query) }.map { host in
            PaletteItem(id: host.alias, title: host.alias,
                        detail: SSHCommands.describe(controller.reach[host.alias] ?? .unknown, host: host), icon: .terminalWindow)
        }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) { connect(item.id) }

    func stop() {}
}
