import AppKit
import CommandPalette
import Search
import Spaces
import Tabs
import Themes

/// The palette in the app's colors and its prefixes (docs/spec/
/// command-palette.md): "/" files, "#" text, "@" the tabs and spaces.
extension AppDelegate {
    func connectPalette(_ palette: CommandPaletteController) {
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
