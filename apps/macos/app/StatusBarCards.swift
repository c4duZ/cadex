import AppKit
import Menus
import Memory
import StatusBar
import Strings
import Terminal
import UILooks

/// The cards of the app's status bar items (docs/spec/status-bar.md, Os cartões; the proposal
/// approved on 2026-11-18): Agents, Terminals (the drawer's item too), Project and Memory. Each is
/// built when it opens, from what the window already knows; git is asked only then.
extension WindowSession {
    /// The pointer over `view` opens `content`; returns the card for a click to open it at once.
    @discardableResult
    func attachCard(to view: NSView, _ content: @escaping (_ close: @escaping () -> Void) -> NSView) -> HoverCard {
        var card: HoverCard?
        card = HoverCard(over: view) { content { card?.close() } }
        statusCards.append(card!)
        return card!
    }

    /// Every agent in every window: the ones that need you, then working, then done, then idle.
    func agentsCard(close: @escaping () -> Void) -> NSView {
        var needs: [StatusCard.Row] = [], working: [StatusCard.Row] = [], done: [StatusCard.Row] = [], idle: [StatusCard.Row] = []
        for window in app.sessions {
            for project in window.projects?.projects ?? [] {
                for terminal in project.tabs.allTerminals {
                    guard let status = terminal.agentStatus, status.state != .none else { continue }
                    let key = AppDelegate.key(terminal)
                    let go: () -> Void = { [weak app] in app?.goToAgent(key: key, pid: 0) }
                    let pane = PaneDetails.shared.byTerminal[ObjectIdentifier(terminal)]
                    let quiet = terminal.agentQuietSince.map { TerminalCommand.duration(since: $0) }
                    switch status.state {
                    case .blocked:
                        needs.append(.init(project.name, detail: status.message.isEmpty ? nil : status.message, value: quiet,
                                           dot: DesignTokens.Color.stateNeeds, action: go))
                    case .working:
                        working.append(.init(project.name, detail: pane?.detail, value: pane?.trailing.components(separatedBy: " · ").last,
                                             dot: DesignTokens.Color.stateWorking, action: go))
                    case .done, .failed:
                        done.append(.init(project.name, detail: terminal.agentFinishedUnseen ? T("unseen", "não visto") : pane?.detail, value: quiet,
                                          dot: status.state == .failed ? DesignTokens.Color.stateFailed : DesignTokens.Color.stateDone, action: go))
                    default:
                        idle.append(.init(project.name, detail: pane?.detail, value: quiet, dot: DesignTokens.Color.textTertiary, action: go))
                    }
                }
            }
        }
        let count = needs.count + working.count + done.count + idle.count
        var blocks: [StatusCard.Block] = [.header(T("Agents", "Agentes"), detail: T("\(count) in every window", "\(count) em todas as janelas"))]
        for (title, rows) in [(T("Needs you", "Precisa de você"), needs), (T("Working", "Trabalhando"), working),
                              (T("Done", "Pronto"), done), (T("Waiting at the prompt", "Parados no prompt"), idle)] where !rows.isEmpty {
            blocks += [.section(title), .rows(rows)]
        }
        if count == 0 { blocks.append(.note(T("No agent is running.", "Nenhum agente rodando."))) }
        blocks.append(.actions([.init(T("Open the board", "Abrir o quadro")) { [weak self] in _ = self?.commands.run("view.board") },
                                .init(T("Notifications", "Notificações")) { [weak self] in _ = self?.commands.run("agents.show-attention") }]))
        return StatusCard.build(blocks, close: close)
    }

    /// This window's terminals: what each runs and for how long; the drawer's too.
    func terminalsCard(close: @escaping () -> Void) -> NSView {
        let home = NSHomeDirectory()
        func row(_ terminal: TerminalView, _ place: String) -> StatusCard.Row {
            let key = AppDelegate.key(terminal)
            let running = terminal.command.running.map(TerminalCommand.shortName)
            let folder = (terminal.currentDirectory ?? "").replacingOccurrences(of: home, with: "~")
            let since = terminal.command.startedAt.map { TerminalCommand.duration(since: $0) }
            return .init(running ?? (terminal.agentStatus != nil ? "claude" : T("shell", "shell")), detail: [place, folder].filter { !$0.isEmpty }.joined(separator: " · "),
                         value: running == nil ? T("idle", "parado") : since, action: { [weak app] in app?.goToAgent(key: key, pid: 0); return })
        }
        let projects = projects?.projects ?? []
        var rows = projects.flatMap { project in project.tabs.allTerminals.map { row($0, project.name) } }
        let drawerRows = drawer?.tabs.allTerminals.map { row($0, T("drawer", "gaveta")) } ?? []
        rows += drawerRows
        let blocks: [StatusCard.Block] = [
            .header(T("Terminals", "Terminais"), detail: T("\(rows.count) open · \(drawerRows.count) in the drawer", "\(rows.count) abertos · \(drawerRows.count) na gaveta")),
            .rows(rows),
            .actions([.init(T("New terminal", "Novo terminal")) { [weak self] in _ = self?.commands.run("tab.new") },
                      .init(T("Drawer ", "Gaveta ") + (app.keymapLabel("drawer.toggle") ?? "⌃`")) { [weak self] in _ = self?.commands.run("drawer.toggle") }]),
        ]
        return StatusCard.build(blocks, close: close)
    }

    /// The project: the branch against its remote, what changed, the last commit and the last check.
    func projectCard(close: @escaping () -> Void) -> NSView {
        let root = folder.root
        let name = TitleBarView.location(of: root).project ?? (root as NSString).lastPathComponent
        var rows: [StatusCard.Row] = []
        if let branch = lastBranch {
            rows.append(.init(branch.name, detail: T("against its remote", "contra o remoto"), value: "↑\(branch.ahead) · ↓\(branch.behind)",
                              warn: branch.ahead > 0 || branch.behind > 0))
        }
        let changed = Self.cardGit(["status", "--porcelain"], in: root)?.split(separator: "\n").count ?? 0
        rows.append(.init(changed == 0 ? T("Nothing changed", "Nada mudou") : T("\(changed) files changed", "\(changed) arquivos mudaram"),
                          action: { [weak self] in _ = self?.commands.run("git.show") }))
        if let last = Self.cardGit(["log", "-1", "--format=%s%x1f%cr"], in: root)?.split(separator: "\u{1f}").map(String.init), last.count == 2 {
            rows.append(.init(last[0], value: last[1].trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        let blocks: [StatusCard.Block] = [
            .header(name, detail: root.replacingOccurrences(of: NSHomeDirectory(), with: "~")),
            .rows(rows),
            .actions([.init(T("Changes", "Mudanças")) { [weak self] in _ = self?.commands.run("git.show") },
                      .init("Push") { [weak self] in _ = self?.commands.run("git.push") },
                      .init(T("Switch branch…", "Trocar de branch…")) { [weak self] in _ = self?.commands.run("git.switch-branch") }]),
        ]
        return StatusCard.build(blocks, close: close)
    }

    /// The project's memory: the pages that changed last, read from its wiki when the card opens.
    func memoryCard(close: @escaping () -> Void) -> NSView {
        guard settings.store.settings.memory.enabled else {
            return StatusCard.build([.header(T("Memory", "Memória"), detail: T("off", "desligada")),
                                     .note(MemoryStatusText.offText),
                                     .actions([.init(T("Open Memory", "Abrir a memória")) { [weak self] in _ = self?.commands.run("memory.show") }])], close: close)
        }
        var pages: [(name: String, date: Date)] = []
        if let wiki = MemoryPageState.wikiDir(overview: nil, root: projectRoot, folder: MemoryKit.folder()),
           let found = FileManager.default.enumerator(at: URL(fileURLWithPath: wiki), includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let url as URL in found where url.pathExtension == "md" && !url.lastPathComponent.hasPrefix("_") {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                pages.append((url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "-", with: " "), date))
            }
        }
        let recent = pages.sorted { $0.date > $1.date }.prefix(4)
        let blocks: [StatusCard.Block] = [
            .header(T("Memory", "Memória"), detail: T("\(pages.count) pages", "\(pages.count) páginas")),
            .section(T("Changed lately", "Mudaram por último")),
            .rows(recent.map { .init($0.name, value: TerminalCommand.duration(since: $0.date)) }),
            .actions([.init(T("Open Memory", "Abrir a memória")) { [weak self] in _ = self?.commands.run("memory.show") },
                      .init(T("Consolidate now", "Consolidar agora")) { [weak self] in _ = self?.commands.run("memory.consolidate-now") }]),
        ]
        return StatusCard.build(blocks, close: close)
    }

    /// A short git question for a card that just opened; nil when it fails. The output is read
    /// before waiting: a pipe holds 64 KB, and a long status waited on first never ended.
    static func cardGit(_ args: [String], in folder: String) -> String? {
        runForCard("/usr/bin/git", ["-C", folder, "--no-optional-locks"] + args)
    }

    /// A program's output for a card, nil when it is missing or fails.
    static func runForCard(_ executable: String, _ args: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
