import AppKit
import CommandPalette
import Icons
import Strings

/// The window's tabs in the palette ("@", with the spaces): each by its
/// title and what its focused pane shows; choosing one selects it
/// (docs/spec/command-palette.md).
@MainActor
final class TabSource: PaletteSource {
    private let tabs: @MainActor () -> TabsController?

    init(tabs: @escaping @MainActor () -> TabsController?) {
        self.tabs = tabs
    }

    var placeholder: String { T("Go to tab", "Ir para a aba") }
    var emptyText: String { T("No tabs", "Nenhuma aba") }
    var icon: Icon { .files }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let controller = tabs() else { return show([], nil) }
        let items = controller.list.order.enumerated().compactMap { position, id -> PaletteItem? in
            guard let tab = controller.tabs[id] else { return nil }
            let title = tab.title(home: controller.home)
            let found = query.isEmpty ? nil : title.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
            guard query.isEmpty || found != nil else { return nil }
            let panes = tab.panes.count == 1 ? "" : T(" · \(tab.panes.count) panes", " · \(tab.panes.count) painéis")
            let where_ = id == controller.list.active ? T("current", "atual") : "⌘\(position + 1)"
            let identity = tab.focused.document?.identity
            return PaletteItem(id: String(id), title: title, bold: found.map { [$0] } ?? [], detail: where_ + panes,
                               icon: identity.map { TabsController.tabIcon(for: $0).0 } ?? .terminalWindow,
                               image: identity.flatMap(TabsController.tabImage))
        }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) {
        if let id = Int(item.id) { tabs()?.select(id) }
    }

    func stop() {}
}

extension TabCommands {
    /// The tabs of the shown space as a palette list.
    @MainActor
    public static func source(_ tabs: @escaping @MainActor () -> TabsController?) -> PaletteSource {
        TabSource(tabs: tabs)
    }
}
