import AgentTools
import AppKit
import SessionKit
import SourceControl
import Strings
import Worktrees

/// What each agent edited in its turn (plan 26 phase C2, Changes' "Last turn"): the files of each
/// session's edits (PostToolUse) since its last Stop. An edit after a Stop starts a new turn. Kept
/// in memory only: a reopened app has seen no turn yet.
@MainActor
enum AgentTurns {
    private struct Turn {
        var files: Set<String> = []
        var closed = false
        var at = Date.distantPast
    }
    private static var turns: [String: Turn] = [:]

    static func record(_ event: AgentHookEvent) {
        // Without a session its Stop could never close the turn: such edits are left out.
        guard let edit = event.edit, let session = event.sessionID ?? event.kitSession else { return }
        var turn = turns[session] ?? Turn()
        if turn.closed { turn = Turn() }
        turn.files.insert(edit.file)
        turn.at = Date()
        turns[session] = turn
    }

    static func stop(_ event: AgentHookEvent) {
        guard let session = event.sessionID ?? event.kitSession else { return }
        turns[session]?.closed = true
    }

    /// The latest turn that edited inside `repo`: its files there; nil when none did.
    static func lastFiles(in repo: String) -> Set<String>? {
        let inside = repo + "/"
        return turns.values.filter { $0.files.contains { $0.hasPrefix(inside) } }.max { $0.at < $1.at }?.files
    }
}

extension WindowSession {
    /// Changes' sources in this window: where the task started, the last turn, and Open PR.
    func wireChanges(_ git: SourceControlController) {
        git.taskStart = { repo in WorktreesController.shared.store.task(repo)?.base }
        git.lastTurnFiles = { repo in AgentTurns.lastFiles(in: repo) }
        git.onOpenPullRequest = { [weak self] repo in
            // The GitHub CLI asks what it needs in the tab (push, title); without it, the tab says
            // how to get it.
            let install = T("Open a pull request needs the GitHub CLI: brew install gh", "Abrir um pull request precisa do GitHub CLI: brew install gh")
            // if/else, not && ||: a failed `gh pr create` (nothing pushed, cancelled) must not say
            // to install it (review of 2026-11-17).
            self?.typeInNewTab("if command -v gh >/dev/null; then gh pr create --web; else echo " + SessionKit.quote(install) + "; fi", cwd: repo)
        }
    }
}
