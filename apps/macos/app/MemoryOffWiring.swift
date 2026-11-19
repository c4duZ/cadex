import Agents
import AppKit
import CommandPalette
import Icons
import Memory
import Menus
import Projects
import Strings
import Terminal

/// The memory turned off (plan 35 I; docs/spec/memory.md, "Desligar"): in a project, kept in
/// Cadex's projects file by the main window's projects and written for the engine and the kit as
/// the memory's off-projects.json (`MemoryOff`); in a conversation, a new session without the
/// memory's part of the kit, or a pause mark for the focused terminal's Claude session, shown on
/// its tab. Every action is a command (ADR 0005).
extension WindowSession {
    /// The projects that keep the flag: the main window's (only it saves), else this window's.
    var memoryOffProjects: ProjectsController? {
        app.sessions.first { $0.isMain }?.projects ?? projects
    }

    func memoryOffCommands() -> [Command] {
        [Command(id: "memory.toggle-project", title: T("Turn Memory On or Off in This Project", "Ligar ou desligar a memória neste projeto"),
                 keywords: ["memory", "off", "on", "disable", "project", "memória", "desligar", "ligar", "projeto"], category: .terminal,
                 action: .run { [weak self] in self?.toggleProjectMemory() }),
         Command(id: "memory.new-session-without", title: T("New Session without Memory", "Nova sessão sem memória"),
                 keywords: ["memory", "off", "private", "claude", "agent", "session", "memória", "sem", "privada", "sessão", "agente"],
                 category: .terminal, action: .run { [weak self] in self?.newSessionWithoutMemory() }),
         Command(id: "memory.pause-session", title: T("Pause Memory in This Session", "Pausar a memória nesta sessão"),
                 keywords: ["memory", "pause", "stop", "recording", "session", "memória", "pausar", "parar", "gravar", "sessão"],
                 category: .terminal, action: .run { [weak self] in self?.setSessionMemoryPaused(true) }),
         Command(id: "memory.resume-session", title: T("Resume Memory in This Session", "Retomar a memória nesta sessão"),
                 keywords: ["memory", "resume", "recording", "session", "memória", "retomar", "gravar", "sessão"],
                 category: .terminal, action: .run { [weak self] in self?.setSessionMemoryPaused(false) })]
    }

    /// The main window's projects tell the memory which roots are off, now and at each change.
    func connectMemoryOff(_ projects: ProjectsController) {
        projects.onMemoryOffChange = { roots in
            MemoryOff.write(roots: roots)
            MemoryMarkerWiring.memoryOffChanged(roots)
        }
        MemoryOff.write(roots: projects.memoryOff)
        MemoryMarkerWiring.memoryOffChanged(projects.memoryOff)
        MemoryOff.prunePaused()
    }

    private func toggleProjectMemory() {
        guard let folder = takeProjectTarget(), let store = memoryOffProjects else { return NSSound.beep() }
        store.setMemoryOff(!store.isMemoryOff(folder), for: folder)
        // An open Settings page shows the change; after the switch that may have run this is done.
        DispatchQueue.main.async { [weak self] in
            (self?.tabs?.document(identity: ProjectSettingsDocument.identity(for: folder)) as? ProjectSettingsDocument)?.reload()
        }
    }

    /// The memory's switch for a project's Settings (MemoryProjectForm).
    func projectMemoryForm(_ folder: String) -> NSView {
        MemoryProjectForm(folder: folder, memoryOn: !(memoryOffProjects?.isMemoryOff(folder) ?? false)) { [weak self] on in
            guard let self, self.memoryOffProjects?.isMemoryOff(folder) == on else { return }
            self.projectTarget = folder
            _ = self.commands.run("memory.toggle-project")
        }
    }

    /// Claude in the account new sessions use, in a new tab, with the kit but not the memory's part:
    /// no hooks, no tools, no briefing (the same as a project with the memory off).
    private func newSessionWithoutMemory() {
        guard let tabs, let dir = shownAccountDir(),
              let account = AgentsController.shared.everyAccount().first(where: { $0.dir == dir }) else { return NSSound.beep() }
        let cwd = tabs.activeTerminal?.currentDirectory ?? projects?.activeFolder
        tabs.newTab(cwd: cwd)
        let command = AgentLaunch.command(for: account, skipPermissions: settings.store.settings.agents.launchSkipPermissions, cwd: cwd,
                                          leaving: [MemoryKit.partID])
        tabs.activeTerminal?.typeWhenReady(command + "\n")
    }

    /// The focused terminal's Claude session, by the id its hooks gave.
    private var focusedSessionID: String? { tabs?.activeTerminal?.agentResume?.sessionID }

    private func setSessionMemoryPaused(_ paused: Bool) {
        guard let id = focusedSessionID, MemoryOff.isPaused(sessionID: id) != paused,
              MemoryOff.setPaused(paused, sessionID: id) else { return NSSound.beep() }
        tabs?.refreshTabBar()
    }

    /// The tab's right click: Pause or Resume, when its terminal runs a Claude session.
    func memoryTabPins() -> [PalettePin] {
        guard let id = focusedSessionID else { return [] }
        return MemoryOff.isPaused(sessionID: id)
            ? [PalettePin(id: "memory.resume-session", title: T("Resume Memory", "Retomar a memória"), icon: .play)]
            : [PalettePin(id: "memory.pause-session", title: T("Pause Memory", "Pausar a memória"), icon: .pause)]
    }

    /// The tab's sign: the memory paused in its session, else another screen
    /// on it (plan 39 A: the phone by `cadex attach`).
    static func memoryMark(_ terminal: TerminalView) -> Icon? {
        if let id = terminal.agentResume?.sessionID, MemoryOff.isPaused(sessionID: id) { return .pause }
        return terminal.guests > 0 ? .deviceMobile : nil
    }
}
