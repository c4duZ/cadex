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
]
