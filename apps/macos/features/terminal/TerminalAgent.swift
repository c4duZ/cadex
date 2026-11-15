import AppKit

/// The agent running in this terminal, as it reports itself by OSC 7501
/// (docs/spec/tabs.md, plan 19): its state for the tab's title, and whether
/// it finished while nobody looked, which stays until the terminal gets the
/// focus.
extension TerminalView {
    /// The last report, while a program runs in the foreground: an agent
    /// that quit without saying so (back at the shell) reports nothing.
    public var agentStatus: TerminalAgentStatus? {
        guard let agent = signals.agent, hasForegroundProcess else { return nil }
        return agent
    }

    /// It finished (done) while this terminal did not have the focus.
    public var agentFinishedUnseen: Bool { signals.agentUnseen && agentStatus?.state == .done }

    /// The agent reported or was seen: tabs refresh their title.
    public var onAgentStatus: (() -> Void)? {
        get { signals.onAgent }
        set { signals.onAgent = newValue }
    }

    func agentReported() {
        let before = signals.agent?.state
        signals.agent = session?.agentStatus()
        let looked = window?.isKeyWindow == true && window?.firstResponder === self
        if signals.agent?.state == .done, before != .done, !looked { signals.agentUnseen = true }
        if signals.agent?.state != .done { signals.agentUnseen = false }
        signals.onAgent?()
    }

    func agentSeen() {
        guard signals.agentUnseen else { return }
        signals.agentUnseen = false
        signals.onAgent?()
    }
}
