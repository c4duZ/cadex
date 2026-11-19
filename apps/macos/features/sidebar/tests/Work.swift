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
        expect(WorkProject(id: "/a", name: "bhband-site").initials == "BS" && WorkProject(id: "/b", name: "cadex").initials == "CA")
    }),
    ("the switch: Work by default; Files shows the view the app gave, and back", {
        var modes: [WorkSidebarMode] = []
        let view = WorkSidebarView { _ in }
        view.onMode = { modes.append($0) }
        let files = NSView()
        view.setFiles(files)
        expect(view.mode == .work && files.isHidden)
        view.setMode(.files)
        expect(view.mode == .files && !files.isHidden)
        view.setMode(.work)
        expect(files.isHidden)
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
]
