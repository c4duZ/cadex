import AppKit
import Strings

/// The Changes tab's list and footer (plan 26 phase C2; docs/spec/inspector.md, Changes): the
/// files of the scope with their counts, read on the repository's queue after each status, and
/// Commit… and Open PR.
extension SourceControlController {
    /// Reads the scope's files: against HEAD (uncommitted, and the last turn among them) or against
    /// where the task started. Only while the tab shows (each status would cost three more git
    /// runs: review of 2026-11-17); shown again, it reads. One read at a time; asked again
    /// meanwhile, it reads once more.
    func loadChanges() {
        guard let repo else { return }
        guard panel.shows else { return changesStale = true }
        guard !changesRunning else { return changesPending = true }
        changesStale = false
        let scope = scope
        let start = scope == .task ? taskStart?(repo.root) : nil
        let turn = scope == .lastTurn ? lastTurnFiles?(repo.root) : nil
        // Both sides resolved: a project opened through a link (/tmp and /private/tmp) still matches.
        let root = Self.resolved(repo.root) + "/"
        let keep: Set<String>? = scope == .lastTurn
            ? Set((turn ?? []).map(Self.resolved).filter { $0.hasPrefix(root) }.map { String($0.dropFirst(root.count)) }) : nil
        let entries = status.entries
        changesRunning = true
        repo.queue.async { [weak self] in
            let base = scope == .task ? repo.reviewBase(start: start) : "HEAD"
            let read = base.flatMap { repo.reviewFiles(base: $0, to: nil) }
            // No HEAD yet (a repository without commits): the status's files, without counts.
            let files = read ?? (scope == .task ? [] : entries.map {
                GitRepository.ReviewFile(status: $0.letter(staged: !$0.isUnstaged), added: nil, removed: nil, path: $0.path, orig: $0.orig)
            })
            let problem: String? = scope == .task && base == nil
                ? T("Where this task started was not found", "Não achei onde esta tarefa começou")
                : scope == .task && read == nil ? T("Git could not list the task's changes", "O git não listou as mudanças da tarefa") : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.changesRunning = false
                    if self.changesPending {
                        self.changesPending = false
                        return self.loadChanges()
                    }
                    guard self.repo === repo else { return }
                    let kept = keep.map { set in files.filter { set.contains($0.path) } } ?? files
                    self.changeTotal = kept.count
                    self.changeRows = ChangesRow.rows(kept, entries: entries, keep: nil)
                    self.panel.renderChanges(turnSeen: scope != .lastTurn || turn != nil, problem: problem)
                }
            }
        }
    }

    nonisolated static func resolved(_ path: String) -> String { (path as NSString).resolvingSymlinksInPath }

    /// A row was clicked: its uncommitted diff; in Task, or a file changed only in the task's
    /// commits, the review, which shows the task against its start.
    func openChange(_ row: ChangesRow) {
        // Task: the file as the whole task changed it, in the review.
        guard scope != .task, let entry = row.entry else { return _ = run("git.review-open") }
        openDiff(entry, staged: entry.isStaged && !entry.isUnstaged)
    }

    /// git.commit ("Commit…"): asks the message in a sheet, then commits what is staged, or every
    /// change after a yes when nothing is.
    public func commit() {
        guard repo != nil else { return }
        guard !status.entries.isEmpty else { return panel.show(error: T("No changes to commit", "Nenhuma mudança para o commit")) }
        guard let window = panel.window else { return }
        let alert = NSAlert()
        alert.messageText = T("Commit", "Commit")
        let staged = status.entries.contains(where: \.isStaged)
        let count = status.entries.filter(\.isStaged).count
        alert.informativeText = staged ? T("The \(count) staged file(s).", "Os \(count) arquivo(s) no stage.")
            : T("Nothing is staged: every change goes in.", "Nada no stage: todas as mudanças entram.")
        let field = NSTextField(string: "")
        field.placeholderString = T("Message", "Mensagem")
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: T("Commit", "Fazer o commit"))
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1B}"
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.commit(message: field.stringValue, all: !staged) }
        }
    }

    /// The commit itself (the sheet's, and tests'): an empty message is refused.
    func commit(message: String, all: Bool) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return panel.show(error: T("Write a commit message", "Escreva uma mensagem para o commit"))
        }
        perform { $0.commit(message, all: all) }
    }

    /// git.open-pr.
    public func openPullRequest() {
        guard let repo else { return }
        onOpenPullRequest?(repo.root)
    }
}
