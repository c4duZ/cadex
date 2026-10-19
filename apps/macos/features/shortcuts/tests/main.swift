import AppKit
import Checks
@testable import CommandPalette
@testable import Shortcuts
import Explorer
import Search
import Tabs
import Terminal

// Tests of the shortcuts feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

/// Every command the app registers, as main.swift does.
@MainActor
func appRegistry() -> CommandRegistry {
    let registry = CommandRegistry()
    let palette = CommandPaletteController(registry: registry) { _ in nil }
    registry.register(palette.openCommand)
    registry.register(StandardCommands.all)
    registry.register(TerminalCommands.all)
    registry.register(TabCommands.all { nil })
    registry.register(ExplorerCommands.all(ExplorerController(root: NSTemporaryDirectory()) { _ in false }))
    registry.register(SearchCommands.all(SearchController(root: NSTemporaryDirectory(), showHidden: false) { _, _ in },
                                         palette: palette))
    return registry
}

let exitCode = await Checks.run([
    ("key combinations parse, print and label", {
        let combo = KeyCombo("cmd+shift+d")
        expect(combo == KeyCombo(key: "d", command: true, shift: true))
        expect(combo?.description == "shift+cmd+d")
        expect(combo?.label == "⇧⌘D")
        expect(KeyCombo("cmd+opt+left")?.label == "⌥⌘←")
        expect(KeyCombo("ctrl+tab")?.isTerminalControlKey == false)
        expect(KeyCombo("ctrl+b")?.isTerminalControlKey == true)
        expect(KeyCombo("hyper+x") == nil)
        expect(KeyCombo("cmd+") == nil)
    }),
    ("every default shortcut points to a registered command, without repeats", {
        let registry = appRegistry()
        let keymap = Keymap(registry: registry)
        expect(keymap.problems.isEmpty, "\(keymap.problems)")
        for (_, id) in keymap.bindings { expect(registry.command(id) != nil, id) }
        expect(keymap.command(for: KeyCombo("cmd+k")!) == "palette.open")
        expect(keymap.combo(for: "terminal.clear")?.label == "⌘L")
    }),
    ("the preferences file overrides, adds and turns off shortcuts", {
        let registry = appRegistry()
        var keymap = Keymap(registry: registry)
        keymap.applyPreferences([
            "cmd+shift+l": "terminal.clear",
            "cmd+l": NSNull(),
            "cmd+f": "edit.copy",
            "ctrl+r": "terminal.find",
            "cmd+j": "nao.existe",
        ], registry: registry)
        expect(keymap.command(for: KeyCombo("cmd+shift+l")!) == "terminal.clear")
        expect(keymap.command(for: KeyCombo("cmd+l")!) == nil)
        expect(keymap.command(for: KeyCombo("cmd+f")!) == "edit.copy")
        expect(keymap.command(for: KeyCombo("ctrl+r")!) == nil, "Ctrl+letter is the terminal's")
        expect(keymap.problems.count == 3, "\(keymap.problems)")
    }),
    ("every command of the app is found by its own title", {
        let registry = appRegistry()
        for command in registry.commands {
            let found = PaletteModel.items(for: command.title, registry: registry) { _ in nil }.map(\.id)
            expect(found.contains(command.id), "\(command.id) not found by \"\(command.title)\"")
        }
        expect(registry.commands.allSatisfy { !$0.title.isEmpty })
    }),
    ("every menu item runs a registered command", {
        let registry = appRegistry()
        let menu = CommandMenu(registry: registry) { _ in nil }.build()
        let ids = menu.items.flatMap { $0.submenu?.items ?? [] }.compactMap { $0.representedObject as? String }
        expect(ids.count == registry.commands.count)
        expect(ids.allSatisfy { registry.command($0) != nil })
    }),
    ("shortcuts from settings.json override and turn off defaults", {
        let registry = appRegistry()
        var keymap = Keymap(registry: registry)
        keymap.applyPreferences(["cmd+shift+t": "tab.new", "cmd+l": nil] as [String: String?], registry: registry)
        expect(keymap.command(for: KeyCombo("cmd+shift+t")!) == "tab.new")
        expect(keymap.command(for: KeyCombo("cmd+l")!) == nil)
        expect(keymap.problems.isEmpty, "\(keymap.problems)")
    }),
])
exit(exitCode)
