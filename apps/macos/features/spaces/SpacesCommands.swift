import AppKit
import Strings
import CommandPalette
import Icons

/// The spaces' commands (ADR 0005). The title bar's label runs
/// space.switch; `folder` is where a new space's terminal starts.
public enum SpacesCommands {
    @MainActor
    public static func all(_ spaces: SpacesController, palette: CommandPaletteController,
                           folder: @escaping @MainActor () -> String) -> [Command] {
        func needsTwo() -> String? { spaces.spaces.count > 1 ? nil : T("Only one space open", "Só um space aberto") }
        return [
            Command(id: "space.switch", title: T("Switch Space", "Trocar de space"), keywords: ["space", "grupo", "projeto", "switch", "group", "project"], category: .tabs,
                    defaultShortcut: "cmd+shift+s", action: .run { palette.open(SpaceSource(spaces: spaces)) }),
            Command(id: "space.new", title: T("New Space", "Novo space"), keywords: ["space", "grupo", "criar", "new"], category: .tabs,
                    defaultShortcut: "ctrl+cmd+n", action: .run { spaces.newSpace(folder: folder()) }),
            Command(id: "space.rename", title: T("Rename Space", "Renomear space"), keywords: ["space", "nome", "rename"], category: .tabs,
                    action: .run { askName(spaces) }),
            Command(id: "space.close", title: T("Close Space", "Fechar space"), keywords: ["space", "fechar", "close"], category: .tabs,
                    action: .run { spaces.closeActive() }, unavailableReason: needsTwo),
            Command(id: "space.next", title: T("Next Space", "Próximo space"), keywords: ["space", "alternar", "next"], category: .tabs,
                    defaultShortcut: "ctrl+cmd+right", action: .run { spaces.selectNext(step: 1) }, unavailableReason: needsTwo),
            Command(id: "space.previous", title: T("Previous Space", "Space anterior"), keywords: ["space", "alternar", "previous"], category: .tabs,
                    defaultShortcut: "ctrl+cmd+left", action: .run { spaces.selectNext(step: -1) }, unavailableReason: needsTwo),
        ]
    }

    /// "Renomear space": empty keeps the name it had.
    @MainActor
    static func askName(_ spaces: SpacesController) {
        guard let window = spaces.active?.hostWindow else { return }
        let index = spaces.activeIndex
        let alert = NSAlert()
        alert.messageText = T("Rename space", "Renomear space")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = spaces.activeName
        alert.accessoryView = field
        alert.addButton(withTitle: T("Rename", "Renomear"))
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1B}"
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

    var placeholder: String { T("Switch to space", "Trocar para o space") }
    var emptyText: String { T("No spaces", "Nenhum space") }
    var icon: Icon { .stack }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let spaces else { return show([], nil) }
        let items = spaces.spaces.enumerated()
            .filter { query.isEmpty || $0.element.name.localizedCaseInsensitiveContains(query) }
            .map { index, space in
                let tabs = space.tabs.count == 1 ? T("1 tab", "1 aba") : T("\(space.tabs.count) tabs", "\(space.tabs.count) abas")
                return PaletteItem(id: String(index), title: space.name,
                                   detail: index == spaces.activeIndex ? T("current · \(tabs)", "atual · \(tabs)") : "\(index + 1) · \(tabs)",
                                   icon: .stack)
            }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) {
        if let index = Int(item.id) { spaces?.select(index) }
    }

    func stop() {}
}
