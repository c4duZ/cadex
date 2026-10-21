import AppKit
import Checks
import Foundation
@testable import Sidebar

// Tests of the sidebar feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let known = ["files", "search", "git", "history", "preview"]

@MainActor
func catalog() -> [SidebarItem] {
    [SidebarItem(id: "files", icon: .files, title: "Files", command: "explorer.focus", kind: .page(NSView())),
     SidebarItem(id: "search", icon: .magnifyingGlass, title: "Search", command: "search.content", kind: .action),
     SidebarItem(id: "git", icon: .gitBranch, title: "Git", command: "git.show", kind: .page(NSView()))]
}

let exitCode = await Checks.run([
    ("the saved list keeps its order and drops unknown and repeated ids", {
        let (ids, problems) = SidebarLayout.shown(["git", "agents", "files", "git"], known: known)
        expect(ids == ["git", "files"], "\(ids)")
        expect(problems.count == 2, "\(problems)")
        expect(SidebarLayout.shown([], known: known).ids.isEmpty)
    }),
    ("toggling shows at the end and hides in place", {
        expect(SidebarLayout.toggled(["files", "git"], "history") == ["files", "git", "history"])
        expect(SidebarLayout.toggled(["files", "git", "history"], "git") == ["files", "history"])
    }),
    ("moving puts an id at the index, clamped", {
        expect(SidebarLayout.moved(["files", "search", "git"], "git", to: 0) == ["git", "files", "search"])
        expect(SidebarLayout.moved(["files", "search", "git"], "files", to: 9) == ["search", "git", "files"])
        expect(SidebarLayout.moved(["files"], "nope", to: 0) == ["files"])
    }),
    ("the customize list shows the shown first, then the hidden in catalog order", {
        let order = SidebarLayout.customizeOrder(shown: ["git", "files"], known: known)
        expect(order == ["git", "files", "search", "history", "preview"], "\(order)")
    }),
    ("icons that do not fit leave room for the more button", {
        expect(SidebarLayout.fitting(4, iconWidth: 30, spacing: 2, width: 200) == 4)
        // 4 icons need 126; with 100, 2 icons and "…" fit (94).
        expect(SidebarLayout.fitting(4, iconWidth: 30, spacing: 2, width: 100) == 2)
        expect(SidebarLayout.fitting(4, iconWidth: 30, spacing: 2, width: 10) == 0)
    }),
    ("the view shows the first page and reports unknown ids", {
        let view = SidebarView(catalog: catalog()) { _ in }
        expect(view.page == "files")
        let problems = view.setItems(["git", "agents"])
        expect(view.items == ["git"] && problems.count == 1, "\(view.items) \(problems)")
        expect(view.page == "files", "a page whose icon is hidden stays shown")
    }),
    ("pressing an icon runs its command; the open page's icon hides the sidebar", {
        var ran: [String] = []
        let view = SidebarView(catalog: catalog()) { ran.append($0) }
        view.setItems(["files", "search", "git"])
        view.press("git")
        view.press("files")
        view.press("search")
        expect(ran == ["git.show", "view.toggle-sidebar", "search.content"], "\(ran)")
    }),
    ("toggling a page saves the new list", {
        var saved: [[String]] = []
        let view = SidebarView(catalog: catalog()) { _ in }
        view.onItemsChange = { saved.append($0) }
        view.toggle("search")
        view.toggle("nope")
        expect(saved == [["files", "git"]], "\(saved)")
    }),
    ("dragging an icon sideways reorders it, one slot or more, and it stays on top", {
        let row = SidebarIconRow()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(row)
        row.frame = NSRect(x: 0, y: 0, width: 240, height: SidebarIconButton.size.height)
        row.setItems(catalog())
        row.layoutSubtreeIfNeeded()
        var orders: [[String]] = []
        row.onReorder = { orders.append($0) }
        let step = SidebarIconButton.size.width + SidebarIconRow.spacing
        @MainActor func drag(from: CGFloat, to: CGFloat) {
            let y = SidebarIconButton.size.height / 2
            @MainActor func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: row.convert(NSPoint(x: x, y: y), to: nil), modifierFlags: [], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            row.mouseDown(with: event(.leftMouseDown, from))
            var x = from
            while x < to {
                x = min(x + 5, to)
                row.mouseDragged(with: event(.leftMouseDragged, x))
            }
            if row.subviews.last?.accessibilityLabel() != "Files" { expect(false, "the dragged icon is not on top") }
            row.mouseUp(with: event(.leftMouseUp, to))
            row.layoutSubtreeIfNeeded()
        }
        drag(from: step / 2, to: step * 1.5)
        expect(orders.count == 1, "one save per drop")
        expect(orders.last == ["search", "files", "git"], "\(orders)")
        drag(from: step * 1.5, to: step * 2.6)
        expect(orders.last == ["search", "git", "files"], "\(orders)")
        let xs = row.buttons.map(\.frame.minX)
        expect(xs == [0, step, step * 2], "each icon back in its slot: \(xs)")
        row.setItems(catalog())
        row.layoutSubtreeIfNeeded()
        expect(row.buttons.map(\.id) == ["files", "search", "git"])
        drag(from: step / 2, to: step * 2.6)
        expect(orders.last == ["search", "git", "files"], "two slots in one drag: \(orders)")
    }),
    ("Customize lists every page under one title, the shown ones first, with switch and shortcut", {
        let items = catalog() + [SidebarItem(id: "history", icon: .clockCounterClockwise, title: "Git History", command: "git.show-history",
                                             shortcut: "⇧⌘Y", kind: .page(NSView()))]
        let view = SidebarView(catalog: items) { _ in }
        view.setItems(["git", "files"])
        let entries = view.customizeEntries()
        expect(entries.first == .header("Sidebar icons"))
        expect(entries.compactMap(\.row).map(\.id) == ["git", "files", "search", "history"])
        expect(entries.compactMap(\.row).map(\.on) == [true, true, false, false])
        expect(entries.compactMap(\.row).last?.trailing == "⇧⌘Y")
    }),
    ("a picture of the sidebar, with CADEX_SNAPSHOT_DIR", {
        for (name, width) in [("sidebar", 260.0), ("sidebar-narrow", 150.0)] {
            let page = NSTextField(labelWithString: "  apps\n  core\n  docs\n  CLAUDE.md")
            page.textColor = .white
            let items = [SidebarItem(id: "files", icon: .files, title: "Files", command: "explorer.focus", shortcut: "⇧⌘E", kind: .page(page)),
                         SidebarItem(id: "search", icon: .magnifyingGlass, title: "Search", command: "search.content", kind: .action),
                         SidebarItem(id: "git", icon: .gitBranch, title: "Git", command: "git.show", kind: .page(NSView())),
                         SidebarItem(id: "history", icon: .clockCounterClockwise, title: "History", command: "git.history", kind: .action)]
            let view = SidebarView(catalog: items) { _ in }
            view.setItems(["files", "search", "git", "history"])
            view.setTitle("cadex", for: "files")
            view.setBadge("3", for: "git")
            view.setColors(.init(text: .white, secondary: NSColor(white: 0.62, alpha: 1),
                                 fill: NSColor(white: 0.2, alpha: 1), accent: NSColor(red: 0.88, green: 0.64, blue: 0.35, alpha: 1)))
            view.frame = NSRect(x: 0, y: 0, width: width, height: 200)
            snapshot(view, name)
        }
    }),
])

/// With CADEX_SNAPSHOT_DIR set, saves a picture of `view` there: the way to
/// look at the sidebar when the screen cannot be captured.
@MainActor func snapshot(_ view: NSView, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
    let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    let root = NSView(frame: view.bounds)
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
    root.addSubview(view)
    window.contentView = root
    root.layoutSubtreeIfNeeded()
    guard let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { return }
    root.cacheDisplay(in: root.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
}
exit(exitCode)
