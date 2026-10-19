import CCadex
import Foundation

/// A row of the tree. Folders read their contents only when opened, and a
/// reload keeps the nodes whose name and kind did not change, so open
/// folders stay open and the selection stays (docs/spec/explorer.md).
@MainActor
final class FileNode {
    let path: String
    let name: String
    /// Updated on reload (the size changes; the row stays).
    private(set) var entry: FileEntry?
    /// Nil until the folder is opened for the first time.
    private(set) var children: [FileNode]?
    /// Why the folder could not be read ("Sem permissão").
    private(set) var problem: String?
    /// A row that only carries a note ("Pasta vazia"), not a file.
    let isNote: Bool

    init(path: String, entry: FileEntry?) {
        self.path = path
        self.name = entry?.name ?? (path as NSString).lastPathComponent
        self.entry = entry
        isNote = false
    }

    private init(note: String, in folder: String) {
        path = folder + "/\u{0}" + note
        name = note
        entry = nil
        isNote = true
    }

    /// The root is always a folder; other rows by their kind.
    var isFolder: Bool { !isNote && (entry?.opensAsFolder ?? true) }
    var isHidden: Bool { name.hasPrefix(".") }
    var isLoaded: Bool { children != nil }

    /// Reads the folder again, keeping unchanged children (and their own
    /// children) as they were.
    func load() {
        guard isFolder else { return }
        do {
            let entries = try ExplorerFiles.list(path)
            var old: [String: FileNode] = [:]
            for child in children ?? [] { old[child.name] = child }
            children = entries.map { entry in
                if let kept = old[entry.name], kept.entry?.opensAsFolder == entry.opensAsFolder,
                   kept.entry?.kind == entry.kind {
                    kept.entry = entry
                    return kept
                }
                return FileNode(path: Self.join(path, entry.name), entry: entry)
            }
            problem = nil
        } catch {
            children = []
            problem = error.status == CADEX_PERMISSION_DENIED ? "Sem permissão" : "Pasta indisponível"
        }
    }

    /// What the tree shows inside this folder: hidden files only when asked,
    /// and a note when there is nothing to show.
    func visibleChildren(showHidden: Bool) -> [FileNode] {
        guard let children else { return [] }
        if let problem { return [noteRow(problem)] }
        let shown = showHidden ? children : children.filter { !$0.isHidden }
        return shown.isEmpty ? [noteRow("Pasta vazia")] : shown
    }

    /// Notes are made once per folder and text, so the outline sees the same
    /// object on every reload.
    private var notes: [String: FileNode] = [:]
    private func noteRow(_ text: String) -> FileNode {
        if let note = notes[text] { return note }
        let note = FileNode(note: text, in: path)
        notes[text] = note
        return note
    }

    /// Every loaded folder at or below this one, this one first.
    func loadedFolders() -> [FileNode] {
        guard isLoaded else { return [] }
        return [self] + (children ?? []).flatMap { $0.loadedFolders() }
    }

    /// The loaded node at `target`, searching down from here.
    func find(_ target: String) -> FileNode? {
        if target == path { return self }
        guard target.hasPrefix(path == "/" ? "/" : path + "/") else { return nil }
        for child in children ?? [] where !child.isNote {
            if let found = child.find(target) { return found }
        }
        return nil
    }

    static func join(_ folder: String, _ name: String) -> String {
        folder.hasSuffix("/") ? folder + name : folder + "/" + name
    }
}
