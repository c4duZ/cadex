import AppKit
import Checks
@testable import CommandPalette

// Tests of the command-palette feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
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
