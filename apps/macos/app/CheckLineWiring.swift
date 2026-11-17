import AppKit
import SourceControl
import Terminal

/// Changes' footer line ("make check passed · 2 min ago", the Inspector mockup): the last check
/// that ended in a terminal of the panel's folder (the task's or the project's), from what the
/// shells reported (TerminalView.command). Worked out when the tree redraws, which every
/// command's start and end makes it do.
extension WindowSession {
    func showCheckLine(now: Date = Date()) {
        guard let git else { return }
        let root = folder.root
        let ended = (projects?.projects ?? []).flatMap { $0.tabs.allTerminals }.compactMap { terminal -> TerminalCommand? in
            let place = terminal.currentDirectory ?? ""
            guard place == root || place.hasPrefix(root + "/"), let last = terminal.command.last, terminal.command.endedAt != nil,
                  CheckLine.isCheck(last) else { return nil }
            return terminal.command
        }
        guard let latest = ended.max(by: { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }),
              let line = latest.last, let at = latest.endedAt else { return git.showCheck(nil, passed: false) }
        let passed = latest.lastExit == 0
        git.showCheck(CheckLine.text(TerminalCommand.shortName(line), passed: passed, endedAt: at, now: now), passed: passed)
    }
}
