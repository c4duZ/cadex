import AppKit
import Checks
@testable import CommandPalette
@testable import Shortcuts
import Explorer
import Search
import Editor
import Markdown
import MediaPreview
import Preview
import SourceControl
import GitHistory
import Projects
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
    registry.register(EditorCommands.all { nil })
    registry.register(MediaCommands.all { nil })
    registry.register(PreviewCommands.all(open: { _, _ in }, active: { nil }))
    registry.register(SourceControlCommands.all(SourceControlController(folder: NSTemporaryDirectory()) { _ in false },
                                                palette: palette))
    registry.register(HistoryCommands.all(open: { _ in }, repository: { nil }, active: { nil }))
    registry.register(ProjectsCommands.all(ProjectsController { fatalError("not called") }, palette: palette) { "/" })
    registry.register(MarkdownCommands.all(MarkdownController(root: NSTemporaryDirectory(), findFiles: { _ in [] }, open: { _, _ in }),
                                           palette: palette) { nil })
    registry.register(SearchCommands.all(SearchController(root: NSTemporaryDirectory(), showHidden: false) { _, _, _ in },
                                         palette: palette))
    return registry
}

let exitCode = await Checks.run([
    ("a press another part takes first ends there: ⌘1 in ⌘J's list is not tab.select-1", { @MainActor in
        let registry = CommandRegistry()
        var ran = 0
        registry.register(Command(id: "tab.select-1", title: "Tab 1", category: .tabs, defaultShortcut: "cmd+1", action: .run { ran += 1 }))
        let dispatcher = ShortcutDispatcher(registry: registry, keymap: Keymap(registry: registry))
        guard let press = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
                                           characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18) else { return expect(false) }
        var wanted = true
        dispatcher.takenFirst = { _ in wanted }
        expect(dispatcher.handle(press) && ran == 0, "the palette took it: handled, the command not run")
        wanted = false
        expect(dispatcher.handle(press) && ran == 1, "otherwise the shortcut runs")
    }),
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
            "ctrl+r": "edit.find",
            "cmd+j": "nao.existe",
        ], registry: registry)
        expect(keymap.command(for: KeyCombo("cmd+shift+l")!) == "terminal.clear")
        expect(keymap.command(for: KeyCombo("cmd+l")!) == nil)
        expect(keymap.command(for: KeyCombo("cmd+f")!) == "edit.copy")
        expect(keymap.command(for: KeyCombo("ctrl+r")!) == nil, "Ctrl+letter is the terminal's")
        expect(keymap.problems.count == 3, "\(keymap.problems)")
    }),
    ("every command that can run is found by its own title", {
        let registry = appRegistry()
        // The ones that cannot run now are left out of the palette.
        for command in registry.commands where command.unavailableReason() == nil {
            let found = PaletteModel.items(for: command.title, registry: registry) { _ in nil }.map(\.id)
            expect(found.contains(command.id), "\(command.id) not found by \"\(command.title)\"")
        }
        expect(registry.commands.allSatisfy { !$0.title.isEmpty })
    }),
    ("every menu item runs a registered command", {
        let registry = appRegistry()
        let menu = CommandMenu(registry: registry) { _ in nil }.build()
        // Every level (the areas' submenus, plan 37); the palette is also in Help.
        func ids(_ items: [NSMenuItem]) -> [String] {
            items.flatMap { item in [item.representedObject as? String].compactMap { $0 } + ids(item.submenu?.items ?? []) }
        }
        let all = ids(menu.items)
        expect(Set(all) == Set(registry.commands.map(\.id)), "every command is in the menu")
        expect(all.allSatisfy { registry.command($0) != nil })
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
