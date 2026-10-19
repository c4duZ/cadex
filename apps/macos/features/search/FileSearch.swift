import AppKit
import CCadex
import CommandPalette
import Icons

/// ⌘P: the workspace's files by name (docs/spec/search.md). The core keeps
/// the names in memory and current; each keystroke ranks them there.
@MainActor
public final class FileSearch: PaletteSource {
    /// How many rows a query shows.
    static let limit = 50
    static let maxRecent = 20

    /// Read by deinit, which is not on the main actor; closing is safe from
    /// any thread in the core.
    nonisolated(unsafe) private var index: OpaquePointer?
    private(set) var root = ""
    /// Opened from here, most recent first, as paths relative to the root.
    private(set) var recent: [String] = []
    /// Opens a chosen file (absolute path; line, when known; beside or not).
    let open: (String, Int?, Bool?) -> Void

    init(open: @escaping (String, Int?, Bool?) -> Void) {
        self.open = open
    }

    /// Indexes another folder (the workspace changed, or hidden files).
    func setRoot(_ path: String, showHidden: Bool) {
        cadex_search_index_close(index)
        index = nil
        if path != root { recent = [] }
        root = path
        var out: OpaquePointer?
        if cadex_search_index_open(path, showHidden, &out) == CADEX_OK { index = out }
    }

    public var placeholder: String { "Buscar arquivo pelo nome" }
    public var emptyText: String { "Nenhum arquivo encontrado" }
    public var icon: Icon { .files }
    public var hints: [PaletteHint] {
        [PaletteHint("↩", "abrir"), PaletteHint("⌥↩", "ao lado"), PaletteHint("⌘↩", "em nova aba")]
    }

    public func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard !query.isEmpty else {
            return show(recent.map { item(path: $0, positions: []) }, recent.isEmpty ? "Digite para buscar arquivos" : "Recentes")
        }
        show(rank(query).map { item(path: $0.path, positions: $0.positions) }, indexStatus())
    }

    public func choose(_ item: PaletteItem) {
        remember(item.id)
        open(FileSearchPaths.absolute(item.id, in: root), nil, nil)
    }

    public func choose(_ item: PaletteItem, as choice: PaletteChoice) {
        remember(item.id)
        open(FileSearchPaths.absolute(item.id, in: root), nil, choice == .primary ? nil : choice == .option)
    }

    public func stop() {}

    func remember(_ rel: String) {
        recent.removeAll { $0 == rel }
        recent.insert(rel, at: 0)
        if recent.count > Self.maxRecent { recent.removeLast() }
    }

    /// The core's ranking: relative paths and the matched byte offsets.
    func rank(_ query: String) -> [(path: String, positions: [Int])] {
        guard let index else { return [] }
        let bytes = Array(query.utf8)
        var result = cadex_search_files_result()
        let status = bytes.withUnsafeBufferPointer { cadex_search_files(index, $0.baseAddress, $0.count, Self.limit, &result) }
        defer { cadex_search_files_result_free(&result) }
        guard status == CADEX_OK, let matches = result.matches, let paths = result.paths else { return [] }
        return (0..<result.count).map { i in
            let m = matches[i]
            let path = String(decoding: UnsafeBufferPointer(start: paths + Int(m.path_offset), count: Int(m.path_len)), as: UTF8.self)
            let positions = (0..<Int(m.positions_count)).map { Int(result.positions![Int(m.positions_offset) + $0]) }
            return (path, positions)
        }
    }

    /// "Indexando… 1234" until the first full read is done.
    private func indexStatus() -> String? {
        var ready = false
        let count = cadex_search_index_count(index, &ready)
        return ready ? nil : "Indexando… \(count)"
    }

    /// The name as the title, its folder in grey, the type's icon: the
    /// owner found whole paths hard to scan (2026-10-19). The matched
    /// letters of the name stay bold.
    private func item(path: String, positions: [Int]) -> PaletteItem {
        let name = (path as NSString).lastPathComponent
        let start = path.utf8.count - name.utf8.count
        let inName = positions.filter { $0 >= start }.map { $0 - start }
        let folder = (path as NSString).deletingLastPathComponent
        return PaletteItem(id: path, title: name, bold: PaletteItem.boldRanges(in: name, byteOffsets: inName),
                           detail: folder.isEmpty ? nil : folder, icon: FileIcons.icon(forFileNamed: name),
                           image: FileIcons.image(forFileNamed: name))
    }

    deinit {
        cadex_search_index_close(index)
    }
}

enum FileSearchPaths {
    static func absolute(_ rel: String, in root: String) -> String {
        root.hasSuffix("/") ? root + rel : root + "/" + rel
    }
}
