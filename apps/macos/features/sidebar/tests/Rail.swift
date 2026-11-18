import AppKit
import Checks
@testable import Sidebar
import StateGlyph

// The rail (plan 36 phase A; docs/adr/0038-rail-and-side-column.md): a tile per project, the chosen
// one ringed, the badge only for a state to see, the open dot, the foot's commands.

@MainActor
let railChecks: [(name: String, body: Checks.Body)] = [
    ("the rail: a tile per project, the chosen ringed, the badge and the open dot, the click picks", {
        var ran: [String] = []
        var picked: [String] = []
        let rail = RailView { ran.append($0) }
        rail.onPick = { picked.append($0) }
        rail.frame = NSRect(x: 0, y: 0, width: 56, height: 600)
        rail.show([RailProject(id: "/a", name: "bkdg-center", state: .done, open: true),
                   RailProject(id: "/b", name: "cadex", state: .needs, open: true),
                   RailProject(id: "/c", name: "fba-site", state: .idle)], chosen: "/a")
        expect(rail.tileIDs == ["/a", "/b", "/c"], "\(rail.tileIDs)")
        expect(rail.chosenID == "/a")
        expect(rail.tiles.map(\.badgeShown) == [true, true, false], "idle has no badge")
        expect(rail.tiles.map(\.dotShown) == [true, true, false])
        expect(rail.tiles[1].project.mark == "C" && RailProject(id: "/x", name: "2fa").mark == "2")
        rail.tiles[1].onPress?()
        expect(picked == ["/b"])
        rail.show(rail.tiles.map(\.project), chosen: "/b")
        expect(rail.chosenID == "/b")
    }),
    ("a tile shows the project's picture, else its emoji, else its letter (plan 36 B)", {
        let png = NSTemporaryDirectory() + "rail-\(UUID().uuidString).png"
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); image.unlockFocus()
        try? NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: png))
        let rail = RailView { _ in }
        rail.show([RailProject(id: "/a", name: "cadex", image: png), RailProject(id: "/b", name: "bkdg", emoji: "🦊"),
                   RailProject(id: "/c", name: "fba")], chosen: nil)
        expect(rail.tiles.map(\.pictureShown) == [true, false, false])
        expect(rail.tiles.map(\.markText) == ["C", "🦊", "F"], "\(rail.tiles.map(\.markText))")
        rail.show([RailProject(id: "/a", name: "a"), RailProject(id: "/b", name: "b", pinned: false)], chosen: nil)
        expect(rail.groupLineShown, "a line between the pinned and the others")
        rail.show([RailProject(id: "/a", name: "a"), RailProject(id: "/b", name: "b")], chosen: nil)
        expect(!rail.groupLineShown)
        // The chosen one ringed after a pick, with the line before an unpinned one (seen in the app:
        // the ring went to the unpinned tile).
        rail.show([RailProject(id: "/a", name: "a"), RailProject(id: "/b", name: "b"), RailProject(id: "/c", name: "c", pinned: false)], chosen: "/a")
        rail.show([RailProject(id: "/a", name: "a"), RailProject(id: "/b", name: "b", open: true), RailProject(id: "/c", name: "c", pinned: false)], chosen: "/b")
        expect(rail.tiles.map(\.chosen) == [false, true, false], "\(rail.tiles.map(\.chosen))")
        var menus: [String] = []
        rail.menuFor = { menus.append($0); return [] }
        expect(rail.menuFor?("/b").isEmpty == true && menus == ["/b"])
    }),
    ("the rail's foot: Projects and Automations run their commands, lit with their page", {
        let rail = RailView { _ in }
        expect(rail.footCommands == ["project.show-all", "orchestration.show-automations"], "\(rail.footCommands)")
        rail.footLit = .automations
        expect(rail.litCommands == ["orchestration.show-automations"])
        rail.footLit = nil
        expect(rail.litCommands.isEmpty)
    }),
    ("the pages' icons in the rail: a click opens the column on the page; on the lit one, folds it", {
        var ran: [String] = []
        let rail = RailView { ran.append($0) }
        rail.setPages([RailPage(id: "files", title: "Files", icon: .folder, command: "explorer.focus"),
                       RailPage(id: "changes", title: "Changes", icon: .gitDiff, command: "git.show")])
        expect(rail.pageCommands == ["explorer.focus", "git.show"])
        rail.pressPage(1)
        expect(ran == ["git.show"], "closed: opens on the page")
        rail.pageLit = "changes"
        expect(rail.litPage == "changes")
        rail.pressPage(1)
        expect(ran == ["git.show", "view.toggle-sidebar"], "lit: folds the column")
        rail.pressPage(0)
        expect(ran.last == "explorer.focus", "another page: goes to it")
    }),
    ("dragging in the rail: a tile goes among the others live and past the line pins; the pages reorder", {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 56, height: 700), styleMask: [.borderless], backing: .buffered, defer: true)
        let rail = RailView { _ in }
        window.contentView = rail
        rail.show([RailProject(id: "/a", name: "a", open: true), RailProject(id: "/b", name: "b", open: true),
                   RailProject(id: "/c", name: "c", open: true, pinned: false), RailProject(id: "/d", name: "d", pinned: false)], chosen: nil)
        rail.setPages([RailPage(id: "files", title: "Files", icon: .folder, command: "explorer.focus"),
                       RailPage(id: "changes", title: "Changes", icon: .gitDiff, command: "git.show")])
        rail.layoutSubtreeIfNeeded()
        var moved: [(String, [String], Bool)] = []
        var pages: [[String]] = []
        rail.onMove = { moved.append(($0, $1, $2)) }
        rail.onMovePages = { pages.append($0) }
        var picked: [String] = []
        rail.onPick = { picked.append($0) }
        func at(_ view: NSView, _ dy: CGFloat = 0) -> NSPoint {
            let mid = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
            return NSPoint(x: mid.x, y: mid.y + dy)
        }
        func drag(_ view: NSView, to point: NSPoint) {
            let start = at(view)
            func event(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                   context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            view.mouseDown(with: event(.leftMouseDown, start))
            view.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: start.x, y: (start.y + point.y) / 2)))
            view.mouseDragged(with: event(.leftMouseDragged, point))
            view.mouseUp(with: event(.leftMouseUp, point))
        }
        // "c" (open, not pinned) dragged above "a": first, and pinned.
        let c = rail.tiles[2]
        drag(c, to: at(rail.tiles[0], 4))
        expect(moved.count == 1 && moved[0].0 == "/c" && moved[0].1 == ["/c", "/a", "/b", "/d"] && moved[0].2, "\(moved)")
        expect(picked.isEmpty, "a drag is no click")
        // "d" has no terminal: it never goes below the line... and above it, it stays where it can.
        rail.show([RailProject(id: "/a", name: "a", open: true), RailProject(id: "/b", name: "b"),
                   RailProject(id: "/c", name: "c", open: true, pinned: false)], chosen: nil)
        rail.layoutSubtreeIfNeeded()
        drag(rail.tiles[1], to: at(rail.tiles[2], -30))
        expect(moved.last?.0 == "/b" && moved.last?.2 == true, "an empty pinned one stays above the line: \(String(describing: moved.last))")
        // A short press is still a click.
        drag(rail.tiles[0], to: at(rail.tiles[0], 2))
        expect(picked == ["/a"], "\(picked)")
        // The pages: Changes over Files.
        let changes = rail.pageButtons[1].1
        drag(changes, to: at(rail.pageButtons[0].1, 4))
        expect(pages == [["changes", "files"]] && rail.pageCommands == ["git.show", "explorer.focus"], "\(pages)")
    }),
]
