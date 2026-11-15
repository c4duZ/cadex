import Terminal

/// A tab with an agent (docs/spec/tabs.md, plan 19): a sign for its state
/// before the title and its conversation's name in place of the folder.
/// The state comes from the agent's own OSC 7501 reports (Terminal).
enum TabAgentTitle {
    /// Working ◐, waiting for you ●, finished ✓ (✓• while you have not
    /// looked yet), failed ✕; nothing when idle (docs/spec/tabs.md).
    static func sign(_ status: TerminalAgentStatus?, finishedUnseen: Bool) -> String {
        switch status?.state {
        case .working: "◐ "
        case .blocked: "● "
        case .done: finishedUnseen ? "✓• " : "✓ "
        case .failed: "✕ "
        default: ""
        }
    }

    /// The conversation's name from the title the agent set (OSC 0/2):
    /// Claude Code drops its own spinner from the title once the terminal
    /// answers OSC 7501 (test of 2026-11-14), and any glyph left before the
    /// first letter or digit goes too ("✳ Fix login" → "Fix login").
    static func name(programTitle: String) -> String {
        let trimmed = programTitle.drop { !$0.isLetter && !$0.isNumber }
        return String(trimmed).trimmingCharacters(in: .whitespaces)
    }

    /// The tab's tip: what the agent does now, over the folder.
    static func tip(_ status: TerminalAgentStatus?, folder: String?) -> String? {
        let lines = [status?.message, folder].compactMap { $0 }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
