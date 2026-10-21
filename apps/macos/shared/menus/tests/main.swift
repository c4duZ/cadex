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
    ("a hover tip goes centered under its button, above it at the bottom of the screen", {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 100, height: 22)
        expect(HoverTip.origin(for: size, under: NSRect(x: 450, y: 500, width: 20, height: 20), screen: screen) == NSPoint(x: 410, y: 472))
        expect(HoverTip.origin(for: size, under: NSRect(x: 450, y: 10, width: 20, height: 20), screen: screen).y == 36)
        expect(HoverTip.origin(for: size, under: NSRect(x: 990, y: 500, width: 10, height: 20), screen: screen).x == 896)
        expect(HoverTip.delay == 0.2)
    }),
    ("shortcuts are written and split into keys as in the palette", {
        expect(MenuEntry.shortcutLabel(key: "d", modifiers: [.command, .shift]) == "⇧⌘D")
        expect(MenuLayout.keys(of: "⇧⌘D") == ["⇧", "⌘", "D"] && MenuLayout.keys(of: "F2") == ["F2"])
    }),
    ("a tip of one line stays 22 high; a longer one wraps at 360 and grows", {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        let panel = HoverTipPanel()
        panel.show("Files (⇧⌘E)", under: NSRect(x: 100, y: 400, width: 30, height: 30), in: window)
        expect(panel.frame.height == 22, "\(panel.frame)")
        panel.show("a subject far too long to fit in a single line of a narrow sidebar, and more\nmain, origin/main\nAna <a@x>\n1 January 1970\nabc1234567",
                   under: NSRect(x: 100, y: 400, width: 30, height: 30), in: window)
        expect(panel.frame.width <= HoverTipPanel.maxWidth + 16 && panel.frame.height > 80, "\(panel.frame)")
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let view = panel.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/hover-tip.png"))
        }
        panel.orderOut(nil)
    }),
    ("a hover card opens by the names the system calls, and draws as a popover", {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 60), styleMask: [.borderless], backing: .buffered, defer: false)
        let item = NSView(frame: NSRect(x: 100, y: 10, width: 80, height: 20))
        window.contentView?.addSubview(item)
        let card = HoverCard(over: item) {
            let label = NSTextField(labelWithString: "vps-bkdg   up 20 ms")
            label.textColor = .white
            return label
        }
        expect(card.responds(to: Selector(("mouseEntered:"))) && card.responds(to: Selector(("mouseExited:"))),
               "the tracking area calls mouseEntered: and mouseExited:")
        let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        _ = card.perform(Selector(("mouseEntered:")), with: event)
        try? await Task.sleep(nanoseconds: 400_000_000)
        expect(card.panel?.isVisible == true, "it opened")
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let view = card.panel?.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/hover-card.png"))
        }
        card.close()
    }),
])
exit(exitCode)
