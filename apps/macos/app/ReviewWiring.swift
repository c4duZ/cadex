import AppKit
import CommandPalette
import Settings
import SourceControl
import Strings
import Tabs
import Worktrees

/// The review tab in this window (docs/spec/review.md, plan 21 phase B2):
/// git.review-open reviews the repository of the focused terminal's folder
/// (else the workspace's) against where its task started (the branch New
/// Task kept, through worktrees); Tasks, the task's group in Agents and the
/// Git page's header run the same command. Settings follow the tab's
/// toggles; a change on disk inside the repository reads it again.
extension WindowSession {
    func registerReview(palette: CommandPaletteController) {
        commands.register(ReviewCommands.all(
            active: { [weak self] in self?.tabs?.activeDocument as? ReviewDocument },
            palette: palette,
            open: { [weak self] in self?.openReview() },
            canOpen: { [weak self] in self?.reviewFolder() == nil ? T("No git repository here", "Nenhum repositório git aqui") : nil },
            compare: { [weak self] repo, a, b in self?.openReview(ReviewDocument.Request(repo: repo, base: a, to: b)) },
            repo: { [weak self] in self?.reviewFolder() }))
        commands.register(ConflictCommands.all(
            conflict: { [weak self] in self?.tabs?.activeDocument as? ConflictDocument },
            review: { [weak self] in self?.tabs?.activeDocument as? ReviewDocument },
            diff: { [weak self] in self?.tabs?.activeDocument as? DiffDocument }))
        registerReviewComments(palette: palette)
        registerAuthorship()
    }

    /// The repository to review: the focused terminal's, else the workspace's.
    func reviewFolder() -> String? {
        let folder = tabs?.activeTerminal?.currentDirectory ?? self.folder.root
        return WorktreesCore.repository(of: folder) ?? WorktreesCore.repository(of: self.folder.root)
    }

    /// git.review-open for `repo` (a task's worktree), or the current one.
    func openReview(repo given: String? = nil) {
        guard let repo = given ?? reviewFolder() else { return }
        let start = WorktreesController.shared.store.task(repo)?.base
        openReview(ReviewDocument.Request(repo: repo, start: start))
    }

    func openReview(_ request: ReviewDocument.Request) {
        guard let tabs else { return }
        if let existing = tabs.document(identity: ReviewDocument.identity(for: request)) as? ReviewDocument {
            existing.load()
            return tabs.open(existing)
        }
        let git = settings.store.settings.git
        let review = ReviewDocument(request: request, context: git.reviewContextLines, wrap: git.reviewWrap, whitespace: git.reviewShowWhitespace)
        review.openFile = { [weak self, weak review] path in self?.opener?.open(path, from: review) }
        review.onOpenConflict = { [weak self] repo, path in self?.opener?.openConflict(repo: repo, path: path) }
        review.onSetting = { [weak self] context, wrap, whitespace in
            self?.settings.store.update {
                $0.git.reviewContextLines = context
                $0.git.reviewWrap = wrap
                $0.git.reviewShowWhitespace = whitespace
            }
        }
        attachComments(to: review)
        attachAuthorship(to: review)
        tabs.open(review, beside: false)
    }

    /// Folders changed on disk: a review whose repository holds one reads again.
    func reviewsDiskChanged(_ folders: [String]) {
        for case let review as ReviewDocument in spacesTabs().flatMap(\.allDocuments) {
            let root = review.request.repo + "/"
            if folders.contains(where: { ($0 + "/").hasPrefix(root) }) { review.loadSoon() }
        }
    }

    private func spacesTabs() -> [TabsController] {
        projects?.projects.map(\.tabs) ?? []
    }
}
