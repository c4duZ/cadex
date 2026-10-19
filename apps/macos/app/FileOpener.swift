import AppKit
import Editor
import Explorer
import GitHistory
import MediaPreview
import SourceControl
import Tabs
import Terminal
import Themes

/// Where a chosen file opens (explorer, ⌘P, ⌘⇧F): a media tab for images,
/// video, audio, PDF and what Quick Look shows; an editor tab for the rest.
@MainActor
final class FileOpener {
    /// The shown space's tabs, where things open.
    private let currentTabs: () -> TabsController?
    /// Every space's tabs, for disk changes.
    private let everyTabs: () -> [TabsController]
    /// A file was opened in a new editor tab (markdown attaches its help).
    var onEditorOpened: ((EditorDocument) -> Void)?
    /// Runs a command by id, for tabs whose menus fire commands (history).
    var runCommand: ((String) -> Bool)?

    init(tabs: @escaping () -> TabsController?, every: @escaping () -> [TabsController]) {
        currentTabs = tabs
        everyTabs = every
    }

    /// Opens `path`, at a 1-based line when given.
    func open(_ given: String, line: Int? = nil) {
        guard let tabs = currentTabs() else { return }
        let path = Self.canonical(given)
        let document = tabs.document(identity: path) ?? makeFile(path)
        tabs.open(document)
        if let line, let editor = document as? EditorDocument {
            // After the tab is in the window, so the view has its size.
            DispatchQueue.main.async { editor.reveal(line: line) }
        }
    }

    /// A saved pane's document, made without opening it (the spaces place
    /// it): files that still exist and the git history. Diffs and web
    /// previews are passing things and stay closed. Its folder is
    /// authorized again: the core forgets them between launches, and the
    /// history of a repository outside the workspace failed (2026-10-19).
    func makeDocument(identity: String) -> TabDocument? {
        if identity.hasPrefix("/") {
            guard FileManager.default.fileExists(atPath: identity),
                  WorkspaceFolder.allow((identity as NSString).deletingLastPathComponent) != nil else { return nil }
            return makeFile(identity)
        }
        guard identity.hasPrefix("history:") else { return nil }
        let root = String(identity.dropFirst("history:".count))
        guard FileManager.default.fileExists(atPath: root + "/.git"), WorkspaceFolder.allow(root) != nil else { return nil }
        return makeHistory(root)
    }

    /// Media for images, video, audio, PDF and what Quick Look shows; the
    /// editor for the rest.
    private func makeFile(_ path: String) -> TabDocument {
        guard let kind = MediaKind.of(path: path) else { return makeEditor(path) }
        let media = MediaDocument(path: path, kind: kind)
        media.openExternally = { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) }
        return media
    }

    /// A file's git diff in a tab; the same diff again selects its tab and
    /// reads it again.
    func openDiff(_ request: SourceControlController.DiffRequest) {
        guard let tabs = currentTabs() else { return }
        if let existing = tabs.document(identity: DiffDocument.identity(for: request)) as? DiffDocument {
            existing.load()
            return tabs.open(existing)
        }
        let diff = DiffDocument(request: request)
        diff.openFile = { [weak self] path in self?.open(path) }
        tabs.open(diff)
    }

    /// The repository's history in a tab; again, its tab, read again.
    func openHistory(_ root: String) {
        guard let tabs = currentTabs() else { return }
        if let existing = tabs.document(identity: HistoryDocument.identity(for: root)) as? HistoryDocument {
            existing.reload()
            return tabs.open(existing)
        }
        tabs.open(makeHistory(root))
    }

    private func makeHistory(_ root: String) -> HistoryDocument {
        let history = HistoryDocument(root: root)
        history.runCommand = { [weak self] id in self?.runCommand?(id) ?? false }
        history.onOpenDiff = { [weak self] repo, sha, path, orig in
            self?.openDiff(.init(repo: repo, path: path, orig: orig, staged: false, commit: sha))
        }
        return history
    }

    /// The real path, as the core compares them: /tmp/x is /private/tmp/x.
    /// NSString's resolvingSymlinksInPath drops /private on purpose, so the
    /// Markdown index did not know the note (2026-10-19).
    static func canonical(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }

    private func makeEditor(_ path: String) -> EditorDocument {
        let document = EditorDocument(path: path)
        document.openExternally = { NSWorkspace.shared.open(URL(fileURLWithPath: $0)) }
        onEditorOpened?(document)
        return document
    }

    /// Folders changed on disk: open files in them read themselves again.
    func foldersChanged(_ folders: [String]) {
        let changed = Set(folders)
        let documents = everyTabs().flatMap(\.allDocuments)
        for document in documents where changed.contains((document.identity as NSString).deletingLastPathComponent) {
            (document as? EditorDocument)?.diskMayHaveChanged()
            (document as? MediaDocument)?.diskMayHaveChanged()
        }
        for case let diff as DiffDocument in documents where changed.contains((diff.request.repo + "/" + diff.request.path as NSString).deletingLastPathComponent) {
            diff.load()
        }
        for case let history as HistoryDocument in documents {
            history.diskChanged(folders)
        }
    }
}

/// The editor's font and colors: the terminal's font and the theme's
/// terminal palette, so code reads like the terminal next to it.
@MainActor
enum EditorLooks {
    static func update(theme: Theme, font: NSFont) {
        let t = theme.terminal
        let ui = theme.interface
        EditorAppearance.current = EditorAppearance(
            font: font, background: t.background.nsColor, foreground: t.foreground.nsColor,
            currentLine: t.foreground.color(alpha: 0.06), lineNumber: ui.secondaryText.color(alpha: 0.7),
            selection: t.selection.color(alpha: 0.45),
            tokens: EditorAppearance.tokens(ansi: t.ansi.map(\.value), foreground: t.foreground.value))
    }

    /// As the terminal picks it: "SF Mono" (or a missing family) is the
    /// system's monospaced font.
    static func font(family: String, size: CGFloat) -> NSFont {
        if family != "SF Mono", let font = NSFont(name: family, size: size) { return font }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// From the current theme and terminal preferences.
    static func refresh() {
        let prefs = TerminalPreferences.current
        update(theme: ThemeStore.shared.current, font: font(family: prefs.fontFamily, size: prefs.fontSize))
    }
}
