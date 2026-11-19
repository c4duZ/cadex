import AppKit
import StateGlyph
import Strings
import Terminal

/// What a terminal's command gives its tab and its pane's header (plan 29's review against the
/// Terminals mockup): the command's name in place of the folder's ("npm run dev"), a working
/// ring while it runs or a green dot once it serves an address, "running 38 s", and the offer
/// "Open :5173 in preview"; a tab of several terminals is "Terminals · 3".
@MainActor
enum TabCommandLooks {
    /// The state a terminal shows: its agent's, else its command's; nil for a shell at its prompt.
    static func state(_ terminal: TerminalView?) -> GlyphState? {
        guard let terminal else { return nil }
        if let agent = TabAgentTitle.state(terminal.agentStatus, hibernated: terminal.isHibernated) { return agent }
        if terminal.agentStatus != nil { return nil }
        guard terminal.command.running != nil else { return nil }
        // A server (a port open) has no glyph: its green read as "an agent finished, go look" (UX
        // audit, 2026-11-18). Its tab says the command, and the pane offers the preview.
        return terminal.command.served != nil ? nil : .working
    }

    /// A tab's state: its only terminal's, or what matters most among several (needs, works,
    /// failed, done).
    static func state(of tab: Tab) -> GlyphState? {
        let states = tab.terminals.compactMap(state)
        for wanted in [GlyphState.needs, .working, .failed, .done, .review, .idle] where states.contains(wanted) { return wanted }
        return nil
    }

    /// "Terminals · 3" for a tab of several terminals, else nil.
    static func groupTitle(_ tab: Tab) -> String? {
        let count = tab.terminals.count
        return count > 1 ? T("Terminals · \(count)", "Terminais · \(count)") : nil
    }

    /// A shell's name while a command runs: the command's.
    static func commandTitle(_ terminal: TerminalView?) -> String? {
        guard let terminal, terminal.agentStatus == nil, let running = terminal.command.running else { return nil }
        return TerminalCommand.shortName(running)
    }

    /// The header of a terminal running a command (no agent): its name, its state, how long it
    /// has run (until it serves an address), and the offer of that address.
    static func header(_ info: inout PaneHeaderView.Info, terminal: TerminalView, now: Date = Date()) {
        guard let name = commandTitle(terminal) else { return }
        info.title = name
        info.state = state(terminal)
        if let served = terminal.command.served {
            info.offer = T("Open \(TerminalCommand.port(served)) in preview", "Abrir \(TerminalCommand.port(served)) no preview")
        } else if let started = terminal.command.startedAt {
            info.detail = T("running ", "rodando há ") + TerminalCommand.duration(since: started, now: now)
        }
    }

    /// Some pane shows "running N s": its header has to move each second.
    static func needsClock(_ tabs: [Tab]) -> Bool {
        tabs.contains { $0.terminals.contains { $0.agentStatus == nil && $0.command.running != nil && $0.command.served == nil } }
    }
}
