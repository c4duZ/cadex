import AppKit
import Checks
import Strings
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

let mainTests: [(name: String, body: Checks.Body)] = [
    ("the project page's words: a conversation's dot, when, the merges, the remote", {
        let now = Date()
        expect(ProjectPageWords.state(live: true, working: true, asking: false, updated: now, now: now) == .working)
        expect(ProjectPageWords.state(live: true, working: false, asking: true, updated: now, now: now) == .needs)
        expect(ProjectPageWords.state(live: false, working: false, asking: false, updated: now - 3600, now: now) == .idle, "ended is gray, however recent")
        expect(ProjectPageWords.state(live: false, working: false, asking: false, updated: now - 3 * 86400, now: now) == .idle)
        expect(ProjectPageWords.when(now - 240, now: now) == "4m" && ProjectPageWords.when(now, now: now) == "now")
        expect(ProjectPageWords.mergedName("Merge pull request #41 from c4duZ/bell-cards") == "bell-cards")
        expect(ProjectPageWords.mergedName("Merge branch 'hero-images'") == "hero-images")
        expect(ProjectPageWords.remote("git@github.com:c4duZ/cadex.git") == "github.com/c4duZ/cadex")
        expect(ProjectPageWords.remote("https://github.com/c4duZ/cadex.git") == "github.com/c4duZ/cadex")
        expect(ProjectPageWords.tasksNote(working: 1, needYou: 1) == "1 working · 1 needs you")
        expect(ProjectPageWords.usd(6.4) == "US$ 6.40")
    }),
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
        // A file of before plan 36 has no "pinned": its projects come back pinned.
        for index in expected.projects.indices { expected.projects[index].pinned = true }
        // Without the recent ones, which carry the time of now.
        func withoutRecent(_ saved: SavedProjects) -> SavedProjects { var copy = saved; copy.recent = nil; return copy }
        let same = await eventually { withoutRecent(projects.saved) == expected }
        expect(same, "\(projects.saved)")

        projects.saveNow()
        let again = controller(url, window: window())
        again.start(folder: "/") { _ in nil }
        let restored = await eventually { withoutRecent(again.saved) == expected }
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
    ("open a folder: its project, or the one already open; next, rename (empty: the folder's name), close; the last leaves none", {
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
        var none = 0
        projects.onNone = { none += 1 }
        projects.closeActive()
        expect(projects.projects.isEmpty && projects.active == nil && none == 1, "the last one closed: the home screen (plan 29)")
        expect(projects.recent.map(\.folder) == [a, b], "the recent ones, the latest first: \(projects.recent.map(\.folder))")
    }),
    ("from the Dock with nothing saved: no project; the recent ones and an empty list come back from the file", {
        let (a, _) = folders()
        let file = tempFile()
        var none = 0
        let first = controller(file, window: window())
        first.onNone = { none += 1 }
        first.start(folder: a, openFolder: false) { _ in nil }
        expect(first.projects.isEmpty && none == 1)
        first.open(folder: a)
        first.closeActive()
        first.saveNow()
        let again = controller(file, window: window())
        again.start(folder: a, openFolder: false) { _ in nil }
        expect(again.projects.isEmpty && again.recent.map(\.folder) == [a], "\(again.recent)")
        expect(FileManager.default.fileExists(atPath: file.path), "an empty list is a good file, not moved aside")
    }),
    ("a project closed comes back from the recent ones with the tabs it had", {
        let (a, b) = folders()
        let projects = controller(tempFile(), window: window())
        projects.start(folder: a) { _ in nil }
        projects.active?.newTab(cwd: a)
        expect(projects.active?.count == 2)
        projects.open(folder: b)
        projects.select(0)
        projects.closeActive()
        // b shows now and goes first; a stays in the list with its two tabs.
        let kept = projects.recent.first { $0.folder == a }
        expect(projects.projects.count == 1 && kept?.tabs?.items.count == 2, "\(String(describing: kept?.tabs?.items.count))")
        projects.open(folder: a)
        expect(projects.activeFolder == a && projects.active?.count == 2, "\(String(describing: projects.active?.count))")
        projects.projects.forEach { $0.tabs.closeAll() }
    }),
    ("the memory off in a project (plan 35 I): saved, told, kept when the project closes, and read from a file of before as none", {
        let (a, b) = folders()
        let file = tempFile()
        let projects = controller(file, window: window())
        projects.start(folder: a) { _ in nil }
        var told: [Set<String>] = []
        projects.onMemoryOffChange = { told.append($0) }
        projects.setMemoryOff(true, for: a)
        projects.setMemoryOff(true, for: a)
        expect(projects.isMemoryOff(a) && !projects.isMemoryOff(b) && told == [[a]], "\(told)")
        projects.open(folder: b)
        projects.select(0)
        projects.closeActive()
        projects.saveNow()
        expect(ProjectsFile.load(from: file)?.memoryOff == [a], "kept with the project closed")
        let again = controller(file, window: window())
        again.start(folder: b) { _ in nil }
        expect(again.isMemoryOff(a), "restored")
        again.setMemoryOff(false, for: a)
        again.saveNow()
        expect(ProjectsFile.load(from: file)?.memoryOff == nil, "none off: nothing written")
        let before = #"{"version":1,"projects":[],"active":0}"#
        try? Data(before.utf8).write(to: file)
        expect(ProjectsFile.load(from: file)?.memoryOff == nil, "a file of before reads")
        (projects.projects + again.projects).forEach { $0.tabs.closeAll() }
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
    ("a project's card counts its tasks, sessions and memories, one in the singular (plan 34 B)", { @MainActor in
        let card = ProjectCard(folder: "/r", name: "r", place: "~/r · main", tasks: 2, sessions: 1, memories: 0, status: "no session yet", state: nil)
        let text = ProjectsListDocument.stats(card).string
        expect(text.contains("2 " + T("tasks", "tarefas")) && text.contains("1 " + T("session", "sessão")) && text.contains("0 " + T("memories", "memórias")), text)
    }),
]
let exitCode = await Checks.run(mainTests + sectionTests + lookTests)
exit(exitCode)
