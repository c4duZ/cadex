import AppKit
import Checks
@testable import Sidebar
import StateGlyph

// The sidebar of ADR 0039 (plan 38 phase B): the Work list, the place lit, the clicks, the switch.
@MainActor
let workChecks: [(name: String, body: Checks.Body)] = [
    ("the Work list: projects, an unfolded one with main and its tasks, the place lit, New Project last", {
        var ran: [String] = []
        var projects: [String] = []
        var places: [String] = []
        var toggled: [String] = []
        let view = WorkSidebarView { ran.append($0) }
        view.onPickProject = { projects.append($0) }
        view.onPickPlace = { places.append($0) }
        view.onToggle = { toggled.append($0) }
        view.show([WorkProject(id: "/cadex", name: "cadex", state: .working, terminals: 3, expanded: true,
                               places: [WorkPlace(id: "/cadex", name: "main", isMain: true, terminals: 1),
                                        WorkPlace(id: "/w/kite-fix", name: "kite-fix", state: .working, terminals: 2)]),
                   WorkProject(id: "/bh", name: "bhband-site", terminals: 1, waiting: 1),
                   WorkProject(id: "/nt", name: "notes")], place: "/w/kite-fix")
        expect(view.lineTitles == ["cadex", "main", "kite-fix", "bhband-site", "notes", "New Project…"], "\(view.lineTitles)")
        expect(view.litTitle == "kite-fix")
        view.press("bhband-site")
        view.press("kite-fix")
        view.press("New Project…")
        expect(projects == ["/bh"] && places == ["/w/kite-fix"] && ran == ["project.create"], "\(projects) \(places) \(ran)")
        var asked: [String] = []
        view.menuForPlace = { asked.append($0); return [] }
        let kite = view.list.arrangedSubviews.compactMap { $0 as? WorkChildren }.flatMap(\.rows).first { $0.title == "kite-fix" }
        let main = view.list.arrangedSubviews.compactMap { $0 as? WorkChildren }.flatMap(\.rows).first { $0.title == "main" }
        _ = kite?.rightMenu?()
        expect(asked == ["/w/kite-fix"] && main?.rightMenu == nil, "a task's line has its menu, main's none: \(asked)")
        // An image dropped on a project's line becomes its picture, as on the strip's tile.
        var dropped: [String] = []
        view.onDropImage = { folder, url in dropped.append(folder + "|" + url.lastPathComponent) }
        let notes = view.list.arrangedSubviews.compactMap { $0 as? WorkRow }.first { $0.title == "notes" }
        expect(notes?.registeredDraggedTypes.contains(.fileURL) == true && kite?.registeredDraggedTypes.isEmpty == true)
        notes?.onDropImage?(URL(fileURLWithPath: "/tmp/face.png"))
        expect(dropped == ["/nt|face.png"], "\(dropped)")
        expect(WorkProject(id: "/a", name: "bhband-site").initials == "BS" && WorkProject(id: "/b", name: "cadex").initials == "CA")
    }),
    ("the switch: Work by default; Files shows the view the app gave, and back", {
        var modes: [WorkSidebarMode] = []
        let view = WorkSidebarView { _ in }
        view.onMode = { modes.append($0) }
        let files = NSView()
        view.setFiles(files)
        expect(view.mode == .work && !view.filesShown)
        view.setMode(.files)
        expect(view.mode == .files && view.filesShown)
        view.setMode(.work)
        expect(!view.filesShown)
    }),
    ("the needs-you queue shows only with requests; a waiting project out of sight puts its name on the edge", {
        var picked: [String] = []
        let view = WorkSidebarView { _ in }
        view.onPickRequest = { picked.append($0) }
        view.frame = NSRect(x: 0, y: 0, width: 248, height: 260)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = view
        view.showQueue([])
        expect(view.queueAnchor == nil, "no request, no queue")
        view.showQueue([WorkRequest(id: "r1", who: "checkout-copy", project: "bhband-site", ask: "wants to run npm install stripe",
                                    since: Date().addingTimeInterval(-90))])
        expect(view.queueAnchor != nil)
        expect(WorkRequest.waited(Date().addingTimeInterval(-90)) == "1 min")
        var projects = (1...12).map { WorkProject(id: "/p\($0)", name: "p\($0)", terminals: 1) }
        projects.append(WorkProject(id: "/bh", name: "bhband-site", terminals: 1, waiting: 1))
        view.show(projects, place: nil)
        view.layoutSubtreeIfNeeded()
        view.updateEdge()
        expect(view.edgeSaid.hasPrefix("▼ bhband-site"), "\(view.edgeSaid)")
    }),
    ("nothing open: the recents with their faces, New Project… and Open Folder…, no switch; a project brings it back", {
        var ran: [String] = []
        var picked: [String] = []
        let view = WorkSidebarView { ran.append($0) }
        view.onPickRecent = { picked.append($0) }
        view.showRecents([WorkRecent(project: WorkProject(id: "/cadex", name: "cadex"), when: "4m"),
                          WorkRecent(project: WorkProject(id: "/nt", name: "notes"), when: "2d")], openShortcut: "⌃⌘N")
        expect(view.showsRecents && view.lineTitles == ["cadex", "notes", "New Project…", "Open Folder…"], "\(view.lineTitles)")
        view.press("notes")
        view.press("Open Folder…")
        expect(picked == ["/nt"] && ran == ["project.new"], "\(picked) \(ran)")
        view.show([WorkProject(id: "/cadex", name: "cadex")], place: nil)
        expect(!view.showsRecents && view.lineTitles == ["cadex", "New Project…"], "\(view.lineTitles)")
    }),
    ("Files: the head in words, \"N changes · see\" at the end, hidden with none or while Changes shows", {
        var shown = 0
        let view = WorkSidebarView { _ in }
        view.onShowChanges = { shown += 1 }
        view.setFiles(NSView())
        view.setFilesHead(title: "kite-fix", detail: "task of cadex · against main")
        expect(view.filesHeadSaid == "kite-fix · task of cadex · against main")
        view.setChanges(count: 3, showingChanges: false)
        expect(view.changesSaid == "3 changes")
        view.setChanges(count: 0, showingChanges: false)
        expect(view.changesSaid.isEmpty, "none: no line")
        view.setChanges(count: 2, showingChanges: true)
        expect(view.changesSaid.isEmpty, "while Changes shows: no line")
    }),
]
