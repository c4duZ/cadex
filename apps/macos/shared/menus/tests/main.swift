import AppKit
import Checks
@testable import Menus

// Tests of the shared popup menus. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

@MainActor
func item(_ title: String, enabled: Bool = true, shortcut: String? = nil) -> MenuEntry {
    MenuEntry(title, shortcut: shortcut, isEnabled: enabled) {}
}

let exitCode = await Checks.run([
    ("separators never come first, last or twice", {
        let tidy = MenuEntry.tidy([.separator, item("a"), .separator, .separator, item("b"), .separator])
        expect(tidy.map(\.isSeparator) == [false, true, false], "\(tidy.map(\.title))")
        expect(MenuEntry.tidy([.separator, .separator]).isEmpty)
    }),
    ("the arrows skip separators and disabled items, wrapping", {
        let entries = [item("a"), .separator, item("b", enabled: false), item("c")]
        expect(MenuLayout.next(from: nil, by: 1, in: entries) == 0)
        expect(MenuLayout.next(from: 0, by: 1, in: entries) == 3)
        expect(MenuLayout.next(from: 3, by: 1, in: entries) == 0)
        expect(MenuLayout.next(from: nil, by: -1, in: entries) == 3)
        expect(MenuLayout.next(from: nil, by: 1, in: [.separator, item("x", enabled: false)]) == nil)
    }),
    ("rows stack under the padding; the menu fits its widest line", {
        let entries = [item("Abrir"), .separator, item("Um título bem mais comprido que o mínimo do menu", shortcut: "⇧⌘D")]
        let frames = MenuLayout.frames(entries, width: 300)
        expect(frames.map(\.minY) == [5, 33, 42] && frames[2].height == 28, "\(frames)")
        expect(MenuLayout.totalHeight(entries) == 75)
        expect(MenuLayout.width([item("a")]) == MenuLayout.minWidth)
        expect(MenuLayout.width(entries) > MenuLayout.minWidth)
    }),
    ("shortcuts are written and split into keys as in the palette", {
        expect(MenuEntry.shortcutLabel(key: "d", modifiers: [.command, .shift]) == "⇧⌘D")
        expect(MenuLayout.keys(of: "⇧⌘D") == ["⇧", "⌘", "D"] && MenuLayout.keys(of: "F2") == ["F2"])
    }),
])
exit(exitCode)
