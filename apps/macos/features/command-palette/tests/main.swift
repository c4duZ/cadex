import AppKit
import Checks
@testable import CommandPalette

// Tests of the command-palette feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

@MainActor
func sampleRegistry() -> CommandRegistry {
    let registry = CommandRegistry()
    for (id, title, keywords) in [("window.new", "Abrir nova janela", []), ("tab.new", "Nova aba", ["tab"]),
                                  ("terminal.clear", "Limpar o terminal", ["clear", "cls"])] {
        registry.register(Command(id: id, title: title, keywords: keywords, category: .app, action: .run {}))
    }
    return registry
}

let exitCode = await Checks.run([
    ("'na' ranks Nova aba above Abrir nova janela, with the letters in bold", {
        let items = PaletteModel.items(for: "na", registry: sampleRegistry()) { _ in nil }
        let ids = items.map(\.id)
        expect(ids.firstIndex(of: "tab.new")! < ids.firstIndex(of: "window.new")!, "\(ids)")
        let first = items[0]
        expect(first.bold.map { String(first.title[$0]) } == ["N", "a"], "\(first.bold)")
    }),
    ("an empty search lists the recent commands, then a section per area", {
        let registry = sampleRegistry()
        registry.run("terminal.clear")
        let items = PaletteModel.items(for: "", registry: registry) { _ in nil }
        expect(items.map(\.id) == ["terminal.clear", "tab.new", "window.new"], "\(items.map(\.id))")
        expect(items.map(\.section) == ["Recentes", "Abas", "Cadex"], "\(items.map(\.section))")
        expect(items[1].icon == .files && items[2].icon == .gearSix)
    }),
    ("titles go where the section changes; arrows skip them", {
        let items = [PaletteItem(id: "a", title: "a", section: "X"), PaletteItem(id: "b", title: "b", section: "X"),
                     PaletteItem(id: "c", title: "c", section: "Y")]
        let rows = PaletteRows.rows(for: items)
        expect(rows == [.header("X"), .item(0), .item(1), .header("Y"), .item(2)], "\(rows)")
        expect(PaletteRows.next(from: 2, by: 1, in: rows) == 4)
        expect(PaletteRows.next(from: 1, by: -1, in: rows) == nil)
        expect(KeycapsView.keys(of: "⇧⌘D") == ["⇧", "⌘", "D"] && KeycapsView.keys(of: "esc") == ["esc"])
    }),
    ("a prefix in ⌘K lists another source with the rest of the text", {
        final class Files: PaletteSource {
            var placeholder: String { "" }
            var emptyText: String { "" }
            func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {}
            func choose(_ item: PaletteItem) {}
            func stop() {}
        }
        let palette = CommandPaletteController(registry: sampleRegistry()) { _ in nil }
        let files = Files()
        palette.addPrefix("/", label: "arquivos", source: files)
        let commands = palette.commands
        let toFiles = palette.route("/ render", from: commands)
        expect(toFiles.0 === files && toFiles.1 == "render", "\(toFiles.1)")
        let back = palette.route("> nova", from: commands)
        expect(back.0 === commands && back.1 == "nova")
        // Only from ⌘K: in ⌘P, "/" is just text.
        expect(palette.route("/x", from: files).0 === files && palette.route("/x", from: files).1 == "/x")
    }),
    ("keywords find a command after the title matches", {
        let items = PaletteModel.items(for: "cls", registry: sampleRegistry()) { _ in nil }
        expect(items.map(\.id) == ["terminal.clear"], "\(items.map(\.id))")
        expect(PaletteModel.items(for: "zzz", registry: sampleRegistry()) { _ in nil }.isEmpty)
    }),
    ("accents and case do not matter, and bold lands on accented letters", {
        let registry = CommandRegistry()
        registry.register(Command(id: "pane.split-right", title: "Dividir à direita", category: .panes, action: .run {}))
        let items = PaletteModel.items(for: "A DIR", registry: registry) { _ in "⌘D" }
        expect(items.first?.id == "pane.split-right")
        expect(items.first?.shortcut == "⌘D")
        expect(items.first?.bold.contains { items[0].title[$0] == "à" } == true)
    }),
    ("a command that cannot run now is not listed, empty or searched", {
        let registry = CommandRegistry()
        registry.register(Command(id: "x.blocked", title: "Salvar", category: .app, action: .run {},
                                  unavailableReason: { "Sem editor ativo" }))
        expect(PaletteModel.items(for: "salvar", registry: registry) { _ in nil }.isEmpty)
        expect(PaletteModel.items(for: "", registry: registry) { _ in nil }.isEmpty)
    }),
    ("the pins come first under Abrir, with their names, and not again below", {
        let registry = sampleRegistry()
        registry.register(Command(id: "pane.split-right", title: "Dividir à direita", category: .panes, action: .run {}))
        registry.register(Command(id: "git.history", title: "Abrir o histórico", category: .app, action: .run {},
                                  unavailableReason: { "Sem repositório" }))
        registry.run("tab.new")
        let pins = [PalettePin(id: "pane.split-right", title: "Terminal ao lado", icon: .terminalWindow),
                    PalettePin(id: "git.history", title: "Grafo do git", icon: .gitBranch),
                    PalettePin(id: "tab.new", title: "Terminal em nova aba", icon: .plus)]
        let items = PaletteModel.items(for: "", registry: registry, pins: pins) { $0 == "pane.split-right" ? "⌘D" : nil }
        expect(items.prefix(2).map(\.title) == ["Terminal ao lado", "Terminal em nova aba"], "\(items.map(\.title))")
        expect(items[0].section == "Abrir" && items[0].shortcut == "⌘D")
        expect(items.filter { $0.id == "tab.new" }.count == 1 && !items.contains { $0.section == "Recentes" })
    }),
    ("a registered command runs by id and goes to the recent list", {
        let registry = CommandRegistry()
        var ran = 0
        registry.register(Command(id: "test.run", title: "Rodar", category: .app, action: .run { ran += 1 }))
        expect(registry.run("test.run"))
        expect(ran == 1)
        expect(registry.recent == ["test.run"])
        expect(!registry.run("test.missing"))
    }),
    ("an unavailable command does not run and says why", {
        let registry = CommandRegistry()
        var ran = false
        registry.register(Command(id: "test.blocked", title: "Bloqueado", category: .app,
                                  action: .run { ran = true }, unavailableReason: { "Sem editor ativo" }))
        expect(!registry.run("test.blocked"))
        expect(!ran)
        expect(registry.unavailableReason("test.blocked") == "Sem editor ativo")
        expect(registry.unavailableReason("test.missing") == "Comando desconhecido")
    }),
    ("every standard command has a title and a unique id", {
        let registry = CommandRegistry()
        registry.register(StandardCommands.all)
        expect(registry.commands.allSatisfy { !$0.title.isEmpty })
        expect(Set(registry.commands.map(\.id)).count == registry.commands.count)
    }),
    ("the menu has one submenu per category in use and items run by id", {
        let registry = CommandRegistry()
        registry.register(StandardCommands.all)
        let menu = CommandMenu(registry: registry) { _ in nil }.build()
        expect(menu.items.map(\.title) == ["Cadex", "Editar"], "\(menu.items.map(\.title))")
        let copy = menu.items[1].submenu?.items.first { ($0.representedObject as? String) == "edit.copy" }
        expect(copy?.title == "Copiar")
    }),
])
exit(exitCode)
