import Foundation
import Icons

/// What the palette lists and runs. Commands are one source (⌘K); other
/// features add theirs (files on ⌘P, text on ⌘⇧F) without this feature
/// knowing them (docs/spec/command-palette.md, docs/spec/search.md).
@MainActor
public protocol PaletteSource: AnyObject {
    /// The field's placeholder ("Digite um comando").
    var placeholder: String { get }
    /// Shown when the list is empty for a query.
    var emptyText: String { get }
    /// The text changed. `show` may be called many times, as results
    /// arrive; the second value is a short status on the right of the field.
    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void)
    /// The user picked a row; the palette is already closed.
    func choose(_ item: PaletteItem)
    /// The same, with ⌥↩ or ⌘↩: files open beside or in a new tab.
    func choose(_ item: PaletteItem, as choice: PaletteChoice)
    /// The keys this list answers to, for the footer.
    var hints: [PaletteHint] { get }
    /// The field's icon while this list is on.
    var icon: Icon { get }
    /// The palette closed or switched source: stop work in progress.
    func stop()
}

extension PaletteSource {
    public func choose(_ item: PaletteItem, as choice: PaletteChoice) { choose(item) }
    public var hints: [PaletteHint] { [PaletteHint("↩", "escolher")] }
    public var icon: Icon { .magnifyingGlass }
}

/// ⌘K: the registered commands (PaletteModel), run by id.
@MainActor
final class CommandSource: PaletteSource {
    private let registry: CommandRegistry
    private let shortcut: (String) -> String?

    init(registry: CommandRegistry, shortcut: @escaping (String) -> String?) {
        self.registry = registry
        self.shortcut = shortcut
    }

    var placeholder: String { "Digite um comando" }
    var emptyText: String { "Nenhum comando encontrado" }

    var icon: Icon { .command }
    var hints: [PaletteHint] { [PaletteHint("↩", "executar")] }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        show(PaletteModel.items(for: query, registry: registry, shortcut: shortcut), nil)
    }

    func choose(_ item: PaletteItem) {
        registry.run(item.id)
    }

    func stop() {}
}
