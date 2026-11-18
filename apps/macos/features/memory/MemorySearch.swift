import CommandPalette
import Foundation
import Icons
import Strings

/// "Search what this project knows" (memory.search; the Inspector's Memory tab, plan 26 C2c): the
/// wiki's pages in ⌘K, by every word in the title, kind, path or summary; picked, a page opens.
@MainActor
final class MemoryPageSource: PaletteSource {
    var placeholder: String { T("Search what this project knows", "Buscar o que este projeto sabe") }
    var emptyText: String { T("No page matches", "Nenhuma página bate") }
    var icon: Icon { .magnifyingGlass }
    private let pages: [MemoryPage]
    private let open: @MainActor (MemoryPage) -> Void

    init(pages: [MemoryPage], open: @escaping @MainActor (MemoryPage) -> Void) {
        self.pages = pages
        self.open = open
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        show(Self.matching(pages, query).prefix(200).map { page in
            PaletteItem(id: page.path, title: page.title, detail: [page.kind, page.relative].compactMap { $0 }.joined(separator: " · "), icon: .fileMd)
        }, nil)
    }

    func choose(_ item: PaletteItem) {
        if let page = pages.first(where: { $0.path == item.id }) { open(page) }
    }

    /// Nothing runs in the background: the pages came with the tab.
    func stop() {}

    /// Every word somewhere in the page's title, kind, path or summary; newest first.
    static func matching(_ pages: [MemoryPage], _ query: String) -> [MemoryPage] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return pages.filter { page in
            let text = [page.title, page.kind ?? "", page.relative, page.summary ?? ""].joined(separator: " ").lowercased()
            return words.allSatisfy(text.contains)
        }.sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
    }
}

extension MemoryFolder {
    /// Every page under this folder, at any depth.
    /// Every page a person reads: the engine's own files left out (plan 34, seen with bkdg-center's
    /// wiki on 2026-11-18: _meta, the month's log and the pending proposals listed as pages, by id).
    public var allPages: [MemoryPage] { (pages + folders.flatMap(\.allPages)).filter { !$0.isEngineFile } }
}
