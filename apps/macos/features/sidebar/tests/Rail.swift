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
]
