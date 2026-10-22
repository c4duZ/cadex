import AppKit
import CommandPalette
import Menus
import Search
import Spaces
import Strings
import Tabs
import Themes

/// The palette in the app's colors and its prefixes (docs/spec/
/// command-palette.md): "/" files, "#" text, "@" the tabs and spaces.
extension WindowSession {
    /// The ways to open things, first in ⌘K and in the "+" menu next to
    /// the tabs (owner, 2026-10-19).
    /// The right click on a tab and on the space button (plan 15, phase D).
    static let tabActions = [
        PalettePin(id: "tab.rename", title: T("Rename Tab", "Renomear aba"), icon: .pencilSimple),
        PalettePin(id: "tab.set-color", title: T("Tab Color…", "Cor da aba…"), icon: .palette),
        PalettePin(id: "pane.close", title: T("Close Pane", "Fechar painel"), icon: .x),
    ]
    static let spaceActions = [
        PalettePin(id: "space.rename", title: T("Rename Space", "Renomear space"), icon: .pencilSimple),
        PalettePin(id: "space.set-color", title: T("Space Color…", "Cor do space…"), icon: .palette),
        PalettePin(id: "space.close", title: T("Close Space", "Fechar space"), icon: .x),
    ]

    static let openers = [
        PalettePin(id: "tab.new", title: T("Terminal in New Tab", "Terminal em nova aba"), icon: .plus),
        PalettePin(id: "pane.split-right", title: T("Terminal on the Right", "Terminal ao lado"), icon: .squareSplitHorizontal),
        PalettePin(id: "pane.split-down", title: T("Terminal Below", "Terminal abaixo"), icon: .squareSplitVertical),
        PalettePin(id: "search.files", title: T("File…", "Arquivo…"), icon: .file),
        PalettePin(id: "preview.open", title: T("Web Preview", "Preview web"), icon: .globe),
        PalettePin(id: "preview.open-in-tab", title: T("Web Preview in New Tab", "Preview web em nova aba"), icon: .globe),
        PalettePin(id: "window.new", title: T("New Window", "Nova janela"), icon: .appWindow),
    ]
    /// The "+" next to the tabs: what opens outside the tab you are in.
    /// What opens beside the pane moved to the pane header's "+", and the
    /// Git graph left both menus (the owner, 2026-10-22).
    static let newOpeners = openers.filter { !["pane.split-right", "pane.split-down", "preview.open"].contains($0.id) }
    /// The pane header's "+": what opens in this tab, then the pane itself.
    static let besideOpeners = [
        PalettePin(id: "pane.split-right", title: T("Terminal on the Right", "Terminal ao lado"), icon: .squareSplitHorizontal),
        PalettePin(id: "pane.split-down", title: T("Terminal Below", "Terminal abaixo"), icon: .squareSplitVertical),
        PalettePin(id: "preview.open", title: T("Web Preview on the Right", "Preview web ao lado"), icon: .globe),
    ]

    /// The pane header's menu, with Maximize or Restore as the pane is.
    func paneMenu() -> [MenuEntry] {
        guard let menu else { return [] }
        let zoomed = tabs?.activePaneZoomed == true
        let pane = [PalettePin(id: "pane.zoom", title: zoomed ? T("Restore Pane", "Restaurar painel") : T("Maximize Pane", "Maximizar painel"),
                               icon: zoomed ? .cornersIn : .cornersOut),
                    PalettePin(id: "pane.close", title: T("Close Pane", "Fechar painel"), icon: .x)]
        return MenuEntry.tidy(menu.popup(Self.besideOpeners) + [.separator] + menu.popup(pane))
    }

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
