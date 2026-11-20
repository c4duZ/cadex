import Checks
import Foundation
@testable import Projects
import Tabs

// The spaces.json of before plan 27 read on the first launch after it (the owner's 2.2.1, 2026-11-20):
// every folder of the old tabs a project beside what projects.json has, once.

/// The owner's: one space, a terminal in Bea, then cadex and bkdg-center side by side.
let ownerSpaces = """
{"active":0,"folder":"/w/cadex","spaces":[{"name":"Space 1","tabs":{"active":1,"items":[
 {"terminal":{"focus":0,"layout":{"pane":{"folder":"/w/Bea"}}}},
 {"terminal":{"focus":0,"layout":{"split":{"first":{"pane":{"folder":"/w/cadex"}},"ratio":0.5,
   "second":{"pane":{"folder":"/w/bkdg-center"}},"sideBySide":true}}}}]}}],"version":1}
"""

@MainActor let legacyTests: [(name: String, body: Checks.Body)] = [
    ("every folder of the old tabs a project; a split goes with its first pane; the ones projects.json has stay as they are", {
        guard let legacy = try? JSONDecoder().decode(LegacySpaces.self, from: Data(ownerSpaces.utf8)) else { return expect(false, "it reads") }
        let fresh = ProjectsFile.merge(legacy, into: nil, home: "/home")
        expect(fresh.projects.map(\.folder) == ["/w/Bea", "/w/cadex", "/w/bkdg-center"], "\(fresh.projects.map(\.folder))")
        expect(fresh.projects.map(\.name) == ["Bea", "cadex", "bkdg-center"] && fresh.projects.allSatisfy { $0.pinned == true })
        expect(fresh.projects[1].tabs.items.count == 1 && fresh.projects[2].tabs.items.count == 1, "bkdg-center gets a terminal of its own")
        let cadex = SavedProjects.Project(name: "Cadex", folder: "/w/cadex", tabs: TabsSnapshot(items: [.terminal(title: nil, layout: .pane(folder: "/w/cadex"), focus: 0)]))
        let home = SavedProjects.Project(name: "cadu", folder: "/home", tabs: TabsSnapshot())
        let merged = ProjectsFile.merge(legacy, into: SavedProjects(projects: [home, cadex], active: 0), home: "/home")
        expect(merged.projects.map(\.folder) == ["/home", "/w/cadex", "/w/Bea", "/w/bkdg-center"], "\(merged.projects.map(\.folder))")
        expect(merged.projects[1] == cadex && merged.active == 0, "the existing project and the active one untouched")
    }),
    ("read once: projects.json gets the folders and spaces.json becomes spaces.migrated.json", {
        let dir = tempDir()
        let url = dir.appendingPathComponent("projects.json")
        try? Data(ownerSpaces.utf8).write(to: dir.appendingPathComponent("spaces.json"))
        let first = ProjectsFile.load(from: url)
        expect(first?.projects.count == 3, "\(String(describing: first?.projects.map(\.folder)))")
        expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("spaces.migrated.json").path)
               && !FileManager.default.fileExists(atPath: dir.appendingPathComponent("spaces.json").path))
        expect(ProjectsFile.load(from: url) == first, "the second read is the saved file")
    }),
]
