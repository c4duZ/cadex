import Foundation
import Icons
import Strings

/// What the palette lists and runs. Commands are one source (⌘K); other
/// features add theirs (files on ⌘P, text on ⌘⇧F) without this feature
/// knowing them (docs/spec/command-palette.md, docs/spec/search.md).
@MainActor
public protocol PaletteSource: AnyObject {
    /// The field's placeholder ("Digite um comando").
    var placeholder: String { get }
    /// Shown when the list is empty for a query.
    var emptyText: String { get }
    /// What the list says before anything is typed and nothing shows (⌘P with no recent file);
    /// nil: `emptyText`. "No files found" before typing read as broken (the owner, 2026-11-18).
    var hint: String? { get }
    var idleText: String? { get }
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
    var width: CGFloat? { get }
    var showsFooter: Bool { get }
}

extension PaletteSource {
    public var idleText: String? { nil }
    /// A dim sentence under the field saying what choosing does (the account switch's, the proposal).
    public var hint: String? { nil }
    public func choose(_ item: PaletteItem, as choice: PaletteChoice) { choose(item) }
    public var hints: [PaletteHint] { [PaletteHint("↩", T("choose", "escolher"))] }
    public var icon: Icon { .magnifyingGlass }
    /// Its own width (⌘J's 600 pt, components.sheet.switcherWidth); nil: the palette's.
    public var width: CGFloat? { nil }
    /// The keys' footer under the list; ⌘J has none (the mockup).
    public var showsFooter: Bool { true }
}

/// ⌘K: the registered commands (PaletteModel), run by id.
@MainActor
final class CommandSource: PaletteSource {
    private let registry: CommandRegistry
    private let shortcut: (String) -> String?
    /// Shown first, under "Abrir" (the app sets them).
    var pins: [PalettePin] = []
    /// "Now", above everything with the field empty (the proposal): what waits for you and what fits
    /// the moment; ids starting "now:" run through `runNow`.
    var now: @MainActor () -> [PaletteItem] = { [] }
    var runNow: @MainActor (String) -> Void = { _ in }

    init(registry: CommandRegistry, shortcut: @escaping (String) -> String?) {
        self.registry = registry
        self.shortcut = shortcut
    }

    var placeholder: String { T("Search commands, files, tabs…", "Buscar comando, arquivo, aba…") }
    var emptyText: String { T("No commands found", "Nenhum comando encontrado") }

    var icon: Icon { .magnifyingGlass }
    var hints: [PaletteHint] { [PaletteHint("↩", T("run", "executar"))] }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let listed = PaletteModel.items(for: query, registry: registry, pins: pins, shortcut: shortcut)
        show(query.isEmpty ? now().map { var item = $0; item.section = T("Now", "Agora"); return item } + listed : listed, nil)
    }

    func choose(_ item: PaletteItem) {
        if item.id.hasPrefix("now:") { return runNow(item.id) }
        registry.run(item.id)
    }

    func stop() {}
}
