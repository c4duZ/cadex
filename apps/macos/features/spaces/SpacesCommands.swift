import AppKit
import CommandPalette
import Icons

/// The spaces' commands (ADR 0005). The title bar's label runs
/// space.switch; `folder` is where a new space's terminal starts.
public enum SpacesCommands {
    @MainActor
    public static func all(_ spaces: SpacesController, palette: CommandPaletteController,
                           folder: @escaping @MainActor () -> String) -> [Command] {
        func needsTwo() -> String? { spaces.spaces.count > 1 ? nil : "Só um space aberto" }
        return [
            Command(id: "space.switch", title: "Trocar de space", keywords: ["space", "grupo", "projeto"], category: .tabs,
                    defaultShortcut: "cmd+shift+s", action: .run { palette.open(SpaceSource(spaces: spaces)) }),
            Command(id: "space.new", title: "Novo space", keywords: ["space", "grupo", "criar"], category: .tabs,
                    defaultShortcut: "ctrl+cmd+n", action: .run { spaces.newSpace(folder: folder()) }),
            Command(id: "space.rename", title: "Renomear space", keywords: ["space", "nome"], category: .tabs,
                    action: .run { askName(spaces) }),
            Command(id: "space.close", title: "Fechar space", keywords: ["space", "fechar"], category: .tabs,
                    action: .run { spaces.closeActive() }, unavailableReason: needsTwo),
            Command(id: "space.next", title: "Próximo space", keywords: ["space", "alternar"], category: .tabs,
                    defaultShortcut: "ctrl+cmd+right", action: .run { spaces.selectNext(step: 1) }, unavailableReason: needsTwo),
            Command(id: "space.previous", title: "Space anterior", keywords: ["space", "alternar"], category: .tabs,
                    defaultShortcut: "ctrl+cmd+left", action: .run { spaces.selectNext(step: -1) }, unavailableReason: needsTwo),
        ]
    }

    /// "Renomear space": empty keeps the name it had.
    @MainActor
    static func askName(_ spaces: SpacesController) {
        guard let window = spaces.active?.hostWindow else { return }
        let index = spaces.activeIndex
        let alert = NSAlert()
        alert.messageText = "Renomear space"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = spaces.activeName
        alert.accessoryView = field
        alert.addButton(withTitle: "Renomear")
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1B}"
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                if response == .alertFirstButtonReturn { spaces.rename(at: index, to: field.stringValue) }
            }
        }
    }
}

extension SpacesCommands {
    /// The spaces as a palette list, for the app's "@" (with the tabs).
    @MainActor
    public static func source(_ spaces: SpacesController) -> PaletteSource { SpaceSource(spaces: spaces) }
}

/// The spaces in the palette; choosing one shows it.
@MainActor
final class SpaceSource: PaletteSource {
    private weak var spaces: SpacesController?

    init(spaces: SpacesController) {
        self.spaces = spaces
    }

    var placeholder: String { "Trocar para o space" }
    var emptyText: String { "Nenhum space" }
    var icon: Icon { .stack }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let spaces else { return show([], nil) }
        let items = spaces.spaces.enumerated()
            .filter { query.isEmpty || $0.element.name.localizedCaseInsensitiveContains(query) }
            .map { index, space in
                let tabs = space.tabs.count == 1 ? "1 aba" : "\(space.tabs.count) abas"
                return PaletteItem(id: String(index), title: space.name,
                                   detail: index == spaces.activeIndex ? "atual · \(tabs)" : "\(index + 1) · \(tabs)",
                                   icon: .stack)
            }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) {
        if let index = Int(item.id) { spaces?.select(index) }
    }

    func stop() {}
}
