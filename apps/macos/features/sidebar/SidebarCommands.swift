import CommandPalette
import Icons
import Strings

/// The sidebar's commands (ADR 0005): the customize panel, and showing or
/// hiding any page from ⌘K, with the list of pages marked shown or hidden.
@MainActor
public enum SidebarCommands {
    public static func all(_ sidebar: @escaping @MainActor () -> SidebarView?, palette: CommandPaletteController) -> [Command] {
        [
            Command(id: "sidebar.customize", title: T("Customize Sidebar", "Personalizar o painel lateral"),
                    keywords: ["sidebar", "icons", "pages", "ícones", "páginas", "painel"], category: .view,
                    action: .run { sidebar()?.customize() }),
            Command(id: "sidebar.toggle-page", title: T("Show or Hide a Sidebar Page", "Mostrar ou esconder uma página do painel lateral"),
                    keywords: ["sidebar", "icon", "page", "ícone", "página", "painel"], category: .view,
                    action: .run {
                        guard let sidebar = sidebar() else { return }
                        palette.open(SidebarPageSource(sidebar: sidebar))
                    }),
        ]
    }
}

/// ⌘K's list of the sidebar's pages, each marked shown or hidden; choosing
/// one flips it.
@MainActor
final class SidebarPageSource: PaletteSource {
    private weak var sidebar: SidebarView?

    init(sidebar: SidebarView) { self.sidebar = sidebar }

    var placeholder: String { T("Choose a page to show or hide", "Escolher uma página para mostrar ou esconder") }
    var emptyText: String { T("No such page", "Nenhuma página assim") }
    var icon: Icon { .slidersHorizontal }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let sidebar else { return show([], nil) }
        let items = sidebar.catalogItems
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.contains(query.lowercased()) }
            .map { item in
                PaletteItem(id: item.id, title: item.title,
                            detail: sidebar.items.contains(item.id) ? T("shown", "aparece") : T("hidden", "escondida"),
                            icon: item.icon)
            }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) { sidebar?.toggle(item.id) }

    func stop() {}
}
