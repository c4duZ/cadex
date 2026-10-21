import AppKit
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
        grid.selected = [appearance.theme]
        applyFilter()
        var rows: [NSView] = [
            SettingsPage.row(T("Mode", "Modo"),
                             T("Which version of the theme shows: the one for the system's light or dark mode, or always the same.",
                               "Qual versão do tema aparece: a do modo claro ou escuro do sistema, ou sempre a mesma."),
                             control: mode),
            filesRow(),
            SettingsPage.section(T("Theme", "Tema")),
            toolbar(count: families.count),
        ]
        if !problems.isEmpty {
            rows.append(SettingsPage.note(T("Themes in your folder that could not be read:\n", "Temas da sua pasta que não deu para ler:\n")
                                          + problems.joined(separator: "\n")))
        }
        rows.append(grid)
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
        let bar = NSStackView(views: [search, kinds])
        bar.spacing = 8
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
            SettingsPage.row(T("Vibrancy", "Vibrância"),
                             T("The window's frame turns frosted over what is behind it. The panels stay solid.",
                               "A moldura da janela fica fosca sobre o que está atrás dela. Os painéis continuam sólidos."),
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

    private func pick(_ family: ThemeFamily) {
        store.update { $0.appearance.theme = family.id }
        grid.selected = [family.id]
    }
}
