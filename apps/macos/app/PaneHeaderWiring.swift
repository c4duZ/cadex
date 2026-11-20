import AppKit
import Agents
import Darwin
import Orchestration
import Strings
import Tabs
import Terminal

/// What each pane's header says beyond its name (plan 28 phase B; the Pane and Terminals
/// mockups): for an agent's terminal, "Claude", then the task, the model and the account, and on
/// the right the session's cost and how long it has run. Worked out when an agent of this window
/// changes and once a minute while one runs, and kept: the header only reads it, so typing never
/// reads a file (the plan's rule).
extension WindowSession {
    func startPaneHeaders() {
        TabsController.paneDetail = { terminal in PaneDetails.shared.byTerminal[ObjectIdentifier(terminal)] }
        paneHeaderObserver = NotificationCenter.default.addObserver(forName: TerminalView.agentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPaneDetails() }
        }
        let clock = Timer(timeInterval: 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refreshPaneDetails() } }
        RunLoop.main.add(clock, forMode: .common)
        paneHeaderClock = clock
        refreshPaneDetails()
    }

    /// The details of this window's agent terminals again, and the headers redrawn when one changed.
    func refreshPaneDetails() {
        guard let projects else { return }
        var changed = false
        for project in projects.projects {
            for terminal in project.tabs.allTerminals {
                let next = paneDetail(of: terminal, project: project.name)
                if PaneDetails.shared.byTerminal[ObjectIdentifier(terminal)] != next {
                    PaneDetails.shared.byTerminal[ObjectIdentifier(terminal)] = next
                    changed = true
                }
            }
        }
        if changed { for project in projects.projects { project.tabs.refreshPaneHeaders() } }
        refreshLimitCards()
        refreshTitleAccount()
    }

    private func paneDetail(of terminal: TerminalView, project: String) -> PaneDetail? {
        // A race's lane says the race's numbers (RaceLanesWiring.swift).
        if let lane = laneDetail(terminal) { return lane }
        guard terminal.agentStatus != nil,
              let session = AgentsController.shared.sessions.first(where: { self.terminal(of: $0)?.terminal === terminal }) else { return nil }
        let place = TitleBarView.location(of: terminal.currentDirectory ?? "")
        let usage = PaneDetails.usage(session: session.id)
        let detail = [place.task ?? project, usage.model ?? "", session.account.name].filter { !$0.isEmpty }
        var trailing: [String] = []
        if let cost = usage.cost { trailing.append(String(format: "US$ %.2f", cost)) }
        if let started = PaneDetails.started(pid: session.pid) { trailing.append(PaneDetails.duration(since: started)) }
        return PaneDetail(title: "Claude", detail: detail.joined(separator: " · "), trailing: trailing.joined(separator: " · "),
                          accountSwitch: session.account.provider == .claude)
    }
}

/// The details by terminal, for every window (a header asks by its terminal), and how they are read.
@MainActor
final class PaneDetails {
    static let shared = PaneDetails()
    var byTerminal: [ObjectIdentifier: PaneDetail] = [:]

    /// The model and the cost the kit's status line kept for the session (usage/sessions/<id>.json).
    static func usage(session: String) -> (model: String?, cost: Double?) {
        guard !session.contains("/"),
              let data = FileManager.default.contents(atPath: SessionCost.usageFolder + "/sessions/" + session + ".json"),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return (nil, nil) }
        let model = (root["model"] as? [String: Any])?["display_name"] as? String
        let cost = ((root["cost"] as? [String: Any])?["total_cost_usd"] as? NSNumber)?.doubleValue
        return (model, cost)
    }

    /// When the process started, from the kernel (no `ps`).
    static func started(pid: Int32) -> Date? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }

    /// "now", "4 min", "1 h 5 min": the mockup's time on the right.
    static func duration(since start: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start)) / 60)
        if minutes < 1 { return T("now", "agora") }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
