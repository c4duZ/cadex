import AgentTools
import Agents
import AppKit
import CommandPalette
import Explorer
import Preview
import SourceControl
import Strings
import Terminal
import Worktrees

/// The agent uses the Cadex (docs/adr/0024-agent-tools.md, plan 20 phase B):
/// a command request on the app's socket finds the terminal of the agent
/// that asked (by its kit session, else by the pids above `cadex`), checks
/// the agent's list and runs the command in that terminal's window, with
/// the terminal's folder and conversation riding along.
extension AppDelegate {
    func startAgentTools() {
        AgentToolsServer.shared.onCommand = { [weak self] request, reply in
            guard let self else { return reply(.failed("Cadex is closing")) }
            self.answerAgent(request, reply)
        }
    }

    private func answerAgent(_ request: AgentCommandRequest, _ reply: @escaping @MainActor (AgentCommandAnswer) -> Void) {
        guard settings.store.settings.agentTools.enabled else { return reply(.failed("Agent tools are off in Cadex")) }
        guard let found = agentTerminal(request) else { return reply(.failed("this session's terminal is not open in Cadex")) }
        let session = Self.conversationName(found.terminal)
        guard let id = request.id else { return reply(.ok(commandList(found.window))) }
        guard AgentCommandList.allows(id) else {
            AgentToolsActivity.shared.record(kitSession: request.kitSession, session: session, command: id, ok: false)
            return reply(.failed("\(id) is not allowed for agents"))
        }
        // The agent's folder, symlinks resolved (/tmp is /private/tmp, and git
        // answers the resolved one: found 2026-11-15), and authorized: the
        // core runs git only in authorized folders, and the agent's shell is
        // there already.
        let folder = Self.resolved(found.terminal.currentDirectory ?? NSHomeDirectory())
        WorkspaceFolder.allow(folder)
        let asked = CommandRequest(arguments: request.arguments, folder: folder, terminal: Self.key(found.terminal), session: session,
                                   kitSession: request.kitSession, dispatch: request.dispatch)
        let shown = id == "preview.agent" ? "browser " + (request.arguments["action"] ?? "") : id
        found.window.commands.run(id, request: asked) { answer in
            switch answer {
            case .ok(let text):
                AgentToolsActivity.shared.record(kitSession: request.kitSession, session: session, command: shown, ok: true)
                reply(.ok(text))
            case .failed(let text):
                AgentToolsActivity.shared.record(kitSession: request.kitSession, session: session, command: shown, ok: false)
                reply(.failed(text))
            }
        }
    }

    /// The asking agent's terminal: the one whose hooks came from this kit
    /// session, else the one whose foreground program is above `cadex`.
    private func agentTerminal(_ request: AgentCommandRequest) -> (window: WindowSession, terminal: TerminalView)? {
        let byKit = locate { $0.agentResume?.kitSession == request.kitSession }
        let found = byKit ?? locate { request.pids.contains($0.foregroundGroup) }
        return found.map { ($0.window, $0.terminal) }
    }

    static func resolved(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// `cadex commands`: what the agent may run, with its arguments.
    private func commandList(_ window: WindowSession) -> String {
        AgentCommandList.allowed.compactMap { id in
            guard let command = window.commands.command(id) else { return nil }
            return [id, command.argumentHelp, "— " + command.title].filter { !$0.isEmpty }.joined(separator: " ")
        }.joined(separator: "\n")
    }
}

extension WindowSession {
    func agentToolsActions() -> AgentToolsActions {
        AgentToolsActions(
            openFile: { [weak self] in self?.agentOpenFile($0) ?? .failed("the window is gone") },
            openDiff: { [weak self] in self?.agentOpenDiff($0) ?? .failed("the window is gone") },
            notify: { [weak self] in self?.agentNotify($0) ?? .failed("the window is gone") },
            runOwnerCommand: { [weak self] id in _ = self?.commands.run(id) },
            toggle: { [weak self] in self?.settings.store.update { $0.agentTools.enabled.toggle() } },
            showSessions: { [weak self] in self?.showAgentToolSessions() })
    }

    /// `path` from the agent's folder, inside its task (the repository of
    /// that folder, or the folder): nil and the reason otherwise.
    private func agentPath(_ given: String?, _ request: CommandRequest) -> (path: String, root: String)? {
        guard let given, !given.isEmpty else { return nil }
        let root = AppDelegate.resolved(WorktreesCore.repository(of: request.folder) ?? request.folder)
        let path = AppDelegate.resolved(((given.hasPrefix("/") ? given : (request.folder as NSString).appendingPathComponent(given)) as NSString).standardizingPath)
        guard path == root || path.hasPrefix(root + "/") else { return nil }
        return (path, root)
    }

    private func agentOpenFile(_ request: CommandRequest) -> CommandReply {
        guard let found = agentPath(request["path"], request) else { return .failed("path=<file> inside this task is needed") }
        guard FileManager.default.fileExists(atPath: found.path) else { return .failed("no such file: \(request["path"] ?? "")") }
        WorkspaceFolder.allow(found.root)
        besideAgent(request)
        opener?.open(found.path, line: request["line"].flatMap(Int.init), beside: true)
        return .ok("opened \(request["path"] ?? found.path)")
    }

    private func agentOpenDiff(_ request: CommandRequest) -> CommandReply {
        guard let root = WorktreesCore.repository(of: request.folder).map(AppDelegate.resolved) else { return .failed("this terminal is not in a git repository") }
        guard request["path"] != nil else {
            folder.open(root)
            workspace?.showInspector("changes")
            return .ok("the task's changes are in Cadex's Git page")
        }
        guard let found = agentPath(request["path"], request) else { return .failed("the file must be inside this task") }
        let relative = String(found.path.dropFirst(root.count + 1))
        besideAgent(request)
        opener?.openDiff(.init(repo: root, path: relative, orig: relative, staged: false), beside: true)
        return .ok("opened the diff of \(relative)")
    }

    private func agentNotify(_ request: CommandRequest) -> CommandReply {
        let text = String((request["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !text.isEmpty else { return .failed("text=<one sentence> is needed") }
        let project = ((WorktreesCore.repository(of: request.folder) ?? request.folder) as NSString).lastPathComponent
        AgentAttention.shared.note(.note, text: text, project: project, session: request.session, key: request.terminal)
        let looked = tabs?.allTerminals.first { AppDelegate.key($0) == request.terminal }?.isLookedAt ?? false
        if AgentNotifier.canPost, !looked {
            app.postTerminalNotification(title: request.session.isEmpty ? "Agent" : request.session, subtitle: project, body: text, key: request.terminal)
        }
        return .ok("the owner was notified")
    }

    /// preview.open with url=: a page beside the agent's terminal.
    func agentOpenPreview(_ request: CommandRequest) -> CommandReply {
        guard let given = request["url"]?.trimmingCharacters(in: .whitespaces), !given.isEmpty else { return .failed("url=<address> is needed") }
        let local = ["localhost", "127.", "0.0.0.0", "[::1]"].contains { given.hasPrefix($0) }
        let url = given.contains("://") ? given : (local ? "http://" : "https://") + given
        guard let scheme = URL(string: url)?.scheme, ["http", "https"].contains(scheme) else { return .failed("only http and https pages open in the preview") }
        besideAgent(request)
        openPreview(url, beside: true)
        return .ok("opened \(url) in the preview")
    }

    /// The preview the asking agent drives (its first goto opened it).
    func agentPreview(_ request: CommandRequest) -> PreviewDocument? {
        AgentPreviewTabs.tabs[request.terminal]?.document
    }

    /// The agent's first goto: a blank preview beside its terminal, kept as
    /// its tab (docs/spec/preview.md, Agente no preview).
    func openAgentPreview(_ request: CommandRequest) -> PreviewDocument? {
        besideAgent(request)
        openPreview("", beside: true)
        guard let doc = tabs?.activeDocument as? PreviewDocument else { return nil }
        doc.agentTerminal = request.terminal
        AgentPreviewTabs.tabs[request.terminal] = AgentPreviewTabs.Held(document: doc)
        return doc
    }

    /// What the agent opens goes beside its terminal (docs/spec/agent-tools.md):
    /// that terminal's space and tab come forward in this window, its pane
    /// takes the focus; the window does not jump in front of the owner's work.
    private func besideAgent(_ request: CommandRequest) {
        guard let found = app.locate({ AppDelegate.key($0) == request.terminal }), found.window === self else { return }
        spaces?.select(found.space)
        tabs?.focus(found.terminal)
    }

    /// agent-tools.show-sessions: the sessions that used the Cadex and their last request.
    private func showAgentToolSessions() {
        palette?.open(AgentChoiceSource(placeholder: T("Sessions using Cadex", "Sessões usando o Cadex"),
                                        empty: T("No agent has used Cadex since it opened", "Nenhum agente usou o Cadex desde que ele abriu"), items: {
            AgentToolsActivity.shared.entries.map { entry in
                PaletteItem(id: entry.kitSession, title: entry.session.isEmpty ? entry.kitSession : entry.session,
                            detail: (entry.ok ? "" : "✕ ") + entry.command + " · " + entry.at.formatted(date: .omitted, time: .shortened), icon: .terminalWindow)
            }
        }, choose: { [weak self] kit in
            guard let found = self?.app.locate({ $0.agentResume?.kitSession == kit }) else { return NSSound.beep() }
            self?.app.goToAgent(key: AppDelegate.key(found.terminal), pid: 0)
        }))
    }
}

/// Each agent terminal's preview tab, by the terminal's key; a closed tab
/// lets go (weak).
@MainActor
enum AgentPreviewTabs {
    struct Held { weak var document: PreviewDocument? }
    static var tabs: [String: Held] = [:]
}
