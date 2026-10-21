import AppKit
import CommandPalette
import Icons
import Strings

/// The status bar's commands (ADR 0005): the Customize window, showing or
/// hiding any item from ⌘K (the list marks each one), and Activity
/// Monitor, which the RAM, CPU and Cadex memory items open.
@MainActor
public enum StatusBarCommands {
    public static func all(_ bar: @escaping @MainActor () -> StatusBarView?, palette: CommandPaletteController) -> [Command] {
        [
            Command(id: "statusBar.customize", title: T("Customize Status Bar", "Personalizar a barra de status"),
                    keywords: ["status bar", "items", "ram", "cpu", "barra de status", "itens"], category: .view,
                    action: .run { bar()?.customize() }),
            Command(id: "statusBar.toggle-item", title: T("Show or Hide a Status Bar Item", "Mostrar ou esconder um item da barra de status"),
                    keywords: ["status bar", "item", "ram", "cpu", "branch", "barra de status"], category: .view,
                    action: .run {
                        guard let bar = bar() else { return }
                        palette.open(StatusItemSource(bar: bar))
                    }),
            Command(id: "statusBar.activity-monitor", title: T("Open Activity Monitor", "Abrir o Monitor de Atividade"),
                    keywords: ["activity monitor", "memory", "cpu", "monitor de atividade", "memória"], category: .view,
                    action: .run {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }),
        ]
    }
}

/// ⌘K's list of the status bar's items, each marked shown or hidden;
/// choosing one flips it.
@MainActor
final class StatusItemSource: PaletteSource {
    private weak var bar: StatusBarView?

    init(bar: StatusBarView) { self.bar = bar }

    var placeholder: String { T("Choose an item to show or hide", "Escolher um item para mostrar ou esconder") }
    var emptyText: String { T("No such item", "Nenhum item assim") }
    var icon: Icon { .slidersHorizontal }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let bar else { return show([], nil) }
        let shown = Set(bar.left + bar.right)
        let items = bar.catalogItems
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.id.lowercased().contains(query.lowercased()) }
            .map { PaletteItem(id: $0.id, title: $0.title, detail: shown.contains($0.id) ? T("shown", "aparece") : T("hidden", "escondido"), icon: $0.icon) }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) { bar?.toggle(item.id) }

    func stop() {}
}
