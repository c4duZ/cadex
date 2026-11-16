import AppKit
import CommandPalette
import Icons
import Strings

/// What the app does for the Docker commands: the tab, the preview, the
/// user each machine logs in as.
public struct DockerActions {
    /// machines.docker-context: the focused tab on `machine`'s Docker, or
    /// back on this Mac's with nil.
    public var useContext: @MainActor (Machine?) -> Void
    public var openShell: @MainActor (Machine, DockerContainer) -> Void
    public var openPort: @MainActor (Machine, Int) -> Void
    /// `user@pc.tail1234.ts.net`, the context's ssh destination.
    public var destination: @MainActor (Machine) -> String

    public init(useContext: @escaping @MainActor (Machine?) -> Void, openShell: @escaping @MainActor (Machine, DockerContainer) -> Void,
                openPort: @escaping @MainActor (Machine, Int) -> Void, destination: @escaping @MainActor (Machine) -> String) {
        self.useContext = useContext
        self.openShell = openShell
        self.openPort = openPort
        self.destination = destination
    }
}

/// machines.docker-context and machines.docker-ps (ADR 0005, ADR 0032).
@MainActor
public enum DockerCommands {
    public static func all(palette: CommandPaletteController, actions: DockerActions) -> [Command] {
        let unavailable: @MainActor () -> String? = {
            Docker.binary() == nil ? T("Docker is not installed on this Mac", "O Docker não está instalado neste Mac") : nil
        }
        return [
            Command(id: "machines.docker-context", title: T("Use a Machine's Docker in This Tab…", "Usar o Docker de uma máquina nesta aba…"),
                    keywords: ["docker", "context", "contexto", "tailnet", "remote", "remoto", "pc"], category: .terminal,
                    action: .run { palette.open(DockerMachineSource(palette: palette, actions: actions, listing: false)) },
                    unavailableReason: unavailable),
            Command(id: "machines.docker-ps", title: T("Show a Machine's Containers…", "Mostrar os contêineres de uma máquina…"),
                    keywords: ["docker", "ps", "containers", "contêineres", "tailnet", "pc"], category: .terminal,
                    action: .run { palette.open(DockerMachineSource(palette: palette, actions: actions, listing: true)) },
                    unavailableReason: unavailable),
        ]
    }
}

/// ⌘K's machines for the two commands; for the context, "This Mac" first.
@MainActor
final class DockerMachineSource: PaletteSource {
    private weak var palette: CommandPaletteController?
    private let actions: DockerActions
    private let listing: Bool

    init(palette: CommandPaletteController, actions: DockerActions, listing: Bool) {
        self.palette = palette
        self.actions = actions
        self.listing = listing
    }

    var placeholder: String { listing ? T("Whose containers", "Os contêineres de qual máquina") : T("Whose Docker this tab uses", "O Docker de qual máquina esta aba usa") }
    var emptyText: String { T("No machine online on your tailnet", "Nenhuma máquina no ar na sua tailnet") }
    var icon: Icon { .stack }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let controller = MachinesController.shared
        let list = { [listing] in
            var items = listing ? [] : [PaletteItem(id: "", title: T("This Mac", "Este Mac"), detail: "unset DOCKER_CONTEXT", icon: .stack)]
            items += (controller.status?.others ?? []).filter { $0.online && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
                .map { PaletteItem(id: $0.id, title: $0.name, detail: [$0.os, $0.address].joined(separator: " · "), icon: .globe) }
            show(items, nil)
        }
        if controller.status == nil { controller.refresh(list) } else { list() }
    }

    func choose(_ item: PaletteItem) {
        if item.id.isEmpty { return actions.useContext(nil) }
        guard let machine = MachinesController.shared.status?.others.first(where: { $0.id == item.id }) else { return }
        if listing { palette?.open(ContainerSource(machine: machine, actions: actions)) } else { actions.useContext(machine) }
    }

    func stop() {}
}

/// ⌘K's containers of one machine: a row to open its shell, and one per
/// published port to open it in the preview.
@MainActor
final class ContainerSource: PaletteSource {
    let machine: Machine
    private let actions: DockerActions
    private var loaded: Result<[DockerContainer], DockerError>?
    private var pending: [(String, @MainActor ([PaletteItem], String?) -> Void)] = []

    init(machine: Machine, actions: DockerActions) {
        self.machine = machine
        self.actions = actions
    }

    var placeholder: String { T("Containers on ", "Contêineres em ") + machine.name }
    var emptyText: String { T("No containers", "Nenhum contêiner") }
    var icon: Icon { .stack }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let loaded else {
            pending.append((query, show))
            if pending.count == 1 { load() }
            return show([], T("reading…", "lendo…"))
        }
        switch loaded {
        case .failure(.message(let message)): show([], message)
        case .success(let containers): show(Self.items(containers, machine: machine, query: query), nil)
        }
    }

    static func items(_ containers: [DockerContainer], machine: Machine, query: String) -> [PaletteItem] {
        containers.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.image.localizedCaseInsensitiveContains(query) }
            .flatMap { container -> [PaletteItem] in
                let shell = PaletteItem(id: "shell\u{0}" + container.name, title: container.name,
                                        detail: [container.image, container.status].filter { !$0.isEmpty }.joined(separator: " · "), icon: .terminalWindow)
                let ports = container.ports.map {
                    PaletteItem(id: "port\u{0}" + container.name + "\u{0}\($0)", title: "\(container.name)  :\($0)",
                                detail: T("open in preview", "abrir no preview") + "  http://\(machine.address):\($0)", icon: .globe)
                }
                return [shell] + (container.state == "running" ? ports : [])
            }
    }

    private func load() {
        Task { [weak self] in
            guard let self else { return }
            if let error = await Docker.ensureContext(machine, destination: actions.destination(machine)) {
                loaded = .failure(.message(error))
            } else {
                loaded = await Docker.containers(on: machine)
            }
            for (query, show) in pending { search(query, show: show) }
            pending = []
        }
    }

    func choose(_ item: PaletteItem) {
        guard case .success(let containers) = loaded else { return }
        let parts = item.id.split(separator: "\u{0}").map(String.init)
        guard parts.count >= 2, let container = containers.first(where: { $0.name == parts[1] }) else { return }
        if parts[0] == "shell" { actions.openShell(machine, container) }
        if parts[0] == "port", parts.count == 3, let port = Int(parts[2]) { actions.openPort(machine, port) }
    }

    func stop() {}
}
