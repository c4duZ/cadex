import AppKit
import Strings

/// The General page's interface rows (plan 15, phase D): zoom, density and
/// the interface's font, apart from the terminal's. They count when Cadex
/// opens, so a change offers to reopen.
@MainActor
enum InterfaceRows {
    static func make(_ store: SettingsStore, askRelaunch: @escaping (String?) -> Void) -> [NSView] {
        let a = store.settings.appearance
        let fonts = [(T("System", "Do sistema"), "")] + NSFontManager.shared.availableFontFamilies.map { ($0, $0) }
        func changed(_ body: @escaping (inout Settings) -> Void) {
            let before = store.settings
            store.update(body)
            if store.settings != before { askRelaunch(nil) }
        }
        return [
            SettingsPage.section(T("Interface", "Interface")),
            SettingsPage.row(T("Zoom", "Zoom"),
                             T("The size of everything around the terminal: tabs, the file tree, menus, ⌘K. The terminal keeps its own font size.",
                               "O tamanho de tudo em volta do terminal: abas, árvore de arquivos, menus, ⌘K. O terminal fica com o tamanho de fonte dele."),
                             control: SettingsPage.popup([80, 90, 100, 110, 125, 150].map { ("\($0)%", "\(Double($0) / 100)") },
                                                         selected: "\(a.uiZoom)") { value in
                                 changed { $0.appearance.uiZoom = Double(value) ?? 1 }
                             }),
            SettingsPage.row(T("Density", "Densidade"),
                             T("Compact fits more rows in the file tree, the lists and the menus.",
                               "Compacta cabe mais linhas na árvore de arquivos, nas listas e nos menus."),
                             control: SettingsPage.popup([(T("Normal", "Normal"), "normal"), (T("Compact", "Compacta"), "compact")],
                                                         selected: a.density) { value in changed { $0.appearance.density = value } }),
            SettingsPage.row(T("Interface font", "Fonte da interface"),
                             T("The font of the tabs, the tree and the lists. The terminal's is in Terminal.",
                               "A fonte das abas, da árvore e das listas. A do terminal fica em Terminal."),
                             control: SettingsPage.popup(fonts, selected: a.uiFont) { value in changed { $0.appearance.uiFont = value } }),
            SettingsPage.row(T("Interface text size", "Tamanho do texto da interface"), T("From 9 to 24 points; 13 is the usual.", "De 9 a 24 pontos; 13 é o comum."),
                             control: SettingsPage.number(a.uiFontSize, range: Settings.uiFontSizes, step: 1, format: "%.0f pt") { value in
                                 changed { $0.appearance.uiFontSize = value }
                             }),
        ]
    }
}
