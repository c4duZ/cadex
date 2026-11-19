import AppKit
import Strings

/// The agent running in this terminal, as it reports itself by OSC 7501
/// (docs/spec/tabs.md, plan 19): its state for the tab's title, and whether
/// it finished while nobody looked, which stays until the terminal gets the
/// focus.
extension TerminalView {
    /// The last report, while a program runs in the foreground: an agent
    /// that quit without saying so (back at the shell) reports nothing. One
    /// that was working when its process went away died mid-turn: it says
    /// "failed", not nothing, until the shell runs something else (a crash
    /// just lost its glyph and read as "nothing to do": UX audit, 2026-11-18).
    public var agentStatus: TerminalAgentStatus? {
        guard let agent = signals.agent else { return nil }
        if hasForegroundProcess { return agent }
        guard agent.state == .working, !isHibernated else { return nil }
        return TerminalAgentStatus(state: .failed, kind: agent.kind, app: agent.app,
                                   message: T("Exited while working", "Saiu no meio do trabalho"))
    }

    /// It finished (done) while this terminal did not have the focus.
    public var agentFinishedUnseen: Bool { signals.agentUnseen && agentStatus?.state == .done }

    /// The agent reported or was seen: tabs refresh their title.
    public var onAgentStatus: (() -> Void)? {
        get { signals.onAgent }
        set { signals.onAgent = newValue }
    }

    /// Posted when any terminal's agent reports or is seen: the app gathers
    /// every terminal's state for the bell, the Dock and the board.
    public static let agentDidChange = Notification.Name("CadexTerminalAgentDidChange")

    /// "Mark as Unread": a finished agent counts as not seen again.
    public func markAgentUnseen() {
        guard signals.agent?.state == .done else { return }
        signals.agentUnseen = true
        signals.onAgent?()
        NotificationCenter.default.post(name: Self.agentDidChange, object: self)
    }

    func agentReported() {
        let before = signals.agent?.state
        signals.agent = session?.agentStatus()
        switch signals.agent?.state {
        case .idle, .done: if signals.quietSince == nil || (before != .idle && before != .done) { signals.quietSince = Date() }
        default: signals.quietSince = nil
        }
        let looked = window?.isKeyWindow == true && window?.firstResponder === self
        if signals.agent?.state == .done, before != .done, !looked { signals.agentUnseen = true }
        if signals.agent?.state != .done { signals.agentUnseen = false }
        // The agent waits for the owner: an amber mark where it asked (the Pane mockup).
        if signals.agent?.state == .blocked, before != .blocked { scrollbar.mark(cursorRow: lastCursorRow, needs: true) }
        signals.onAgent?()
        NotificationCenter.default.post(name: Self.agentDidChange, object: self)
    }

    func agentSeen() {
        guard signals.agentUnseen else { return }
        signals.agentUnseen = false
        signals.onAgent?()
        NotificationCenter.default.post(name: Self.agentDidChange, object: self)
    }
}

/// What brings a terminal's agent back after it quit or was hibernated
/// (docs/spec/agents.md, Hibernação): the conversation, its folder, the
/// account's folder (nil: the default one) and the session kit's name for
/// it, whose token the relaunch keeps. The app fills it from the hooks.
public struct TerminalAgentResume: Equatable, Sendable {
    public let sessionID: String
    public let folder: String
    public let configDir: String?
    public let kitSession: String?
    public init(sessionID: String, folder: String, configDir: String?, kitSession: String?) {
        self.sessionID = sessionID
        self.folder = folder
        self.configDir = configDir
        self.kitSession = kitSession
    }
}

/// Hibernation (plan 19 phase F): the state the app keeps on the terminal.
extension TerminalView {
    /// Posted when the terminal takes the keyboard focus (its tab opened,
    /// a click): a hibernated agent comes back then.
    public static let didTakeFocus = Notification.Name("CadexTerminalDidTakeFocus")

    public var agentResume: TerminalAgentResume? {
        get { signals.resume }
        set { signals.resume = newValue }
    }

    /// The app ended this terminal's agent to save memory; it comes back
    /// when the terminal is opened again.
    public var isHibernated: Bool {
        get { signals.hibernated }
        set {
            signals.hibernated = newValue
            signals.onAgent?()
            NotificationCenter.default.post(name: Self.agentDidChange, object: self)
        }
    }

    /// Since when the agent has been done or idle (nil while it works or waits).
    public var agentQuietSince: Date? { signals.quietSince }
}
