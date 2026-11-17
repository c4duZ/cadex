import AppKit
import Checks
@testable import Projects
import Tabs

// Tests of the projects feature (what were the spaces, plan 27). Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

@MainActor
func eventually(_ body: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if body() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

func tempDir() -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cadex-projects-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

func tempFile() -> URL { tempDir().appendingPathComponent("projects.json") }

@MainActor
func controller(_ url: URL, window: NSWindow) -> ProjectsController {
    ProjectsController(fileURL: url) { TabsController(window: window) }
}

@MainActor
func window() -> NSWindow {
    NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
}

// The shell reports the real path: /tmp is /private/tmp.
let tmp = String(cString: realpath(NSTemporaryDirectory(), nil))

/// Two project folders, real paths (each its own repository).
func folders() -> (String, String) {
    let a = tempDir(), b = tempDir()
    for dir in [a, b] { try? FileManager.default.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true) }
    return (String(cString: realpath(a.path, nil)), String(cString: realpath(b.path, nil)))
}

let exitCode = await Checks.run([
    ("a first launch has the launch folder's project, named after it, with a terminal in it", {
        let (a, _) = folders()
        let projects = controller(tempFile(), window: window())
        var shown: TabsController?
        projects.onSwitch = { shown = $0 }
        projects.start(folder: a) { _ in nil }
        expect(projects.projects.count == 1 && projects.activeName == (a as NSString).lastPathComponent && projects.activeFolder == a)
        expect(shown === projects.active && projects.active?.isShown == true && projects.active?.count == 1)
        projects.projects.forEach { $0.tabs.closeAll() }
    }),
    ("a passing window's projects (no file) start fresh and save nothing", {
        let (a, b) = folders()
        let projects = ProjectsController(fileURL: nil) { TabsController(window: window()) }
        projects.start(folder: a) { _ in nil }
        projects.open(folder: b)
        projects.saveNow()
        expect(projects.projects.count == 2 && projects.savedFile == nil)
        projects.projects.forEach { $0.tabs.closeAll() }
    }),
    ("projects saved and restored come back the same, with the active one", {
        let url = tempFile()
        let saved = SavedProjects(projects: [
            .init(name: "api", folder: tmp, tabs: TabsSnapshot(items: [.terminal(title: nil, layout: .pane(folder: tmp), focus: 0, color: "red")], active: 0),
                  color: "blue"),
            .init(name: "site", folder: "/", tabs: TabsSnapshot(items: [
                .terminal(title: "logs", layout: .split(sideBySide: false, ratio: 0.7, first: .pane(folder: "/"), second: .pane(folder: tmp)), focus: 1),
                .document(identity: "/nota.md"),
            ], active: 0)),
        ], active: 1)
        try? ProjectsFile.save(saved, to: url)
        let projects = controller(url, window: window())
        var reopened: [String] = []
        projects.start(folder: "/") { reopened.append($0); return nil }
        expect(reopened == ["/nota.md"] && projects.activeName == "site", "\(reopened) \(projects.activeName)")
        expect(projects.projects[0].tabs.isShown == false && projects.projects[1].tabs.isShown)
        var expected = saved
        expected.projects[1].tabs.items.removeLast()
        let same = await eventually { projects.saved == expected }
        expect(same, "\(projects.saved)")

        projects.saveNow()
        let again = controller(url, window: window())
        again.start(folder: "/") { _ in nil }
        let restored = await eventually { again.saved == expected }
        expect(restored, "\(again.saved)")
        (projects.projects + again.projects).forEach { $0.tabs.closeAll() }
    }),
    ("a corrupted file is moved aside and the app starts fresh", {
        let url = tempFile()
        try? Data("{ isto não é json".utf8).write(to: url)
        let projects = controller(url, window: window())
        projects.start(folder: tmp) { _ in nil }
        expect(projects.projects.count == 1 && projects.active?.count == 1)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        expect(files.contains { $0.hasPrefix("projects.bad-") } && !files.contains("projects.json"), "\(files)")
        projects.projects.forEach { $0.tabs.closeAll() }
    }),
    ("open a folder: its project, or the one already open; next, rename (empty: the folder's name), close; the last stays", {
        let (a, b) = folders()
        let projects = controller(tempFile(), window: window())
        projects.start(folder: a) { _ in nil }
        projects.open(folder: b)
        expect(projects.projects.count == 2 && projects.activeIndex == 1 && projects.activeFolder == b)
        projects.open(folder: a + "/src")
        expect(projects.projects.count == 2 && projects.activeIndex == 0, "a folder inside a project's repository goes to it")
        projects.rename(at: 0, to: "  api ")
        expect(projects.activeName == "api")
        projects.rename(at: 0, to: "   ")
        expect(projects.activeName == (a as NSString).lastPathComponent, "empty: the folder's name")
        projects.selectNext(step: 1)
        expect(projects.activeIndex == 1 && projects.projects[1].tabs.isShown && !projects.projects[0].tabs.isShown)
        projects.closeActive()
        expect(projects.projects.count == 1 && projects.activeFolder == a && projects.active?.isShown == true)
        projects.closeActive()
        expect(projects.projects.count == 1)
        projects.projects.forEach { $0.tabs.closeAll() }
    }),
    ("the spaces of before become projects once: by their folder, two of one folder as one, the old file kept beside", {
        let (a, b) = folders()
        let dir = tempDir()
        let legacy = """
        {"version": 1, "active": 2, "folder": "\(a)", "spaces": [
          {"name": "api", "color": "blue", "tabs": {"items": [{"terminal": {"layout": {"pane": {"folder": "\(a)/src"}}, "focus": 0}}], "active": 0}},
          {"name": "site", "tabs": {"items": [{"terminal": {"layout": {"pane": {"folder": "\(b)"}}, "focus": 0}}], "active": 0}},
          {"name": "api 2", "tabs": {"items": [{"terminal": {"layout": {"pane": {"folder": "\(a)"}}, "focus": 0}}], "active": 0}}
        ]}
        """
        try? Data(legacy.utf8).write(to: dir.appendingPathComponent("spaces.json"))
        let saved = ProjectsFile.load(from: dir.appendingPathComponent("projects.json"))
        expect(saved?.projects.map(\.folder) == [a, b], "\(String(describing: saved?.projects.map(\.folder)))")
        expect(saved?.projects.first?.tabs.items.count == 2 && saved?.projects.first?.color == "blue", "the two spaces of one folder, together")
        expect(saved?.active == 0, "the active space's project is the active one")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        expect(files.contains("projects.json") && files.contains("spaces.migrated.json") && !files.contains("spaces.json"), "\(files)")
    }),
    ("a worktree's folder belongs to its main repository", {
        let (a, _) = folders()
        let worktree = tempDir()
        try? Data("gitdir: \(a)/.git/worktrees/fix\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        expect(ProjectsFile.repositoryRoot(worktree.path + "/deep") == a, ProjectsFile.repositoryRoot(worktree.path))
        expect(ProjectsFile.repositoryRoot(a + "/x/y") == a)
        // git 2.48's relative gitdir, from the worktree's folder.
        let sibling = URL(fileURLWithPath: a).deletingLastPathComponent().appendingPathComponent("rel-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try? Data("gitdir: ../\((a as NSString).lastPathComponent)/.git/worktrees/rel\n".utf8).write(to: sibling.appendingPathComponent(".git"))
        expect(ProjectsFile.repositoryRoot(sibling.path) == a, ProjectsFile.repositoryRoot(sibling.path))
    }),
])
exit(exitCode)
