import AppKit
import Tabs

/// Entry point of the git-history feature (docs/spec/git-history.md): the
/// repository's history in a tab. Pages come from the core on the log's
/// queue as the list scrolls; typing filters what is loaded, Enter searches
/// the whole repository.
@MainActor
public final class HistoryDocument: TabDocument {
    public enum State: Equatable { case loading, ready, empty, failed }

    public let root: String
    public var onChange: (() -> Void)?
    /// A file of a commit: (repository, sha, path, old path). The app opens
    /// source-control's diff tab.
    public var onOpenDiff: ((String, String, String, String) -> Void)?
    /// Menus and buttons run commands by id (ADR 0005).
    public var runCommand: ((String) -> Bool)?
    let historyView = HistoryView()
    public var view: NSView { historyView }

    private(set) var state: State = .loading
    private var log: HistoryLog
    private(set) var commits: [HistoryCommit] = []
    private var searchLog: HistoryLog?
    /// The repository-wide search's results, while there is one.
    private(set) var searchResults: [HistoryCommit]?
    private(set) var filter = ""
    private(set) var currentOnly = false
    private var loading = false
    private var reloadPending = false
    private(set) var selected: HistoryCommit?
    private(set) var details: CommitDetails?
    private(set) var remoteURL: URL?

    public init(root: String) {
        self.root = root
        log = HistoryLog(root: root)
        historyView.document = self
        loadMore()
    }

    public static func identity(for root: String) -> String { "history:\(root)" }
    public var identity: String { Self.identity(for: root) }
    public var title: String { "Histórico: " + (root as NSString).lastPathComponent }
    public var hasUnsavedChanges: Bool { false }
    public func focus() { view.window?.makeFirstResponder(historyView.table) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    /// What the list shows: the search's results, the loaded commits that
    /// match the filter, or all of them with the graph.
    var shown: [HistoryCommit] {
        if let searchResults { return searchResults }
        guard !filter.isEmpty else { return commits }
        return commits.filter { $0.subject.localizedCaseInsensitiveContains(filter) || $0.author.localizedCaseInsensitiveContains(filter) || $0.sha.hasPrefix(filter.lowercased()) }
    }

    var showsGraph: Bool { searchResults == nil && filter.isEmpty }

    /// The next page of whichever log the list shows.
    func loadMore() {
        let source = searchLog ?? log
        guard !loading, !source.ended else { return }
        loading = true
        historyView.setBusy(true)
        source.queue.async { [weak self] in
            let page = source.next()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.received(page, from: source) }
            }
        }
    }

    private func received(_ page: [HistoryCommit], from source: HistoryLog) {
        loading = false
        historyView.setBusy(false)
        if source === searchLog {
            searchResults = (searchResults ?? []) + page
        } else if source === log {
            commits += page
            state = !commits.isEmpty ? .ready : source.failed ? .failed : .empty
        } else {
            return
        }
        historyView.render()
        if reloadPending {
            reloadPending = false
            reload()
        }
    }

    /// Reads the log again from the top (a new commit, a checkout), keeping
    /// the selected commit when it is still there.
    public func reload() {
        guard !loading else { return reloadPending = true }
        log = HistoryLog(root: root, currentOnly: currentOnly)
        commits = []
        loadMore()
    }

    /// The repository changed on disk: refs and HEAD live in .git.
    public func diskChanged(_ paths: [String]) {
        let git = root + "/.git"
        guard paths.contains(where: { $0 == git || $0.hasPrefix(git + "/") }) else { return }
        guard !reloadPending else { return }
        reloadPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.reloadPending else { return }
            self.reloadPending = false
            self.reload()
        }
    }

    func setFilter(_ text: String) {
        filter = text
        searchLog = nil
        searchResults = nil
        historyView.render()
    }

    /// Enter in the search field: the whole repository, not only what is loaded.
    func searchRepository(_ text: String) {
        guard !text.isEmpty else { return setFilter("") }
        filter = text
        searchLog = HistoryLog(root: root, query: text, currentOnly: currentOnly)
        searchResults = []
        loading = false
        historyView.render()
        loadMore()
    }

    /// history.current-branch
    public func toggleCurrentOnly() {
        currentOnly.toggle()
        historyView.render()
        if searchLog != nil { searchRepository(filter) }
        reload()
    }

    func select(_ commit: HistoryCommit?) {
        selected = commit
        details = nil
        remoteURL = nil
        historyView.showDetails()
        guard let commit else { return }
        let source = log
        source.queue.async { [weak self] in
            let details = source.details(commit.sha)
            let url = source.remoteURL(commit.sha)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.selected == commit else { return }
                    self.details = details
                    self.remoteURL = url
                    self.historyView.showDetails()
                }
            }
        }
    }

    func openDiff(_ file: CommitDetails.File) {
        guard let selected else { return }
        onOpenDiff?(root, selected.sha, file.path, file.orig)
    }

    /// history.copy-sha
    public func copySha() {
        guard let selected else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selected.sha, forType: .string)
    }

    /// history.open-remote: the address comes with the details; right after
    /// selecting (the context menu) it may still be on its way.
    public func openRemote() {
        if let remoteURL {
            NSWorkspace.shared.open(remoteURL)
            return
        }
        guard let selected else { return }
        let source = log
        source.queue.async {
            let url = source.remoteURL(selected.sha)
            DispatchQueue.main.async {
                if let url { NSWorkspace.shared.open(url) } else { NSSound.beep() }
            }
        }
    }

    public var hasSelection: Bool { selected != nil }

    /// history.search
    public func focusSearch() {
        view.window?.makeFirstResponder(historyView.searchField)
    }
}
