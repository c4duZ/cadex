import AppKit
import CommandPalette

/// Entry point of the search feature: the two palette sources (⌘P files,
/// ⌘⇧F text) over the workspace folder.
@MainActor
public final class SearchController {
    public let files: FileSearch
    public let content: ContentSearch
    private var current: (root: String, showHidden: Bool)?

    /// `open`: shows a chosen file, at a line when the result has one. Until
    /// the viewers (plan 5) the app opens it in the system's default app.
    public init(root: String, showHidden: Bool, open: @escaping (String, Int?) -> Void) {
        files = FileSearch(open: open)
        content = ContentSearch(open: open)
        setRoot(root, showHidden: showHidden)
    }

    /// Workspace files whose name matches `query` (fuzzy), relative to the
    /// root, best first: for other features' suggestions (markdown `](`).
    public func findFiles(_ query: String, limit: Int = 30) -> [String] {
        Array(files.rank(query).prefix(limit).map(\.path))
    }

    /// The workspace or the hidden-files preference changed. The same
    /// values again (settings apply on every change) keep the index.
    public func setRoot(_ root: String, showHidden: Bool) {
        if let current, current == (root, showHidden) { return }
        current = (root, showHidden)
        files.setRoot(root, showHidden: showHidden)
        content.setRoot(root, showHidden: showHidden)
    }
}

/// The search commands (ADR 0005). The toggles only act while the text
/// search is on screen; otherwise their keys go on to the focused view.
public enum SearchCommands {
    @MainActor
    public static func all(_ search: SearchController, palette: CommandPaletteController) -> [Command] {
        func onScreen() -> String? { palette.currentSource === search.content ? nil : "A busca de texto não está aberta" }
        return [
            Command(id: "search.files", title: "Buscar arquivo pelo nome", keywords: ["go to file", "abrir", "quick open"],
                    category: .file, defaultShortcut: "cmd+p", action: .run { palette.open(search.files) }),
            Command(id: "search.content", title: "Buscar texto nos arquivos", keywords: ["find in files", "grep", "procurar"],
                    category: .file, defaultShortcut: "cmd+shift+f", action: .run { palette.open(search.content) }),
            Command(id: "search.toggle-case", title: "Diferenciar maiúsculas na busca de texto", keywords: ["case", "caixa"],
                    category: .file, defaultShortcut: "cmd+opt+c",
                    action: .run { search.content.caseSensitive.toggle(); palette.refresh() }, unavailableReason: onScreen),
            Command(id: "search.toggle-regex", title: "Usar expressão regular na busca de texto", keywords: ["regex", "regular"],
                    category: .file, defaultShortcut: "cmd+opt+r",
                    action: .run { search.content.regex.toggle(); palette.refresh() }, unavailableReason: onScreen),
        ]
    }
}
