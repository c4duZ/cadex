import AppKit
import Orchestration
import Strings
import Tabs
import Terminal

/// A race's tab as the Race mockup draws it (plan 30 B, done with plan 29's review): the local
/// contenders' terminals side by side, "Contenders · N", the prompt and cap over them with
/// Compare…, each lane's header with "#1 Claude Opus · bkdg", its time, its state, cost and diff
/// and the cap's bar, and its foot with Review and Pick winner.
extension WindowSession {
    func dressLanes(_ race: Race, _ lanes: [TerminalView]) {
        guard let first = lanes.first, let tabs else { return }
        tabs.setTitle(T("Contenders · \(lanes.count)", "Concorrentes · \(lanes.count)"), ofTabWith: first)
        tabs.setBanner(RaceLaneViews.banner(prompt: race.prompt, base: race.base, budget: race.caps.budgetUsd, minutes: race.caps.maxMinutes) { [weak self] in
            _ = self?.commands.run("git.review-compare-worktrees")
        }, ofTabWith: first)
        let contenders = (try? OrchestrationController.shared.races()?.contenders(of: race.id)) ?? []
        for (lane, contender) in zip(lanes, contenders.filter { $0.agent.machine.isEmpty }.sorted { $0.index < $1.index }) {
            lane.footBar = RaceLaneViews.foot(review: { [weak self] in self?.openReview(repo: contender.worktree) },
                                              pickWinner: { [weak self] in self?.pickWinner(race, contender) })
        }
        refreshPaneDetails()
        armRaceWatch()
    }

    /// The race and contender a terminal runs, when it is a lane.
    func contender(of terminal: TerminalView) -> (Race, Contender)? {
        guard let book = OrchestrationController.shared.races(), let place = terminal.currentDirectory else { return nil }
        for race in (try? book.races()) ?? [] where race.winner == nil {
            for contender in (try? book.contenders(of: race.id)) ?? [] where contender.agent.machine.isEmpty
                && (place == contender.worktree || place.hasPrefix(contender.worktree + "/")) {
                return (race, contender)
            }
        }
        return nil
    }

    /// A lane's header: "#1 Claude Opus", the account, the time since the race began; under it
    /// the state, the cost and the diff, and the cap spent (money or minutes, the further one).
    func laneDetail(_ terminal: TerminalView) -> PaneDetail? {
        guard let (race, contender) = contender(of: terminal) else { return nil }
        let live = live(contender)
        let agent = contender.agent.isCodex ? "Codex" : "Claude"
        let model = contender.agent.model.isEmpty ? "" : " " + contender.agent.model.prefix(1).uppercased() + contender.agent.model.dropFirst()
        let account = contender.agent.account.map { ($0 as NSString).lastPathComponent } ?? T("default", "padrão")
        let seconds = max(0, Int(Date().timeIntervalSince(race.createdAt)))
        let time = seconds < 3600 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        var parts = [RaceColumns.stateText(live, stored: contender)]
        parts.append(live?.costUsd.map { String(format: "US$ %.2f", $0) } ?? "—")
        if let diff = live?.diff {
            parts.append("+\(diff.added) −\(diff.removed) " + T("in \(diff.files) files", "em \(diff.files) arquivos"))
        }
        let spent = max((live?.costUsd ?? 0) / max(race.caps.budgetUsd, 0.01), Double(seconds) / 60 / Double(max(race.caps.maxMinutes, 1)))
        return PaneDetail(title: "#\(contender.index) \(agent)\(model)", detail: account, trailing: time,
                          lane: PaneLane(status: parts.joined(separator: " · "), cap: spent))
    }

    /// The race a folder is a contender's worktree of (its name), for the title bar.
    func raceName(of folder: String) -> String? {
        guard OrchestrationController.shared.isEnabled, let book = OrchestrationController.shared.races() else { return nil }
        for race in (try? book.races()) ?? [] where race.winner == nil {
            if ((try? book.contenders(of: race.id)) ?? []).contains(where: { folder == $0.worktree || folder.hasPrefix($0.worktree + "/") }) { return race.name }
        }
        return nil
    }
}
