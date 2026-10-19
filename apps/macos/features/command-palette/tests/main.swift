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
    ("an empty search lists the recent commands first, then by title", {
        let registry = sampleRegistry()
        registry.run("terminal.clear")
        let ids = PaletteModel.items(for: "", registry: registry) { _ in nil }.map(\.id)
        expect(ids == ["terminal.clear", "window.new", "tab.new"], "\(ids)")
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
    ("an unavailable command is listed with its reason", {
        let registry = CommandRegistry()
        registry.register(Command(id: "x.blocked", title: "Salvar", category: .app, action: .run {},
                                  unavailableReason: { "Sem editor ativo" }))
        expect(PaletteModel.items(for: "salvar", registry: registry) { _ in nil }.first?.unavailableReason == "Sem editor ativo")
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
