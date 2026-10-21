import Agents
import AppKit

/// `make perf` only (tools/perf/run.py): what a scenario asks the test app
/// to do on its own, at set times, so it is measured with no click. Each
/// hook reads one variable and does nothing without it.
extension WindowSession {
    func startPerfHooks() {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["CADEX_PERF_SUBAGENT_LOG"] { openPerfTranscript(path) }
        if let count = environment["CADEX_PERF_TABS"].flatMap(Int.init) { openPerfTabs(count) }
    }

    /// That log's conversation opened at 12 s and 36 s and closed 12 s
    /// after each: the first opening's one-time cost apart from each
    /// opening's, and what stays once closed.
    private func openPerfTranscript(_ path: String) {
        for start in [12.0, 36.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + start) { [weak self] in
                self?.tabs?.open(AgentTranscriptDocument(path: path, title: "perf", detail: "", colors: Self.agentColors()), beside: false)
            }
            // Its tab has the focus: closing the focused pane closes it.
            DispatchQueue.main.asyncAfter(deadline: .now() + start + 12) { [weak self] in
                if self?.tabs?.activeDocument is AgentTranscriptDocument { self?.tabs?.closeFocusedPane() }
            }
        }
    }

    /// `count` more terminal tabs, one a second from 12 s, then back to the
    /// first: what each terminal tab weighs, shown and hidden.
    private func openPerfTabs(_ count: Int) {
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12 + Double(index)) { [weak self] in self?.tabs?.newTab() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14 + Double(count)) { [weak self] in self?.tabs?.select(position: 1) }
    }
}
