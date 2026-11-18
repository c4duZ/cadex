import StateGlyph
import Strings
import Terminal

/// A tab with an agent (docs/spec/tabs.md, plan 19): the app's state glyph before the title
/// (shared/state-glyph, plan 25; the ◐ ● ✓ ✕ ☾ of the title went with it) and its
/// conversation's name in place of the folder. The state comes from the agent's own OSC 7501
/// reports (Terminal).
enum TabAgentTitle {
    /// Working, needs you (waiting for a permission or an answer), done, failed; a hibernated
    /// agent (plan 19 phase F: ended to save memory, back when the tab opens) is idle; nothing
    /// when there is no agent.
    static func state(_ status: TerminalAgentStatus?, hibernated: Bool = false) -> GlyphState? {
        if hibernated { return .idle }
        return switch status?.state {
        case .working: .working
        case .blocked: .needs
        case .done: .done
        case .failed: .failed
        default: nil
        }
    }

    /// The tab's tip: what the agent does now, over the folder.
    static func tip(_ status: TerminalAgentStatus?, folder: String?, hibernated: Bool = false) -> String? {
        let state = hibernated ? T("Hibernating: comes back when you open this tab", "Hibernando: volta quando você abre esta aba") : status?.message
        let lines = [state, folder].compactMap { $0 }.filter { !$0.isEmpty }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}
