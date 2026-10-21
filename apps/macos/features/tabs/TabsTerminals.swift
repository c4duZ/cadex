import AppKit
import Terminal

/// The terminals where an agent may run, for what other features hand to it
/// (the preview's picked element, docs/spec/preview.md). Apart from
/// TabsController.swift, which is at its size limit.
extension TabsController {
    /// Best first: a known agent by its title, then any terminal running a
    /// program; in each, the terminal clicked last first, in any tab: click
    /// a terminal, then the preview beside it, and picks go to that terminal
    /// (owner, 2026-10-21). Never clicked ones come after, the active tab's
    /// first. A shell at its prompt is never one.
    public var agentTerminals: [TerminalView] {
        let ids = list.recent + list.order.filter { !list.recent.contains($0) }
        let inTabs = ids.compactMap { tabs[$0] }.flatMap { tab in
            let focused = tab.focused.terminal
            return (focused.map { [$0] } ?? []) + tab.terminals.filter { $0 !== focused }
        }
        let terminals = AgentCandidate.recentFirst(inTabs.map(ObjectIdentifier.init), recent: recentTerminals)
            .compactMap { id in inTabs.first { ObjectIdentifier($0) == id } }
        let candidates = terminals.map { AgentCandidate(title: $0.programTitle, running: $0.hasForegroundProcess) }
        return AgentCandidate.order(candidates).map { terminals[$0] }
    }

    /// A terminal got the focus: it goes to the front of the recent ones.
    func noteFocus(_ terminal: TerminalView) {
        let id = ObjectIdentifier(terminal)
        recentTerminals.removeAll { $0 == id }
        recentTerminals.insert(id, at: 0)
        // Closed terminals leave the list as it grows past what is open.
        if recentTerminals.count > 64 { recentTerminals.removeLast(recentTerminals.count - 64) }
    }

    /// Selects the terminal's tab and gives it the keyboard.
    public func focus(_ terminal: TerminalView) {
        for id in list.order {
            guard let tab = tabs[id], let pane = tab.pane(of: terminal) else { continue }
            if list.active != id { select(id) }
            tab.focus(pane)
            refreshBar()
            return
        }
    }
}

/// A terminal as the agent order sees it. Pure, so the order is testable.
struct AgentCandidate {
    let title: String
    let running: Bool

    /// Titles agents give their terminal (Claude Code's starts with ✳).
    static let agentNames = ["claude", "✳", "codex", "opencode", "aider", "gemini", "cursor-agent", "amp", "goose", "crush"]

    var isAgent: Bool {
        let lower = title.lowercased()
        return running && Self.agentNames.contains { lower.contains($0) }
    }

    /// The items focused recently first, newest first; the others after,
    /// in the order given.
    static func recentFirst<T: Equatable>(_ items: [T], recent: [T]) -> [T] {
        recent.filter(items.contains) + items.filter { !recent.contains($0) }
    }

    /// Indices of the candidates to try: agents, then other running programs.
    static func order(_ candidates: [AgentCandidate]) -> [Int] {
        let agents = candidates.indices.filter { candidates[$0].isAgent }
        let others = candidates.indices.filter { candidates[$0].running && !candidates[$0].isAgent }
        return agents + others
    }
}
