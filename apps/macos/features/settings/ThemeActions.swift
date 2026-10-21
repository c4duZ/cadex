import AppKit
import CommandPalette
import Icons
import Strings
import Themes

/// The theme commands (ADR 0005): choosing a theme in ⌘K, the mode, and the
/// user's theme files. The themes page's buttons run the same code.
@MainActor
public enum ThemeCommands {
    public static func all(store: SettingsStore, palette: CommandPaletteController) -> [Command] {
        func mode(_ value: String, _ title: String, _ keywords: [String]) -> Command {
            Command(id: "theme.mode-\(value)", title: title, keywords: ["theme", "tema", "mode", "modo"] + keywords, category: .view,
                    action: .run { store.update { $0.appearance.mode = value } },
                    unavailableReason: { store.settings.appearance.mode == value ? T("Already set", "Já está assim") : nil })
        }
        return [
            Command(id: "theme.choose", title: T("Choose Theme", "Escolher tema"),
                    keywords: ["theme", "tema", "cores", "colors", "palette", "aparência", "appearance"], category: .view,
                    action: .run { palette.open(ThemeSource(store: store)) }),
            Command(id: "theme.import", title: T("Import Theme…", "Importar tema…"),
                    keywords: ["theme", "tema", "itermcolors", "ghostty", "base16", "import"], category: .view,
                    action: .run { ThemeActions.importTheme(store: store) }),
            Command(id: "theme.open-folder", title: T("Open Themes Folder", "Abrir a pasta de temas"),
                    keywords: ["theme", "tema", "pasta", "folder", "finder"], category: .view,
                    action: .run { ThemeActions.openFolder() }),
            mode("system", T("Theme Follows the System", "Tema segue o sistema"), ["system", "sistema", "auto"]),
            mode("dark", T("Always Dark Theme", "Tema sempre escuro"), ["dark", "escuro"]),
            mode("light", T("Always Light Theme", "Tema sempre claro"), ["light", "claro"]),
        ]
    }
}

@MainActor
enum ThemeActions {
    /// Asks for a theme file, saves it in the themes folder and uses it.
    static func importTheme(store: SettingsStore) {
        let panel = NSOpenPanel()
        panel.message = T("A theme from iTerm2 (.itermcolors), Ghostty, base16 or base24 (.yaml), or Cadex (.json)",
                          "Um tema do iTerm2 (.itermcolors), do Ghostty, base16 ou base24 (.yaml), ou do Cadex (.json)")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let id = try ThemeLibrary.save(try ThemeImport.read(url))
            ThemeStore.shared.reload()
            store.update { $0.appearance.theme = id }
        } catch {
            let alert = NSAlert()
            alert.messageText = T("This file is not a theme Cadex can read", "Este arquivo não é um tema que o Cadex lê")
            alert.informativeText = "\(url.lastPathComponent): \(error)"
            alert.runModal()
        }
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: ThemeLibrary.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(ThemeLibrary.folder)
    }
}

/// ⌘K's list of themes (theme.choose): every theme, the one in use first.
@MainActor
final class ThemeSource: PaletteSource {
    private let store: SettingsStore
    private let families: [ThemeFamily]

    init(store: SettingsStore) {
        self.store = store
        families = ThemeLibrary.all().families
    }

    var placeholder: String { T("Choose a theme", "Escolher um tema") }
    var emptyText: String { T("No themes found", "Nenhum tema encontrado") }
    var icon: Icon { .palette }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let current = store.settings.appearance.theme
        let found = families.filter { family in
            query.isEmpty || [family.name, family.description].contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        let items = found.sorted { ($0.id == current ? 0 : 1) < ($1.id == current ? 0 : 1) }.map { family in
            PaletteItem(id: family.id, title: family.name,
                        detail: family.id == current ? T("in use", "em uso") : Self.versions(family), icon: .palette)
        }
        show(items, T("\(found.count) themes", "\(found.count) temas"))
    }

    static func versions(_ family: ThemeFamily) -> String {
        switch (family.dark != nil, family.light != nil) {
        case (true, true): T("dark and light", "escuro e claro")
        case (true, false): T("dark", "escuro")
        default: T("light", "claro")
        }
    }

    func choose(_ item: PaletteItem) {
        store.update { $0.appearance.theme = item.id }
    }

    func stop() {}
}
