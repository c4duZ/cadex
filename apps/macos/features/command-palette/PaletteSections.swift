import Icons

/// The sections of ⌘K with an empty field (docs/spec/command-palette.md):
/// each command goes to the area of its id prefix, in this order. Only
/// labels: the palette still knows no other feature.
enum CommandSections {
    struct Section {
        let title: String
        let icon: Icon
        let prefixes: [String]
    }

    static let recent = Section(title: "Recentes", icon: .arrowCounterClockwise, prefixes: [])

    static let all: [Section] = [
        Section(title: "Abas", icon: .files, prefixes: ["tab"]),
        Section(title: "Painéis", icon: .sidebar, prefixes: ["pane"]),
        Section(title: "Arquivos", icon: .folder, prefixes: ["explorer", "workspace"]),
        Section(title: "Busca", icon: .magnifyingGlass, prefixes: ["search"]),
        Section(title: "Editor", icon: .code, prefixes: ["editor", "markdown"]),
        Section(title: "Terminal", icon: .terminalWindow, prefixes: ["terminal"]),
        Section(title: "Git", icon: .gitBranch, prefixes: ["git", "history", "diff"]),
        Section(title: "Web e mídia", icon: .globe, prefixes: ["preview", "media"]),
        Section(title: "Spaces", icon: .stack, prefixes: ["space"]),
        Section(title: "Editar", icon: .keyboard, prefixes: ["edit"]),
    ]

    /// Anything else: the app, settings, the palette, windows.
    static let app = Section(title: "Cadex", icon: .gearSix, prefixes: [])

    static func section(of id: String) -> Section {
        let prefix = String(id.prefix { $0 != "." })
        return all.first { $0.prefixes.contains(prefix) } ?? app
    }

    static func order(of section: Section) -> Int {
        all.firstIndex { $0.title == section.title } ?? all.count
    }
}

/// A command shown first in ⌘K, under "Abrir", with its own name and
/// icon: the ways to open things beside the terminal (owner, 2026-10-19:
/// "os primeiros deveriam ser o atalho pra abrir as coisas na direita").
/// The app's "+" menu lists the same ones.
public struct PalettePin: Sendable {
    public let id: String
    public let title: String
    public let icon: Icon

    public init(id: String, title: String, icon: Icon) {
        self.id = id
        self.title = title
        self.icon = icon
    }
}

/// Several lists in one, each under its own title: `@` shows the tabs and
/// the spaces together. Ids get the part's index, so choosing goes back to
/// the list that made the row.
@MainActor
public final class MergedSource: PaletteSource {
    private let parts: [(title: String, source: PaletteSource)]
    public let placeholder: String
    public let emptyText: String
    public let icon: Icon

    public init(placeholder: String, emptyText: String, icon: Icon, parts: [(String, PaletteSource)]) {
        self.placeholder = placeholder
        self.emptyText = emptyText
        self.icon = icon
        self.parts = parts.map { (title: $0.0, source: $0.1) }
    }

    public func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        var results = Array(repeating: [PaletteItem](), count: parts.count)
        for (index, part) in parts.enumerated() {
            part.source.search(query) { items, _ in
                results[index] = items.map { item in
                    PaletteItem(id: "\(index):\(item.id)", title: item.title, bold: item.bold, detail: item.detail,
                                shortcut: item.shortcut, unavailableReason: item.unavailableReason,
                                section: part.title, icon: item.icon ?? part.source.icon, image: item.image)
                }
                show(results.flatMap { $0 }, nil)
            }
        }
    }

    public func choose(_ item: PaletteItem) {
        guard let (part, inner) = split(item) else { return }
        part.choose(inner)
    }

    public func stop() { parts.forEach { $0.source.stop() } }

    private func split(_ item: PaletteItem) -> (PaletteSource, PaletteItem)? {
        let pieces = item.id.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2, let index = Int(pieces[0]), index < parts.count else { return nil }
        return (parts[index].source, PaletteItem(id: pieces[1], title: item.title))
    }
}
