import AppKit
import Terminal

/// The terminals where an agent may run, for what other features hand to it
/// (the preview's picked element, docs/spec/preview.md). Apart from
/// TabsController.swift, which is at its size limit.
extension TabsController {
    /// Best first: a known agent by its title, then any terminal running a
    /// program; the active tab first, then the tabs used most recently, the
    /// focused pane first in each. A shell at its prompt is never one.
    public var agentTerminals: [TerminalView] {
        let ids = list.recent + list.order.filter { !list.recent.contains($0) }
        let terminals = ids.compactMap { tabs[$0] }.flatMap { tab in
            let focused = tab.focused.terminal
            return (focused.map { [$0] } ?? []) + tab.terminals.filter { $0 !== focused }
        }
        let candidates = terminals.map { AgentCandidate(title: $0.programTitle, running: $0.hasForegroundProcess) }
        return AgentCandidate.order(candidates).map { terminals[$0] }
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

    /// Indices of the candidates to try: agents, then other running programs.
    static func order(_ candidates: [AgentCandidate]) -> [Int] {
        let agents = candidates.indices.filter { candidates[$0].isAgent }
        let others = candidates.indices.filter { candidates[$0].running && !candidates[$0].isAgent }
        return agents + others
    }
}
