import AppKit
import UILooks
import Strings
import Themes
import UniformTypeIdentifiers

/// The "Themes" page: the mode, a search with a dark/light filter, the
/// grid of theme cards (ThemeGrid), importing, and the window's looks.
/// Picking a card changes the theme at once (docs/spec/themes.md).
@MainActor
final class ThemesPage {
    enum Filter: Int { case all, dark, light }
    private let store: SettingsStore
    private let grid: ThemeGrid
    private var query = ""
    private var filter = Filter.all
    private var library: [ThemeFamily] = []

    init(store: SettingsStore) {
        self.store = store
        var pick: (ThemeFamily) -> Void = { _ in }
        grid = ThemeGrid { pick($0) }
        pick = { [weak self] family in self?.pick(family) }
    }

    func makeView() -> NSView {
        let appearance = store.settings.appearance
        let mode = SettingsPage.popup([(T("Follow the system", "Seguir o sistema"), "system"), (T("Dark", "Escuro"), "dark"), (T("Light", "Claro"), "light")],
                                      selected: appearance.mode) { [store] value in store.update { $0.appearance.mode = value } }
        let (families, problems) = ThemeLibrary.all()
        library = families
        let (dark, light) = ThemeLooksRows.inUse(appearance)
        grid.selected = [dark, light]
        applyFilter()
        var rows: [NSView] = [
            SettingsPage.row(T("Mode", "Modo"),
                             T("Which version of the theme shows: the one for the system's light or dark mode, or always the same.",
                               "Qual versão do tema aparece: a do modo claro ou escuro do sistema, ou sempre a mesma."),
                             control: mode),
            ThemeLooksRows.pair(store),
            ThemeLooksRows.accent(store),
            filesRow(),
            SettingsPage.section(T("Theme", "Tema")),
            toolbar(count: families.count),
        ]
        if !problems.isEmpty {
            rows.append(SettingsPage.note(T("Themes in your folder that could not be read:\n", "Temas da sua pasta que não deu para ler:\n")
                                          + problems.joined(separator: "\n")))
        }
        rows.append(grid)
        rows += [SettingsPage.section(T("Reading", "Leitura"))] + ThemeLooksRows.contrast(store)
        rows += looksRows()
        return SettingsPage.make(title: T("Themes", "Temas"), subtitle: T("The theme, the window's frame and a background image.", "O tema, a moldura da janela e uma imagem de fundo."), rows: rows)
    }

    /// Importing a theme and the folder of the user's themes.
    private func filesRow() -> NSView {
        let importButton = SettingsPage.button(T("Import…", "Importar…")) { [store] in ThemeActions.importTheme(store: store) }
        let folder = SettingsPage.button(T("Open Folder", "Abrir pasta")) { ThemeActions.openFolder() }
        let buttons = NSStackView(views: [folder, importButton])
        buttons.spacing = 6
        return SettingsPage.row(T("Your themes", "Seus temas"),
                                T("Import a theme from iTerm2 (.itermcolors), Ghostty, or base16 and base24 (.yaml). Cadex theme files (.json) in the folder show up first.",
                                  "Importe um tema do iTerm2 (.itermcolors), do Ghostty ou base16 e base24 (.yaml). Arquivos de tema do Cadex (.json) na pasta aparecem primeiro."),
                                control: buttons)
    }

    /// The search and the dark/light filter.
    private func toolbar(count: Int) -> NSView {
        let search = NSSearchField()
        search.stringValue = query
        search.placeholderString = T("Search \(count) themes", "Buscar entre \(count) temas")
        search.target = ActionBox.keep(search) { [weak self, weak search] in
            self?.query = search?.stringValue ?? ""
            self?.applyFilter()
        }
        search.action = #selector(ActionBox.fire)
        let kinds = SettingsPage.popup([(T("All", "Todos"), "all"), (T("Dark", "Escuros"), "dark"), (T("Light", "Claros"), "light")],
                                       selected: ["all", "dark", "light"][filter.rawValue]) { [weak self] value in
            self?.filter = ["dark": .dark, "light": .light][value] ?? .all
            self?.applyFilter()
        }
        // The search in the frame's box (plan 31 D), the filter beside it.
        let bar = NSStackView(views: [FrameField.field(search), kinds])
        bar.spacing = UILooks.pt(DesignTokens.NewTask.Option.gap)
        return bar
    }

    private func applyFilter() {
        grid.families = library.filter { family in
            switch filter {
            case .all: break
            case .dark: if family.dark == nil { return false }
            case .light: if family.light == nil { return false }
            }
            return query.isEmpty || [family.name, family.description, family.id].contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    /// Vibrancy and the background image: off by default, they cost
    /// compositing on every frame (docs/spec/themes.md).
    private func looksRows() -> [NSView] {
        let a = store.settings.appearance
        let image = a.backgroundImage.map { ($0 as NSString).lastPathComponent } ?? T("none", "nenhuma")
        let pick = SettingsPage.button(T("Choose image…", "Escolher imagem…")) { [weak self] in self?.pickImage() }
        let remove = SettingsPage.button(T("Remove", "Remover")) { [store] in
            if let old = store.settings.appearance.backgroundImage { try? FileManager.default.removeItem(atPath: old) }
            store.update { $0.appearance.backgroundImage = nil }
        }
        remove.isEnabled = a.backgroundImage != nil
        let buttons = NSStackView(views: [remove, pick])
        buttons.spacing = 6
        return [
            SettingsPage.section(T("Window", "Janela")),
            SettingsPage.row(T("Window opacity", "Opacidade da janela"),
                             T("Below 100% the whole window turns into glass: your desktop shows through it blurred, with its shapes, under the theme's color at this strength. ⌘K, the menus, the cards and Settings are the same glass. Lines, text and cards stay as they are.",
                               "Abaixo de 100% a janela inteira vira vidro: o seu fundo de tela aparece atrás desfocado, com as formas, sob a cor do tema nessa força. O ⌘K, os menus, os cartões e as configurações são o mesmo vidro. Linhas, texto e cartões continuam iguais."),
                             control: SettingsPage.slider(a.windowOpacity, range: Settings.windowOpacityRange, format: "%.0f%%", shown: { $0 * 100 }) { [store] value in
                                 store.update { $0.appearance.windowOpacity = (value * 20).rounded() / 20 }
                             }),
            SettingsPage.row(T("Full screen", "Tela cheia"),
                             T("The system's gives the window a screen of its own, with the window's buttons at the top; a translucent window shows your wallpaper behind the glass. Cadex's covers the screen over your desktop, with the menu bar and the Dock at the edges, without the window's buttons.",
                               "A do sistema dá à janela uma tela só dela, com os botões da janela no topo; a janela translúcida mostra o seu fundo de tela atrás do vidro. A do Cadex cobre a tela sobre a sua mesa, com a barra de menus e o Dock nas bordas, sem os botões da janela."),
                             // "auto" and "system" are both the system's since 2026-11-27; one row for them.
                             control: SettingsPage.popup([(T("System", "Do sistema"), "auto"), ("Cadex", "cadex")],
                                                         selected: a.fullScreen == "cadex" ? "cadex" : "auto") { [store] value in
                                 store.update { $0.appearance.fullScreen = value }
                             }),
            SettingsPage.row(T("Pane borders", "Bordas dos painéis"),
                             T("Glow draws each pane's border in the tab's or project's color, with a soft light around it.",
                               "Com brilho, a borda de cada painel fica na cor da aba ou do projeto, com uma luz suave em volta."),
                             control: SettingsPage.popup([(T("Line", "Linha"), "line"), (T("Glow", "Brilho"), "glow")],
                                                         selected: a.paneBorder) { [store] value in
                                 store.update { $0.appearance.paneBorder = value }
                             }),
            SettingsPage.row(T("Vibrancy", "Vibrância"),
                             T("The window's frame turns frosted over what is behind it. A translucent window is always frosted.",
                               "A moldura da janela fica fosca sobre o que está atrás dela. A janela translúcida é sempre fosca."),
                             control: SettingsPage.toggle(a.vibrancy) { [store] on in store.update { $0.appearance.vibrancy = on } }),
            SettingsPage.row(T("Background image", "Imagem de fundo"),
                             T("Shown behind the terminal; Cadex keeps a copy. Now: \(image).", "Aparece atrás do terminal; o Cadex guarda uma cópia. Agora: \(image)."),
                             control: buttons),
            SettingsPage.row(T("Image opacity", "Opacidade da imagem"), nil,
                             control: SettingsPage.slider(a.backgroundOpacity, range: 0...1, format: "%.0f%%", shown: { $0 * 100 }) { [store] value in
                                 store.update { $0.appearance.backgroundOpacity = value }
                             }),
            SettingsPage.row(T("Image blur", "Desfoque da imagem"), nil,
                             control: SettingsPage.slider(a.backgroundBlur, range: 0...50, format: "%.0f") { [store] value in
                                 store.update { $0.appearance.backgroundBlur = value }
                             }),
        ]
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let copy = try? BackgroundImages.keepCopy(of: url) else { NSSound.beep(); return }
        if let old = store.settings.appearance.backgroundImage { try? FileManager.default.removeItem(atPath: old) }
        store.update { $0.appearance.backgroundImage = copy }
    }

    /// With the Dark or Light filter, the theme for that mode only;
    /// otherwise one theme for both (plan 15, phase B).
    private func pick(_ family: ThemeFamily) {
        store.update {
            switch filter {
            case .dark: $0.appearance.darkTheme = family.id
            case .light: $0.appearance.lightTheme = family.id
            case .all: ($0.appearance.theme, $0.appearance.darkTheme, $0.appearance.lightTheme) = (family.id, "", "")
            }
        }
        let (dark, light) = ThemeLooksRows.inUse(store.settings.appearance)
        grid.selected = [dark, light]
    }
}
