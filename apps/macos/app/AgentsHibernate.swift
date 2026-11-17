import AgentTools
import Agents
import AppKit
import Terminal

/// Hibernation for the whole app (docs/spec/agents.md, Hibernação; plan 19
/// phase F): the hooks tell each terminal what brings its agent back; an
/// agent done or idle and not looked at for agents.hibernateAfterMinutes
/// ends (SIGTERM) and its tab shows it; opening that terminal again types
/// `claude --resume <id>` by the kit; an agent that quit on its own gets
/// "Restart". Only sessions Cadex opened (they have hooks) hibernate.
extension AppDelegate {
    func startHibernation() {
        let center = NotificationCenter.default
        center.addObserver(forName: TerminalView.agentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleHibernation() }
        }
        center.addObserver(forName: TerminalView.didTakeFocus, object: nil, queue: .main) { [weak self] note in
            // The view is read on the main queue it was posted on.
            nonisolated(unsafe) let object = note.object
            MainActor.assumeIsolated { if let terminal = object as? TerminalView { self?.wake(terminal) } }
        }
    }

    /// A hook from a session Cadex opened: what brings it back, kept on its
    /// terminal; its end with nothing left running offers "Restart".
    func noteAgentEvent(_ event: AgentHookEvent) {
        guard let terminal = terminal(pid: event.pid)?.terminal else { return }
        // A hook may come after the report that made the agent quiet.
        defer { scheduleHibernation() }
        let old = terminal.agentResume
        if let id = event.sessionID, !id.isEmpty {
            let configDir = event.transcriptPath.map { AgentHibernation.configDir(transcript: $0) } ?? old?.configDir
            terminal.agentResume = TerminalAgentResume(sessionID: id, folder: event.cwd ?? old?.folder ?? terminal.currentDirectory ?? NSHomeDirectory(),
                                                       configDir: configDir, kitSession: event.kitSession ?? old?.kitSession)
        }
        if terminal.onRestartAgent == nil {
            terminal.onRestartAgent = { [weak self, weak terminal] in
                guard let terminal else { return }
                terminal.window?.makeFirstResponder(terminal)
                // The command acts on the focused terminal: this one now.
                _ = self?.sessions.first { $0.window === terminal.window }?.commands.run("agents.restart")
            }
        }
        guard event.event == "SessionEnd", !terminal.isHibernated else { return }
        // Still running after it (/clear starts a new one): nothing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak terminal] in
            MainActor.assumeIsolated {
                guard let terminal, !terminal.isHibernated, !terminal.hasForegroundProcess, terminal.agentResume != nil else { return }
                terminal.offerRestart(true)
            }
        }
    }

    private var hibernateMinutes: Int { settings.store.settings.agents.hibernateAfterMinutes }

    private var everyTerminal: [TerminalView] {
        sessions.flatMap { window in (window.projects?.projects ?? []).flatMap { $0.tabs.allTerminals } }
    }

    /// An agent Cadex opened, running, not hibernated.
    private func canHibernate(_ terminal: TerminalView) -> Bool {
        terminal.agentResume != nil && !terminal.isHibernated && terminal.agentStatus != nil
    }

    /// One timer, for the earliest agent to come due; none while no agent
    /// is quiet. One looked at when due is looked at again a minute later.
    func scheduleHibernation() {
        HibernationClock.timer?.invalidate()
        HibernationClock.timer = nil
        let minutes = hibernateMinutes
        let dues = everyTerminal.filter(canHibernate).compactMap { AgentHibernation.dueAt(quietSince: $0.agentQuietSince, minutes: minutes) }
        guard let first = dues.min() else { return }
        let at = max(first, Date().addingTimeInterval(first <= Date() ? 60 : 0))
        HibernationClock.timer = Timer.scheduledTimer(withTimeInterval: max(at.timeIntervalSinceNow, 1), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hibernateDue() }
        }
    }

    private func hibernateDue() {
        let minutes = hibernateMinutes
        for terminal in everyTerminal where canHibernate(terminal)
            && AgentHibernation.isDue(quietSince: terminal.agentQuietSince, lookedAt: terminal.isLookedAt, minutes: minutes) {
            hibernate(terminal)
        }
        scheduleHibernation()
    }

    /// Ends the agent (it keeps its conversation) and marks the terminal.
    @discardableResult
    func hibernate(_ terminal: TerminalView) -> Bool {
        let pid = terminal.foregroundGroup
        guard pid > 0, terminal.agentResume != nil else { return false }
        terminal.isHibernated = true
        kill(pid, SIGTERM)
        // Its task's environment sleeps with it (plan 23, ADR 0032).
        sessions.first?.followEnvironment(of: terminal.currentDirectory, to: .suspend)
        return true
    }

    /// The terminal was opened: a hibernated agent comes back.
    func wake(_ terminal: TerminalView) {
        guard terminal.isHibernated, !terminal.hasForegroundProcess else { return }
        relaunch(terminal)
    }

    /// Types the resume in the terminal, at the shell's prompt.
    @discardableResult
    func relaunch(_ terminal: TerminalView) -> Bool {
        guard let resume = terminal.agentResume, !terminal.hasForegroundProcess else { return false }
        terminal.offerRestart(false)
        terminal.isHibernated = false
        sessions.first?.followEnvironment(of: terminal.currentDirectory, to: .resume)
        let command = AgentHibernation.resumeCommand(sessionID: resume.sessionID, folder: resume.folder, configDir: resume.configDir,
                                                     kitSession: resume.kitSession, skipPermissions: settings.store.settings.agents.launchSkipPermissions)
        terminal.session?.write(command + "\n")
        return true
    }
}

/// The hibernation's one timer (an extension cannot keep it on the app).
@MainActor
enum HibernationClock {
    static var timer: Timer?
}

extension WindowSession {
    /// agents.hibernate: the focused terminal's agent, now, unless it works
    /// or waits for you (that would lose the turn).
    func hibernateFocusedAgent() {
        guard let terminal = tabs?.activeTerminal, let status = terminal.agentStatus,
              status.state != .working, status.state != .blocked, app.hibernate(terminal) else { return NSSound.beep() }
    }

    /// agents.restart: the focused terminal's agent that quit or hibernated.
    func restartFocusedAgent() {
        guard let terminal = tabs?.activeTerminal, app.relaunch(terminal) else { return NSSound.beep() }
    }
}
