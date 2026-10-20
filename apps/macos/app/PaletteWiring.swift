import AppKit
import CommandPalette
import Search
import Spaces
import Strings
import Tabs
import Themes

/// The palette in the app's colors and its prefixes (docs/spec/
/// command-palette.md): "/" files, "#" text, "@" the tabs and spaces.
extension WindowSession {
    /// The ways to open things, first in ⌘K and in the "+" menu next to
    /// the tabs, as in Terax's "+" (owner, 2026-10-19).
    static let openers = [
        PalettePin(id: "tab.new", title: T("Terminal in New Tab", "Terminal em nova aba"), icon: .plus),
        PalettePin(id: "pane.split-right", title: T("Terminal on the Right", "Terminal ao lado"), icon: .squareSplitHorizontal),
        PalettePin(id: "pane.split-down", title: T("Terminal Below", "Terminal abaixo"), icon: .squareSplitVertical),
        PalettePin(id: "search.files", title: T("File…", "Arquivo…"), icon: .file),
        PalettePin(id: "preview.open", title: T("Web Preview", "Preview web"), icon: .globe),
        PalettePin(id: "preview.open-in-tab", title: T("Web Preview in New Tab", "Preview web em nova aba"), icon: .globe),
        PalettePin(id: "git.history", title: T("Git Graph", "Grafo do git"), icon: .gitBranch),
        PalettePin(id: "git.history-in-tab", title: T("Git Graph in New Tab", "Grafo do git em nova aba"), icon: .gitBranch),
        PalettePin(id: "window.new", title: T("New Window", "Nova janela"), icon: .appWindow),
    ]

    func connectPalette(_ palette: CommandPaletteController) {
        palette.pins = Self.openers
        ThemeStore.shared.observe { [weak palette] theme in
            let ui = theme.interface
            palette?.style = PaletteStyle(
                background: ui.panel.nsColor, border: ui.panelBorder.nsColor, text: ui.text.nsColor,
                secondaryText: ui.secondaryText.nsColor, selection: ui.tabActive.nsColor, accent: ui.accent.nsColor,
                keycap: ui.field.nsColor)
        }
        if let search {
            palette.addPrefix("/", label: T("files", "arquivos"), source: search.files)
            palette.addPrefix("#", label: T("text", "texto"), source: search.content)
        }
        var places: [(String, PaletteSource)] = [(T("Tabs", "Abas"), TabCommands.source { [weak self] in self?.tabs })]
        if let spaces { places.append(("Spaces", SpacesCommands.source(spaces))) }
        palette.addPrefix("@", label: T("tabs and spaces", "abas e spaces"), source: MergedSource(
            placeholder: T("Go to a tab or space", "Ir para a aba ou o space"),
            emptyText: T("No tabs or spaces", "Nenhuma aba ou space"), icon: .stack, parts: places))
    }
}
