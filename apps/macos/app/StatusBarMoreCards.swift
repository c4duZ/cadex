import AppKit
import CommandPalette
import Darwin
import Icons
import Machines
import Menus
import StatusBar
import Terminal
import Strings
import UILooks

/// More status bar cards (docs/spec/status-bar.md, Os cartões): Ports, Folder, Environment,
/// Keep awake, Update, Docker and the Tailscale item, and ports.stop. Built when they open.
extension WindowSession {
    /// The listening ports with the process of each and the terminal it runs in.
    func portsCard(close: @escaping () -> Void) -> NSView {
        let names = Dictionary(cadexTerminals().map { ($0.group, $0.name) }, uniquingKeysWith: { a, _ in a })
        var rows: [StatusCard.Row] = []
        for listener in listeners {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let group = proc_pidinfo(listener.pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? Int32(info.pbi_pgid) : 0
            let process = ProcessTable.displayName(path: Self.path(of: listener.pid))
            let detail = [process, "pid \(listener.pid)", names[group]].compactMap { $0 }.joined(separator: " · ")
            let port = listener.port
            rows.append(.init("localhost:\(port)", detail: detail, value: T("Open", "Abrir")) { [weak self] in
                self?.openPreview("http://localhost:\(port)")
            })
        }
        var blocks: [StatusCard.Block] = [.header(T("Ports", "Portas"), detail: T("listening in Cadex's terminals", "ouvindo nos terminais do Cadex"))]
        blocks.append(rows.isEmpty ? .note(T("No program in your terminals is listening.", "Nenhum programa dos terminais está ouvindo.")) : .rows(rows))
        if !rows.isEmpty {
            blocks.append(.actions([.init(T("Stop a port…", "Parar uma porta…")) { [weak self] in _ = self?.commands.run("ports.stop") },
                                    .init(T("Share on the tailnet…", "Compartilhar na tailnet…")) { [weak self] in _ = self?.commands.run("machines.share-port") }]))
        }
        return StatusCard.build(blocks, close: close)
    }

    /// The folder: what takes room in it (measured when the card opens, off the main thread) and
    /// the disk's free space, amber under 10%.
    func folderCard(close: @escaping () -> Void) -> NSView {
        let root = tabs?.activeTerminal?.currentDirectory ?? folder.root
        let name = (root as NSString).lastPathComponent
        var blocks: [StatusCard.Block] = []
        if let sizes = folderSizes, sizes.folder == root {
            blocks.append(.header(name, detail: ProcessTable.size(sizes.total)))
            blocks += [.section(T("What takes room", "O que ocupa espaço")),
                       .rows(sizes.largest.map { .init($0.name, value: ProcessTable.size($0.bytes)) })]
        } else {
            blocks.append(.header(name, detail: T("measuring…", "medindo…")))
            measureFolder(root)
        }
        if let disk = try? URL(fileURLWithPath: root).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let free = disk.volumeAvailableCapacityForImportantUsage, let total = disk.volumeTotalCapacity, total > 0 {
            let share = Double(free) / Double(total)
            blocks += [.section(T("Disk", "Disco")), .bar([(1 - share, share < 0.1 ? DesignTokens.Color.stateNeeds : DesignTokens.Color.stateWorking)]),
                       .note(T("\(ProcessTable.size(UInt64(free))) free of \(ProcessTable.size(UInt64(total)))",
                               "\(ProcessTable.size(UInt64(free))) livres de \(ProcessTable.size(UInt64(total)))"), warn: share < 0.1)]
        }
        blocks.append(.actions([.init(T("Show in Finder", "Mostrar no Finder")) { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: root) },
                                .init(T("Copy path", "Copiar o caminho")) { [weak self] in _ = self?.commands.run("project.copy-path") }]))
        return StatusCard.build(blocks, close: close)
    }

    /// The folder's size and its five largest entries, counted on a background queue; the card
    /// is drawn again when done. One measure at a time.
    private func measureFolder(_ root: String) {
        guard measuringFolder != root else { return }
        measuringFolder = root
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            let sizes = entries.map { entry in (name: entry, bytes: Self.allocated(root + "/" + entry)) }
            let largest = Array(sizes.sorted { $0.bytes > $1.bytes }.prefix(5))
            let total = sizes.map(\.bytes).reduce(0, +)
            DispatchQueue.main.async {
                guard let self else { return }
                self.folderSizes = (root, total, largest)
                self.measuringFolder = nil
                self.folderCard?.refresh()
            }
        }
    }

    nonisolated private static func allocated(_ path: String) -> UInt64 {
        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        guard values.isDirectory == true else { return UInt64(values.totalFileAllocatedSize ?? 0) }
        var sum: UInt64 = 0
        let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [], errorHandler: { _, _ in true })
        while let item = walk?.nextObject() as? URL {
            sum += UInt64((try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return sum
    }

    /// Where programs run: this Mac, its system and shell; the other machines to start a task on.
    func environmentCard(close: @escaping () -> Void) -> NSView {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var arch = utsname()
        uname(&arch)
        let machine = withUnsafeBytes(of: &arch.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        let shell = (ProcessInfo.processInfo.environment["SHELL"] as NSString?)?.lastPathComponent ?? "zsh"
        var blocks: [StatusCard.Block] = [
            .header(T("This Mac", "Este Mac"), detail: Host.current().localizedName),
            .rows([.init("macOS \(version.majorVersion).\(version.minorVersion)", value: machine == "arm64" ? "Apple silicon" : "Intel"),
                   .init(shell, detail: T("with Cadex's integration", "com a integração do Cadex"))]),
        ]
        if let status = MachinesController.shared.status, status.isRunning, !status.others.isEmpty {
            blocks += [.section(T("Also on your tailnet", "Também na sua tailnet")),
                       .rows(status.others.map { .init($0.name, detail: $0.os, dot: $0.online ? DesignTokens.Color.stateDone : DesignTokens.Color.textTertiary) })]
        }
        blocks.append(.actions([.init(T("New task on…", "Nova tarefa em…")) { [weak self] in _ = self?.commands.run("worktrees.new-task-on") }]))
        return StatusCard.build(blocks, close: close)
    }

    /// Keep awake: on or off, the mode, since when, until when, and what holds the computer now.
    func keepAwakeCard(close: @escaping () -> Void) -> NSView {
        let power = app.power
        let on = power.mode != .off
        let time = DateFormatter.localizedString(from: power.since ?? Date(), dateStyle: .none, timeStyle: .short)
        var rows: [StatusCard.Row] = []
        switch power.mode {
        case .off: rows.append(.init(T("The computer may sleep", "O computador pode dormir")))
        case .always: rows.append(.init(T("Always", "Sempre"), detail: T("since ", "desde ") + time, value: power.since.map { TerminalCommand.duration(since: $0) }))
        case .running: rows.append(.init(T("While a program runs", "Com programa rodando"), detail: T("since ", "desde ") + time,
                                         value: power.isHolding ? T("holding", "segurando") : T("waiting", "esperando")))
        }
        if let until = power.until {
            rows.append(.init(T("Until ", "Até ") + DateFormatter.localizedString(from: until, dateStyle: .none, timeStyle: .short)))
        }
        rows.append(.init(settings.store.settings.power.keepDisplayOn ? T("The display stays on", "A tela fica acesa") : T("The display may sleep", "A tela pode apagar")))
        let blocks: [StatusCard.Block] = [
            .header(T("Keep awake", "Manter acordado"), detail: on ? T("on", "ligado") : T("off", "desligado")),
            .rows(rows),
            .actions([.init(on ? T("Turn off", "Desligar") : T("Turn on", "Ligar")) { [weak self] in _ = self?.commands.run("power.toggle") },
                      .init(T("While a program runs", "Com programa rodando")) { [weak self] in _ = self?.commands.run("power.keep-awake-while-running") },
                      .init(T("For 1 hour", "Por 1 hora")) { [weak self] in _ = self?.commands.run("power.keep-awake-hour") }]),
        ]
        return StatusCard.build(blocks, close: close)
    }

    /// The new version and the first lines of its notes.
    func updateCard(close: @escaping () -> Void) -> NSView {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var blocks: [StatusCard.Block] = [.header("Cadex " + (app.updates.pendingVersion ?? current), detail: T("you have ", "você tem ") + current)]
        if case .available(let release) = app.updates.state {
            let lines = release.notes.split(separator: "\n").map(String.init).filter { $0.hasPrefix("- ") }.prefix(4)
            blocks.append(.rows(lines.map { .init(Self.plain($0)) }))
        } else {
            blocks.append(.note(app.updates.buttonTip))
        }
        blocks.append(.actions([.init(T("Update and reopen", "Atualizar e reabrir")) { [weak self] in _ = self?.commands.run("app.check-for-updates") },
                                .init(T("Skip this version", "Pular esta versão")) { [weak self] in _ = self?.commands.run("app.skip-update") }]))
        return StatusCard.build(blocks, close: close)
    }

    /// The cards of the items made elsewhere (the bar's own folder and environment; keep awake,
    /// update and Docker, whose views are labels) and ports.stop.
    func attachItemCards(_ bar: StatusBarView) {
        if let view = bar.itemView("folder") { folderCard = attachCard(to: view) { [weak self] close in self?.folderCard(close: close) ?? NSView() } }
        if let view = bar.itemView("environment") { attachCard(to: view) { [weak self] close in self?.environmentCard(close: close) ?? NSView() } }
        if let view = keepAwakeLabel { attachCard(to: view) { [weak self] close in self?.keepAwakeCard(close: close) ?? NSView() } }
        if let view = updateLabel { attachCard(to: view) { [weak self] close in self?.updateCard(close: close) ?? NSView() } }
        if let view = dockerLabel { attachCard(to: view) { [weak self] close in self?.dockerCard(close: close) ?? NSView() } }
        commands.register(Command(id: "ports.stop", title: T("Stop a Listening Port", "Parar uma porta ouvindo"),
                                  keywords: ["port", "porta", "kill", "stop", "parar", "server", "servidor", "localhost"], category: .terminal,
                                  action: .run { [weak self] in self?.chooseStopPort() },
                                  unavailableReason: { [weak self] in self?.listeners.isEmpty != false ? T("No program is listening", "Nenhum programa ouvindo") : nil }))
    }

    /// ports.stop: the listening ports in ⌘K; the chosen one's process gets SIGTERM.
    private func chooseStopPort() {
        let items = listeners.map { listener in
            PaletteItem(id: "\(listener.pid)", title: "localhost:\(listener.port)",
                        detail: ProcessTable.displayName(path: Self.path(of: listener.pid)) + " · pid \(listener.pid)")
        }
        palette?.open(ChoiceSource(placeholder: T("Stop which port?", "Parar qual porta?"), empty: T("No such port", "Nenhuma porta assim"),
                                  icon: .plug, items: items) { [weak self] id in
            guard let pid = Int32(id), pid > 0 else { return }
            kill(pid, SIGTERM)
            if let label = self?.portsLabel { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.readPorts(into: label) } }
        })
    }

    /// Docker: the tab's context and the containers running there, asked when the card opens.
    func dockerCard(close: @escaping () -> Void) -> NSView {
        let context = tabs?.activeTerminal.flatMap { dockerContexts[ObjectIdentifier($0)] }
        var blocks: [StatusCard.Block] = [.header("Docker", detail: T("context: ", "contexto: ") + (context ?? "default"))]
        var args = ["ps", "--format", "{{.Names}}\u{1f}{{.Image}}\u{1f}{{.Status}}"]
        if let context { args = ["--context", context] + args }
        if let out = Self.runForCard("/usr/local/bin/docker", args) ?? Self.runForCard("/opt/homebrew/bin/docker", args) {
            let rows = out.split(separator: "\n").map { $0.split(separator: "\u{1f}").map(String.init) }.filter { $0.count == 3 }
                .map { StatusCard.Row($0[0], detail: $0[1], value: $0[2]) }
            blocks.append(rows.isEmpty ? .note(T("No container running.", "Nenhum contêiner rodando.")) : .rows(rows))
        } else {
            blocks.append(.note(T("Docker is not running here.", "O Docker não está rodando aqui.")))
        }
        blocks.append(.actions([.init(T("Use another machine's Docker…", "Usar o Docker de outra máquina…")) { [weak self] in
            _ = self?.commands.run("machines.docker-context")
        }]))
        return StatusCard.build(blocks, close: close)
    }

    /// "- **A slim header** on each pane…" as plain text.
    static func plain(_ line: String) -> String {
        String(line.dropFirst(2)).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    }

    /// The executable's path of a process, for its name.
    static func path(of pid: Int32) -> String {
        var path = [CChar](repeating: 0, count: 4096)
        return proc_pidpath(pid, &path, UInt32(path.count)) > 0 ? String(cString: path) : ""
    }
}

/// A plain list for ⌘K: titles and details, choosing one runs `choose` with its id.
@MainActor
final class ChoiceSource: PaletteSource {
    private let items: [PaletteItem]
    private let pick: (String) -> Void
    let placeholder: String
    let emptyText: String
    let icon: Icon

    init(placeholder: String, empty: String, icon: Icon, items: [PaletteItem], pick: @escaping (String) -> Void) {
        self.placeholder = placeholder
        self.emptyText = empty
        self.icon = icon
        self.items = items
        self.pick = pick
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        show(items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.detail ?? "").localizedCaseInsensitiveContains(query) }, nil)
    }

    func choose(_ item: PaletteItem) { pick(item.id) }
    func stop() {}
    var width: CGFloat? { nil }
    var showsFooter: Bool { true }
}
