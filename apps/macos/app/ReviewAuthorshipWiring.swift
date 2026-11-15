import AgentTools
import AppKit
import Review
import SessionKit
import SourceControl
import Strings
import Worktrees

/// Line authorship in the app (docs/adr/0027-local-authorship.md, plan 21
/// phase E): with review.authorship on, the session kit gets a PostToolUse
/// hook (`cadex hook PostToolUse`, which sends ranges only); each edit goes
/// to its worktree's tracker; disk changes and each read of a review are
/// compared; the review tab draws the agent's lines.
@MainActor
enum AuthorshipHub {
    static var trackers: [String: ReviewAuthorshipTracker] = [:]
    static var on = true
    /// review.toggle-authorship: the marks shown or not, in every window.
    static var shown = true

    static func tracker(for root: String) -> ReviewAuthorshipTracker {
        if let tracker = trackers[root] { return tracker }
        let main = WorktreesCore.list(repo: root).first?.path ?? root
        let tracker = ReviewAuthorshipTracker(root: root, repo: (main as NSString).lastPathComponent, worktree: (root as NSString).lastPathComponent)
        trackers[root] = tracker
        return tracker
    }

    private static var swept = false

    /// The setting: the hook in the kit, or not (then nothing is kept either).
    static func apply(_ enabled: Bool) {
        on = enabled
        if !swept {
            swept = true
            ReviewAuthorshipTracker.sweep()
        }
        let kit = SessionKit.shared
        guard enabled, let tools = kit.toolsPath else { return kit.withdraw("review") }
        let command = "'" + tools.replacingOccurrences(of: "'", with: "'\\''") + "' hook PostToolUse"
        kit.contribute("review", SessionKitPart(settings: ["hooks": ["PostToolUse": [
            ["matcher": "Edit|Write|MultiEdit|NotebookEdit", "hooks": [["type": "command", "command": command, "timeout": 5]]],
        ]]]))
    }

    /// An agent's edit: its worktree is found off the main thread (git).
    static func record(_ event: AgentHookEvent) {
        guard on, let edit = event.edit else { return }
        let session = event.sessionID ?? event.kitSession ?? "?"
        DispatchQueue.global(qos: .utility).async {
            let root = WorktreesCore.repository(of: (edit.file as NSString).deletingLastPathComponent)
            DispatchQueue.main.async { MainActor.assumeIsolated {
                guard let root else { return }
                tracker(for: root).record(path: edit.file, lines: edit.lines, whole: edit.whole, session: session)
            } }
        }
    }

    static func diskChanged(_ folders: [String]) {
        guard on else { return }
        for tracker in trackers.values { tracker.diskChanged(folders: folders) }
    }
}

extension WindowSession {
    func attachAuthorship(to review: ReviewDocument) {
        guard review.request.to == nil else { return }
        let tracker = AuthorshipHub.tracker(for: review.request.repo)
        let before = review.onLoaded
        review.onLoaded = { [weak self, weak review] in
            before?()
            guard let review else { return }
            // A worktree outside the workspace sends no disk events: compare now.
            AuthorshipHub.tracker(for: review.request.repo).diskChanged()
            self?.drawAuthorship(on: review)
        }
        tracker.onChange = { [weak self] in
            for case let open as ReviewDocument in self?.tabs?.allDocuments ?? [] where open.request.repo == review.request.repo { self?.drawAuthorship(on: open) }
        }
        drawAuthorship(on: review)
    }

    func drawAuthorship(on review: ReviewDocument) {
        let tracker = AuthorshipHub.tracker(for: review.request.repo)
        guard AuthorshipHub.on, AuthorshipHub.shown else {
            review.lineMarks = [:]
            review.marksStopped = []
            return
        }
        review.lineMarks = Dictionary(uniqueKeysWithValues: review.paths.map { ($0, tracker.marks(of: $0)) }.filter { !$0.1.isEmpty })
        review.marksStopped = Set(tracker.files.filter(\.value.stopped).map(\.key))
    }

    func registerAuthorship() {
        func review() -> ReviewDocument? { (tabs?.activeDocument as? ReviewDocument).flatMap { $0.request.to == nil ? $0 : nil } }
        commands.register(ReviewAuthorshipCommands.all(
            toggle: { [weak self] in
                AuthorshipHub.shown.toggle()
                for case let open as ReviewDocument in self?.tabs?.allDocuments ?? [] { self?.drawAuthorship(on: open) }
            },
            export: { [weak self] in
                guard let review = review(), let data = AuthorshipHub.tracker(for: review.request.repo).export(), let window = self?.window else { return }
                let panel = NSSavePanel()
                panel.nameFieldStringValue = (review.request.repo as NSString).lastPathComponent + "-authorship.json"
                panel.beginSheetModal(for: window) { response in
                    if response == .OK, let url = panel.url { try? data.write(to: url) }
                }
            },
            canToggle: { AuthorshipHub.on ? nil : T("Line authorship is off in Settings", "A autoria das linhas está desligada nas configurações") },
            canExport: { review() == nil || !AuthorshipHub.on ? T("No review open", "Nenhuma revisão aberta") : nil }))
    }
}
