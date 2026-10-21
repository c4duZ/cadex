import AppKit
import Checks
import Foundation
@testable import Customize

// Tests of the shared Customize window. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

func row(_ id: String, _ on: Bool = true, subtitle: String? = nil) -> CustomizeEntry {
    .row(CustomizeRow(id: id, icon: .files, title: id.capitalized, subtitle: subtitle, on: on))
}

let exitCode = await Checks.run([
    ("rows belong to the title above them", {
        let entries: [CustomizeEntry] = [.header("Left"), row("folder"), .header("Right"), row("environment"), row("ram", false)]
        expect(CustomizeLayout.sections(entries).map { $0.map(\.id) } == [["folder"], ["environment", "ram"]])
        expect(CustomizeLayout.sections([.header("Left"), .header("Right"), row("cpu")]).map { $0.map(\.id) } == [[], ["cpu"]])
    }),
    ("moving a row past a title changes its section; none goes above the first title", {
        let entries: [CustomizeEntry] = [.header("Left"), row("folder"), .header("Right"), row("environment")]
        let moved = CustomizeLayout.moved(entries, from: 3, to: 1)
        expect(CustomizeLayout.sections(moved).map { $0.map(\.id) } == [["environment", "folder"], []], "\(moved)")
        expect(CustomizeLayout.moved(entries, from: 1, to: 0) == entries, "the first title stays first")
        expect(CustomizeLayout.moved(entries, from: 0, to: 3) == entries, "titles do not move")
    }),
    ("flipping a switch changes only that row", {
        let flipped = CustomizeLayout.flipped([.header("X"), row("a"), row("b")], "b")
        expect(flipped.compactMap(\.row).map(\.on) == [true, false])
    }),
    ("a dragged thing lands in the slot under its middle", {
        let widths: [CGFloat] = [30, 30, 30]
        expect(CustomizeLayout.dropIndex(at: 5, widths: widths, spacing: 2) == 0)
        expect(CustomizeLayout.dropIndex(at: 47, widths: widths, spacing: 2) == 1, "the middle of slot 1 is slot 1")
        expect(CustomizeLayout.dropIndex(at: 200, widths: widths, spacing: 2) == 2)
    }),
    ("dragging a row reorders the list while the mouse moves, the row on top, across a title", {
        let list = CustomizeList()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(list)
        list.frame = NSRect(x: 0, y: 0, width: 300, height: 260)
        list.show([.header("Left"), row("folder"), .header("Right"), row("environment"), row("ram", false)], colors: CustomizeColors())
        list.layoutSubtreeIfNeeded()
        var changes: [[CustomizeEntry]] = []
        list.onChange = { changes.append($0) }
        @MainActor func event(_ type: NSEvent.EventType, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: list.convert(NSPoint(x: 20, y: y), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // From Right's last row (ram) up into Left.
        let start = list.views[4].frame.midY
        let end = list.views[1].frame.midY
        list.mouseDown(with: event(.leftMouseDown, start))
        var y = start
        while y > end {
            y = max(y - 4, end)
            list.mouseDragged(with: event(.leftMouseDragged, y))
        }
        expect(CustomizeLayout.sections(list.entries).first?.map(\.id).contains("ram") == true, "moved before the mouse goes up: \(list.entries)")
        expect(list.subviews.last === list.views[list.entries.firstIndex { $0.row?.id == "ram" } ?? 0], "the dragged row is on top")
        list.mouseUp(with: event(.leftMouseUp, y))
        expect(changes.count == 1, "one change per drop")
    }),
    ("one window for the app: a tab per page, each change goes to the open tab's owner", {
        var sidebar: [[CustomizeEntry]] = []
        var status: [[CustomizeEntry]] = []
        let pages = [
            CustomizePage(id: "sidebar", title: "Sidebar", icon: .sidebar, note: "n", entries: [.header("Icons"), row("files")]) { sidebar.append($0) },
            CustomizePage(id: "statusBar", title: "Status Bar", icon: .slidersHorizontal, note: "n",
                          entries: [.header("Left"), row("folder"), .header("Right"), row("ram", false)]) { status.append($0) },
        ]
        let window = CustomizeWindow.shared
        window.show(pages, selecting: "statusBar", colors: CustomizeColors(), over: nil)
        expect(window.selected == 1 && window.entries.compactMap(\.row).map(\.id) == ["folder", "ram"])
        expect(window.collectionBehavior.contains(.fullScreenAuxiliary) && window.collectionBehavior.contains(.moveToActiveSpace),
               "over the app in full screen, as settings")
        window.show(pages, selecting: "sidebar", colors: CustomizeColors(), over: nil)
        expect(window.selected == 0 && CustomizeWindow.shared === window, "the same window, another tab")
        window.close()
        expect(sidebar.isEmpty && status.isEmpty)
    }),
    ("a picture of the window, with CADEX_SNAPSHOT_DIR", {
        guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
        let colors = CustomizeColors(text: .white, secondary: NSColor(white: 0.62, alpha: 1), accent: NSColor(red: 0.88, green: 0.64, blue: 0.35, alpha: 1),
                                     panel: NSColor(white: 0.11, alpha: 1), box: NSColor(white: 0.15, alpha: 1), border: NSColor(white: 0.22, alpha: 1))
        let pages = [
            CustomizePage(id: "sidebar", title: "Sidebar", icon: .sidebar, note: "", entries: [.header("Icons"), row("files")]) { _ in },
            CustomizePage(id: "statusBar", title: "Status Bar", icon: .slidersHorizontal, note: "Drag between Left and Right. A hidden item measures nothing.",
                          entries: [.header("Left"), row("folder"), .header("Right"), row("environment"),
                                    row("ram", false, subtitle: "Memory in use, every 2 s"), row("cpu", false)]) { _ in },
        ]
        let window = CustomizeWindow.shared
        window.appearance = NSAppearance(named: .darkAqua)
        window.show(pages, selecting: "statusBar", colors: colors, over: nil)
        guard let view = window.contentView else { return expect(false) }
        view.layoutSubtreeIfNeeded()
        let root = NSView(frame: NSRect(origin: .zero, size: view.fittingSize))
        root.wantsLayer = true
        root.layer?.backgroundColor = colors.panel.cgColor
        view.frame = root.bounds
        root.addSubview(view)
        root.layoutSubtreeIfNeeded()
        if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/customize-status.png"))
        }
        window.close()
    }),
])
exit(exitCode)
