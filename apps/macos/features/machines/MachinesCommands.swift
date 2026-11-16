import AppKit
import CommandPalette
import Icons
import Strings

/// The machines' commands (ADR 0005): connect, ping, refresh and copy the
/// address, each listing the tailnet's machines in ⌘K. The palette reads
/// the daemon once when it opens on them, never more.
@MainActor
public enum MachinesCommands {
    /// `connect(machine, askUser)`: the app opens the ssh tab; `askUser`
    /// (⌥↩) asks the user name again.
    public static func all(palette: CommandPaletteController,
                           connect: @escaping @MainActor (Machine, Bool) -> Void) -> [Command] {
        let controller = MachinesController.shared
        let unavailable: @MainActor () -> String? = {
            guard controller.isEnabled else { return T("Tailnet machines are off in Settings", "As máquinas da tailnet estão desligadas nas configurações") }
            return controller.daemon.find() == nil ? T("Tailscale is not running", "O Tailscale não está rodando") : nil
        }
        return [
            Command(id: "machines.connect", title: T("Connect to a Tailnet Machine", "Conectar a uma máquina da tailnet"),
                    keywords: ["tailscale", "tailnet", "ssh", "machine", "máquina", "pc", "remote", "remoto"], category: .terminal,
                    action: .run { palette.open(MachineSource(kind: .connect, palette: palette, connect: connect)) },
                    unavailableReason: unavailable),
            Command(id: "machines.ping", title: T("Ping a Tailnet Machine", "Medir a latência de uma máquina da tailnet"),
                    keywords: ["tailscale", "tailnet", "ping", "latency", "latência"], category: .terminal,
                    action: .run { palette.open(MachineSource(kind: .ping, palette: palette, connect: connect)) },
                    unavailableReason: unavailable),
            Command(id: "machines.refresh", title: T("Refresh Tailnet Machines", "Atualizar as máquinas da tailnet"),
                    keywords: ["tailscale", "tailnet", "machines", "máquinas", "reload"], category: .terminal,
                    action: .run { controller.refresh() }, unavailableReason: unavailable),
            Command(id: "machines.copy-address", title: T("Copy a Tailnet Machine's Address", "Copiar o endereço de uma máquina da tailnet"),
                    keywords: ["tailscale", "tailnet", "address", "endereço", "magicdns", "ip"], category: .terminal,
                    action: .run { palette.open(MachineSource(kind: .copy, palette: palette, connect: connect)) },
                    unavailableReason: unavailable),
        ]
    }

    /// The MagicDNS name, or with `ip` the 100.x address, on the clipboard.
    public static func copy(_ machine: Machine, ip: Bool) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip ? machine.ip : machine.address, forType: .string)
    }
}

/// ⌘K's list of machines for one of the commands.
@MainActor
final class MachineSource: PaletteSource {
    enum Kind { case connect, ping, copy }

    private let kind: Kind
    private weak var palette: CommandPaletteController?
    private let connect: (Machine, Bool) -> Void
    /// The last ping's answer, shown on the right of the field when the
    /// palette opens again with it.
    var result: String?

    init(kind: Kind, palette: CommandPaletteController, connect: @escaping (Machine, Bool) -> Void) {
        self.kind = kind
        self.palette = palette
        self.connect = connect
    }

    var placeholder: String {
        switch kind {
        case .connect: T("Connect to a machine", "Conectar a uma máquina")
        case .ping: T("Ping a machine", "Medir uma máquina")
        case .copy: T("Copy a machine's address", "Copiar o endereço de uma máquina")
        }
    }
    var emptyText: String { T("No such machine on your tailnet", "Nenhuma máquina assim na sua tailnet") }
    var icon: Icon { .globe }
    var hints: [PaletteHint] {
        switch kind {
        case .connect: [PaletteHint("↩", T("connect", "conectar")), PaletteHint("⌥↩", T("another user", "outro usuário"))]
        case .ping: [PaletteHint("↩", T("ping", "medir"))]
        case .copy: [PaletteHint("↩", T("copy name", "copiar nome")), PaletteHint("⌥↩", T("copy IP", "copiar IP"))]
        }
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let controller = MachinesController.shared
        let list = { [kind, result] in
            let machines = (controller.status?.others ?? []).filter { kind == .copy || $0.online }
            let items = machines.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.address.localizedCaseInsensitiveContains(query) }
                .map { machine in
                    PaletteItem(id: machine.id, title: machine.name,
                                detail: [machine.os, MachinesSection.describe(machine, ping: controller.pings[machine.id] ?? nil)].filter { !$0.isEmpty }.joined(separator: " · "),
                                icon: .globe)
                }
            show(items, result)
        }
        if controller.status == nil { controller.refresh(list) } else { list() }
    }

    func choose(_ item: PaletteItem) { choose(item, as: .primary) }

    func choose(_ item: PaletteItem, as choice: PaletteChoice) {
        let controller = MachinesController.shared
        guard let machine = controller.status?.others.first(where: { $0.id == item.id }) else { return }
        switch kind {
        case .connect:
            connect(machine, choice != .primary)
        case .copy:
            MachinesCommands.copy(machine, ip: choice != .primary)
        case .ping:
            controller.ping(machine)
            waitForPing(machine)
        }
    }

    /// The palette closed on the choice: it opens again with the answer.
    private func waitForPing(_ machine: Machine) {
        var token: UUID?
        token = MachinesController.shared.watchPings { [weak self] in
            guard let self, let answer = MachinesController.shared.pings[machine.id] ?? nil else { return }
            if let id = token { MachinesController.shared.stopWatchingPings(id) }
            self.result = machine.name + ": " + MachinesSection.describe(machine, ping: answer)
            self.palette?.open(self)
        }
    }

    func stop() {}
}
