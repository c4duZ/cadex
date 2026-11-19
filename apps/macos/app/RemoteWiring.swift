import AppKit
import CommandPalette
import Icons
import Machines
import SSH
import Strings

/// Remote at the rail's foot (plan 36 phase F; docs/adr/0038-rail-and-side-column.md): the hosts of
/// ~/.ssh/config and the tailnet's machines in one list, choosing one connects in a tab. The
/// button shows only when there is some host; the status bar's SSH item, off by default, was where
/// this lived and almost nobody saw it.
extension WindowSession {
    func remoteCommands() -> [Command] {
        [Command(id: "remote.show", title: T("Connect to a Remote Machine…", "Conectar a uma máquina remota…"),
                 keywords: ["remote", "ssh", "tailnet", "tailscale", "machine", "server", "host", "remoto", "máquina", "servidor"],
                 category: .terminal,
                 action: .run { [weak self] in
                     guard let self else { return }
                     self.palette?.open(RemoteSource(window: self))
                 })]
    }

    /// Whether the rail shows Remote: an SSH host, or a tailnet machine other than this Mac (as
    /// last read; the tailnet is not read for the button alone).
    var hasRemote: Bool {
        !Self.sshHosts().isEmpty || !(MachinesController.shared.status?.others.isEmpty ?? true)
    }

    /// The hosts the SSH feature read, else ~/.ssh/config's, read again at most every 30 s (the
    /// rail asks on every redraw).
    static func sshHosts() -> [SSHHost] {
        let read = SSHController.shared.hosts
        guard read.isEmpty else { return read }
        if let cached = RemoteHosts.cached, cached.at.timeIntervalSinceNow > -30 { return cached.hosts }
        let hosts = SSHConfig.hosts(at: NSHomeDirectory() + "/.ssh/config")
        RemoteHosts.cached = (Date(), hosts)
        return hosts
    }
}

/// The list: SSH hosts first (with how each answered), then the tailnet's other machines (online
/// first). The tailnet is read again while the list is open.
@MainActor
final class RemoteSource: PaletteSource {
    private weak var window: WindowSession?

    init(window: WindowSession) { self.window = window }

    var placeholder: String { T("Connect to a remote machine", "Conectar a uma máquina remota") }
    var emptyText: String { T("No SSH host nor tailnet machine", "Nenhum host SSH nem máquina da tailnet") }
    var icon: Icon { .globe }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        show(items(query), nil)
        MachinesController.shared.refresh { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                show(self.items(query), nil)
            }
        }
    }

    private func items(_ query: String) -> [PaletteItem] {
        let matches: (String) -> Bool = { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        let ssh = WindowSession.sshHosts().filter { matches($0.alias) }.map { host in
            let reach = SSHCommands.describe(SSHController.shared.reach[host.alias] ?? .unknown, host: host)
            return PaletteItem(id: "ssh:" + host.alias, title: host.alias,
                               detail: ["SSH", reach].filter { !$0.isEmpty }.joined(separator: " · "), icon: .terminalWindow)
        }
        let others = (MachinesController.shared.status?.others ?? []).sorted { $0.online && !$1.online }
        let tailnet = others.filter { matches($0.name) }.map { machine in
            PaletteItem(id: "tailnet:" + machine.name, title: machine.name,
                        detail: "Tailnet · " + (machine.online ? T("online", "online") : T("offline", "offline")), icon: .hardDrives)
        }
        return ssh + tailnet
    }

    func choose(_ item: PaletteItem) {
        guard let window else { return }
        if item.id.hasPrefix("ssh:") { return window.connectSSH(String(item.id.dropFirst(4))) }
        let name = String(item.id.dropFirst("tailnet:".count))
        if let machine = MachinesController.shared.status?.others.first(where: { $0.name == name }) {
            window.connectMachine(machine, askUser: false)
        }
    }

    func stop() {}
}

/// The last read of ~/.ssh/config for the rail's Remote.
@MainActor
enum RemoteHosts {
    static var cached: (at: Date, hosts: [SSHHost])?
}
