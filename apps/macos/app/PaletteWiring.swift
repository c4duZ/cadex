import AppKit
import CommandPalette
import Search
import Spaces
import Tabs
import Themes

/// The palette in the app's colors and its prefixes (docs/spec/
/// command-palette.md): "/" files, "#" text, "@" the tabs and spaces.
extension WindowSession {
    /// The ways to open things, first in ⌘K and in the "+" menu next to
    /// the tabs, as in Terax's "+" (owner, 2026-10-19).
    static let openers = [
        PalettePin(id: "tab.new", title: "Terminal em nova aba", icon: .plus),
        PalettePin(id: "pane.split-right", title: "Terminal ao lado", icon: .squareSplitHorizontal),
        PalettePin(id: "pane.split-down", title: "Terminal abaixo", icon: .squareSplitVertical),
        PalettePin(id: "search.files", title: "Arquivo…", icon: .file),
        PalettePin(id: "preview.open", title: "Preview web", icon: .globe),
        PalettePin(id: "preview.open-in-tab", title: "Preview web em nova aba", icon: .globe),
        PalettePin(id: "git.history", title: "Grafo do git", icon: .gitBranch),
        PalettePin(id: "git.history-in-tab", title: "Grafo do git em nova aba", icon: .gitBranch),
        PalettePin(id: "window.new", title: "Nova janela", icon: .appWindow),
    ]

    /// The coffee's menu in the title bar: the power commands that change
    /// something now (docs/spec/power.md).
    static let powerPins = [
        PalettePin(id: "power.keep-awake", title: "Manter acordado", icon: .coffee),
        PalettePin(id: "power.keep-awake-while-running", title: "Manter acordado com programa rodando", icon: .terminalWindow),
        PalettePin(id: "power.allow-sleep", title: "Deixar o computador dormir", icon: .x),
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
            palette.addPrefix("/", label: "arquivos", source: search.files)
            palette.addPrefix("#", label: "texto", source: search.content)
        }
        var places: [(String, PaletteSource)] = [("Abas", TabCommands.source { [weak self] in self?.tabs })]
        if let spaces { places.append(("Spaces", SpacesCommands.source(spaces))) }
        palette.addPrefix("@", label: "abas e spaces", source: MergedSource(
            placeholder: "Ir para a aba ou o space", emptyText: "Nenhuma aba ou space", icon: .stack, parts: places))
    }
}
