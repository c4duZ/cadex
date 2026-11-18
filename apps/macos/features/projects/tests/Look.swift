import AppKit
import Checks
@testable import Projects
import Tabs

// Editing a project (plan 36 phase B): the name, the color, a picture copied in square and small,
// an emoji; all saved and back after a restart; a replaced picture leaves its folder.

@MainActor
let lookTests: [(name: String, body: Checks.Body)] = [
    ("a project's look: name, color, picture and emoji, saved and back; the old picture goes", {
        let (a, _) = folders()
        let file = tempFile()
        let projects = controller(file, window: window())
        projects.start(folder: a) { _ in nil }
        // A 300×200 image of the Mac.
        let source = tempDir().appendingPathComponent("photo.png")
        let image = NSImage(size: NSSize(width: 300, height: 200))
        image.lockFocus(); NSColor.systemPink.setFill(); NSRect(x: 0, y: 0, width: 300, height: 200).fill(); image.unlockFocus()
        try? NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: source)
        let first = projects.storeImage(from: source)
        expect(first != nil && projects.imageURL(first) != nil, "the picture is copied in")
        let stored = NSImage(contentsOf: projects.imageURL(first)!)!
        let rep = stored.representations.first!
        expect(rep.pixelsWide == 128 && rep.pixelsHigh == 128, "square and small: \(rep.pixelsWide)×\(rep.pixelsHigh)")
        projects.setLook(ProjectLook(name: "  Cadex app  ", color: "magenta", image: first, emoji: " 🦊 "), for: a)
        expect(projects.look(of: a) == ProjectLook(name: "Cadex app", color: "magenta", image: first, emoji: "🦊"))
        let second = projects.storeImage(from: source)
        projects.setLook(ProjectLook(name: "", color: nil, image: second, emoji: ""), for: a)
        expect(projects.imageURL(first) == nil, "the replaced picture leaves the folder")
        expect(projects.look(of: a) == ProjectLook(name: (a as NSString).lastPathComponent, color: nil, image: second, emoji: nil),
               "an empty name is the folder's again; an empty emoji is none")
        projects.saveNow()
        projects.projects.forEach { $0.tabs.closeAll() }
        let again = controller(file, window: window())
        again.start(folder: a) { _ in nil }
        expect(again.look(of: a)?.image == second, "back after a restart")
        expect(projects.storeImage(from: tempDir().appendingPathComponent("nope.png")) == nil, "a file that is no image: nothing")
        again.projects.forEach { $0.tabs.closeAll() }
    }),
    ("pinned: the last terminal closing leaves it in the list without tabs; unpinned it goes; a file of before is pinned", {
        let (a, b) = folders()
        let file = tempFile()
        let projects = controller(file, window: window())
        projects.start(folder: a) { _ in nil }
        projects.open(folder: b)
        expect(!projects.isPinned(a) && !projects.isPinned(b), "opened folders are not pinned")
        projects.setPinned(true, for: b)
        projects.closeTerminals(folder: b)
        expect(projects.projects.map(\.folder) == [a, b] && projects.projects[1].tabs.count == 0, "pinned stays, with no tab")
        expect(projects.activeFolder == a, "the one with terminals shows")
        projects.setPinned(false, for: b)
        expect(projects.projects.map(\.folder) == [a], "unpinned with no terminal: gone")
        projects.open(folder: b)
        projects.setPinned(true, for: b)
        projects.closeTerminals(folder: b)
        projects.saveNow()
        projects.projects.forEach { $0.tabs.closeAll() }
        let again = controller(file, window: window())
        again.start(folder: a) { _ in nil }
        expect(again.projects.count == 2 && again.isPinned(b) && again.projects[1].tabs.count == 0, "back pinned and empty")
        again.removeFromRail(folder: b)
        expect(again.projects.map(\.folder) == [a], "Remove from the Sidebar")
        again.projects.forEach { $0.tabs.closeAll() }
        // A file saved before plan 36 has no "pinned": its projects stay.
        let old = SavedProjects(projects: [.init(name: "a", folder: a, tabs: TabsSnapshot(items: [], active: 0))], active: 0)
        let oldFile = tempFile()
        try? ProjectsFile.save(old, to: oldFile)
        let before = controller(oldFile, window: window())
        before.start(folder: a) { _ in nil }
        expect(before.isPinned(a))
        before.projects.forEach { $0.tabs.closeAll() }
    }),
    ("the rail's order (plan 36 E): dragged, kept; the shown one stays; above the line pins, an empty one never unpins", {
        let (a, b) = folders()
        let projects = controller(tempFile(), window: window())
        projects.start(folder: a) { _ in nil }
        projects.open(folder: b)
        expect(projects.activeFolder == b)
        projects.arrange([b, a], moved: b, pinned: true)
        expect(projects.projects.map(\.folder) == [b, a] && projects.activeFolder == b, "\(projects.projects.map(\.folder))")
        expect(projects.isPinned(b) && !projects.isPinned(a), "dragged above the line: pinned")
        projects.arrange([a, b], moved: a, pinned: true)
        projects.arrange([b, a], moved: a, pinned: false)
        expect(!projects.isPinned(a), "below the line with terminals: not pinned")
        projects.closeTerminals(folder: b)
        projects.arrange([a, b], moved: b, pinned: false)
        expect(projects.isPinned(b) && projects.projects.count == 2, "pinned and empty stays pinned")
        projects.projects.forEach { $0.tabs.closeAll() }
    }),
    ("the project's Settings: Edit Name and Image… and the pinned box (plan 36 E)", {
        var edits = 0
        var pins: [Bool] = []
        let look = ProjectSettingsLook(picture: nil, name: "cadex", pinned: true, edit: { edits += 1 }, pinned: { pins.append($0) })
        expect(look.pinShown)
        look.clickPin()
        expect(pins == [false] && !look.pinShown, "\(pins)")
    }),
    ("the column's Sessions: the groups with their lines, the search filters, the click picks", {
        let view = SessionsColumnView()
        var picked: [String] = []
        view.onPick = { picked.append($0) }
        view.show([("Today", [PageListItem(id: "1", title: "Estado da memória", note: "bkdg · 8 min")]),
                   ("This week", []),
                   ("Earlier", [PageListItem(id: "2", title: "Handoff plano 24", note: "bhband · 9 d")])])
        expect(view.rowTitles == ["Estado da memória", "Handoff plano 24"], "\(view.rowTitles)")
        view.setQuery("bhband")
        expect(view.rowTitles == ["Handoff plano 24"], "the note matches too")
        view.setQuery("")
        let row = view.subviews.compactMap { $0 as? NSScrollView }.first?.documentView?.subviews.compactMap { $0 as? SessionRowView }.first
        row?.onPress?()
        expect(picked == ["1"])
    }),
]
