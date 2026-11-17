import AppKit
import Strings

/// Entry point of the source-control feature (docs/spec/source-control.md):
/// the Git view of the sidebar for the workspace's repository. git runs on
/// the repository's queue; results come back here, on the main thread.
@MainActor
public final class SourceControlController {
    public struct DiffRequest: Equatable, Sendable {
        public let repo: String
        public let path: String
        public let orig: String
        public let staged: Bool
        /// A file as this commit changed it (the history), instead of the
        /// working copy.
        public let commit: String?
        /// The file is in conflict: it opens in three columns (plan 21 phase C).
        public var conflict = false

        public init(repo: String, path: String, orig: String, staged: Bool, commit: String? = nil) {
            self.repo = repo
            self.path = path
            self.orig = orig
            self.staged = staged
            self.commit = commit
        }
    }

    public enum State: Equatable {
        case noRepository
        case gitMissing
        case loading
        case ready
    }

    let panel = SourceControlView()
    public var view: NSView { panel }

    /// Changes' footer line: "make check passed · 2 min ago"; nil hides it.
    public func showCheck(_ text: String?, passed: Bool) { panel.showCheck(text, passed: passed) }
    private(set) var repo: GitRepository?
    /// The repository's top folder, for the history (git-history).
    public var repositoryRoot: String? { repo?.root }
    private(set) var status = GitRepository.Status()
    private(set) var state: State = .loading
    private var folder = ""
    private var refreshPending = false
    private var refreshRunning = false

    /// Changed files for the explorer: absolute path -> letter (M A D R U ?).
    public var onMarks: (([String: Character]) -> Void)?
    /// The branch, and the commits to push and to pull, after each status
    /// (the status bar's Git branch item); nil outside a repository. It
    /// rides on the status the panel reads anyway: no git run of its own.
    public var onBranch: ((Branch?) -> Void)?
    /// An action (fetch, pull, push, commit…) started or ended: the
    /// sidebar's header spins while it runs.
    public var onBusy: ((Bool) -> Void)?

    public struct Branch: Equatable, Sendable {
        /// The branch's name, or the short commit when detached.
        public let name: String
        public let ahead: Int
        public let behind: Int
    }
    /// A file of the lists was clicked: show its diff.
    /// The diff to open; the Bool says beside (true) or in a new tab
    /// (false), nil is the general.openFiles setting.
    public var onOpenDiff: ((DiffRequest, Bool?) -> Void)?
    /// Opens a file in the app (context menu "Abrir o arquivo").
    public var onOpenFile: ((String, Bool?) -> Void)?
    /// Runs a command by id (buttons and keys go through the registry).
    let run: (String) -> Bool

    /// Changes' scope (plan 26 phase C2): what the list shows; changing it reads again.
    public var scope: ChangesScope = .uncommitted {
        didSet { if scope != oldValue { loadChanges() } }
    }
    /// Where the task of a repository started (the branch New Task kept), from the app.
    public var taskStart: (@MainActor (String) -> String?)?
    /// The files the agent edited in its last turn in a repository (absolute paths), from the app;
    /// nil: no turn seen there.
    public var lastTurnFiles: (@MainActor (String) -> Set<String>?)?
    /// git.open-pr: the app opens a tab in the repository with the GitHub CLI.
    public var onOpenPullRequest: ((String) -> Void)?
    /// The list as the scope shows it, read after each status.
    var changeRows: [ChangesRow] = []
    /// How many files the scope has, past the rows' cap too ("N more").
    var changeTotal = 0
    /// The list was not read while the tab was hidden: it reads when it shows.
    var changesStale = false
    var changesRunning = false
    /// Asked again while a read ran (a scope switch, a new status): it reads once more after.
    var changesPending = false

    /// The last branch seen in each repository, shown while its status is read.
    private var knownBranches: [String: Branch] = [:]

    public init(folder: String, run: @escaping (String) -> Bool) {
        self.run = run
        panel.controller = self
        setFolder(folder)
    }

    /// The workspace changed: find its repository again.
    /// The top folder of the repository holding `folder`, or nil. Runs git:
    /// call it off the main thread (the app asks when a terminal changes
    /// folder, to follow it in the explorer).
    public nonisolated static func repositoryRoot(containing folder: String) -> String? {
        GitRepository.find(from: folder)?.root
    }

    public func setFolder(_ path: String) {
        folder = path
        state = .loading
        panel.render()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let available = GitRepository.isGitAvailable
            let found = available ? GitRepository.find(from: path) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.folder == path else { return }
                    self.repo = found
                    self.state = !available ? .gitMissing : (found == nil ? .noRepository : .loading)
                    self.status = GitRepository.Status()
                    // The last repository's files go at once, not when the new list is read.
                    self.changeRows = []
                    self.changeTotal = 0
                    self.panel.renderChanges(turnSeen: true, problem: nil)
                    self.panel.render()
                    // A repository's last branch shows at once, and nothing is
                    // said before its status comes: an empty status hid the
                    // branch and moved the status bar, then it came back
                    // (the owner, 2026-10-22).
                    if let root = found?.root, let known = self.knownBranches[root] { self.onBranch?(known) }
                    if found == nil { self.publishMarks() }
                    self.refresh()
                }
            }
        }
    }

    /// Something changed on disk: read the status again, once per burst.
    public func diskChanged(_ paths: [String]) {
        guard let root = repo?.root, paths.contains(where: { $0 == root || $0.hasPrefix(root + "/") }) else { return }
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshPending = false
            self?.refresh()
        }
    }

    /// git.refresh.
    public func refresh() {
        guard let repo else { return }
        guard !refreshRunning else {
            refreshPending = false
            return diskChanged([repo.root])
        }
        refreshRunning = true
        repo.queue.async { [weak self] in
            let status = repo.status()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refreshRunning = false
                    guard self.repo === repo else { return }
                    if let status { self.status = status }
                    self.state = .ready
                    self.panel.render()
                    self.publishMarks()
                    self.loadChanges()
                }
            }
        }
    }

    private func publishMarks() {
        // Before the first status the name is empty: nothing to show yet.
        let name = status.detached ? String(status.oid.prefix(7)) : status.branch
        let branch = repo == nil || name.isEmpty ? nil : Branch(name: name, ahead: status.ahead, behind: status.behind)
        if let root = repo?.root, let branch { knownBranches[root] = branch }
        onBranch?(branch)
        guard let root = repo?.root else { return onMarks?([:]) ?? () }
        var marks: [String: Character] = [:]
        for e in status.entries {
            marks[root + "/" + e.path] = e.kind == .conflict ? "U" : (e.isUnstaged ? e.letter(staged: false) : e.letter(staged: true))
        }
        onMarks?(marks)
    }

    // MARK: Actions

    /// Runs an action on the queue, then shows its message (if any) and
    /// refreshes.
    func perform(_ work: @escaping @Sendable (GitRepository) -> String?) {
        guard let repo else { return }
        onBusy?(true)
        repo.queue.async { [weak self] in
            let message = work(repo)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.onBusy?(false)
                    self?.panel.show(error: message)
                    self?.refresh()
                }
            }
        }
    }

    func stage(_ entries: [GitRepository.Entry]) {
        let paths = entries.flatMap { $0.orig.isEmpty ? [$0.path] : [$0.path, $0.orig] }
        perform { $0.stage(paths) }
    }

    func unstage(_ entries: [GitRepository.Entry]) {
        let paths = entries.flatMap { $0.orig.isEmpty ? [$0.path] : [$0.path, $0.orig] }
        perform { $0.unstage(paths) }
    }

    public func stageAll() { stage(status.entries.filter(\.isUnstaged)) }
    public func unstageAll() { unstage(status.entries.filter(\.isStaged)) }
    public func fetch() { perform { $0.fetch() } }
    public func pull() { perform { $0.pull() } }

    /// Without an upstream, offers to publish the branch first.
    public func push() {
        guard !status.upstream.isEmpty || status.detached else {
            let branch = status.branch
            return confirm(T("Publish branch \(branch)?", "Publicar a branch \(branch)?"), detail: T("It goes to origin and becomes tracked.", "Ela vai para o origin e passa a ser acompanhada."),
                           action: T("Publish", "Publicar")) { [weak self] in self?.perform { $0.push(publish: branch) } }
        }
        perform { $0.push(publish: nil) }
    }

    /// Discards with confirmation; new files go to the Trash.
    func discard(_ entries: [GitRepository.Entry]) {
        guard let repo, !entries.isEmpty else { return }
        let what = entries.count == 1 ? entries[0].path : T("\(entries.count) files", "\(entries.count) arquivos")
        confirm(T("Discard the changes to \(what)?", "Descartar as mudanças em \(what)?"), detail: T("This can't be undone (new files go to the Trash).", "Isso não pode ser desfeito (arquivos novos vão para a Lixeira)."),
                action: T("Discard", "Descartar")) { [weak self] in
            for e in entries where e.kind == .untracked {
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: repo.root + "/" + e.path), resultingItemURL: nil)
            }
            let tracked = entries.filter { $0.kind != .untracked }.map(\.path)
            self?.perform { tracked.isEmpty ? nil : $0.discard(tracked) }
        }
    }

    func initRepository() {
        let folder = self.folder
        DispatchQueue.global().async { [weak self] in
            let message = GitRepository.initialize(folder)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.panel.show(error: message)
                    self?.setFolder(folder)
                }
            }
        }
    }

    func openDiff(_ entry: GitRepository.Entry, staged: Bool, beside: Bool? = nil) {
        guard let repo else { return }
        var request = DiffRequest(repo: repo.root, path: entry.path, orig: entry.orig, staged: staged)
        request.conflict = entry.kind == .conflict
        onOpenDiff?(request, beside)
    }

    func openFile(_ entry: GitRepository.Entry, beside: Bool? = nil) {
        guard let repo else { return }
        onOpenFile?(repo.root + "/" + entry.path, beside)
    }

    /// git.reveal: the changed files in the Finder (deleted ones are not there).
    func reveal(_ entries: [GitRepository.Entry]) {
        guard let repo else { return }
        let urls = entries.map { URL(fileURLWithPath: repo.root + "/" + $0.path) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    private func confirm(_ title: String, detail: String, action: String, then go: @escaping @MainActor () -> Void) {
        guard let window = panel.window else { return go() }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1B}"
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { MainActor.assumeIsolated { go() } }
        }
    }
}
