import AppKit
import Checks
@testable import Sidebar
import StateGlyph

@MainActor
let treeChecks: [(name: String, body: Checks.Body)] = [
    ("the tree: each project with its tasks and terminals, the chosen task's terminals under it, Add project last", {
        var ran: [String] = []
        var picked: [WorkTreePick] = []
        let tree = WorkTreeView(newTaskShortcut: nil) { ran.append($0) }
        tree.onPick = { picked.append($0) }
        tree.frame = NSRect(x: 0, y: 0, width: 292, height: 600)
        let task = WorkTreeTask(id: "/r.worktrees/fix", name: "fix", state: .working, agent: "Claude · bkdg",
                                terminals: [WorkTreeTerminal(id: "t2", title: "claude", state: .working)])
        tree.show([WorkTreeProject(id: "/r", name: "r", branch: "main", tasks: [task], terminals: [WorkTreeTerminal(id: "t1", title: "zsh")])],
                  chosen: .task("/r.worktrees/fix"))
        expect(tree.rowTitles == ["r", "fix", "claude", "zsh", "Add project"], "\(tree.rowTitles)")
        tree.show(tree.projects, chosen: .terminal("t1"))
        expect(tree.rowTitles == ["r", "fix", "zsh", "Add project"], "a task not chosen hides its terminals: \(tree.rowTitles)")
    }),
    ("the tree with the mockup's own data, at its size (CADEX_SNAPSHOT_DIR: tree.png), to lay over Sidebar.dc.html", {
        guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
        let tree = WorkTreeView(newTaskShortcut: "⌘N") { _ in }
        tree.frame = NSRect(x: 0, y: 0, width: 292, height: 826)
        tree.automationsDetail = "2 on · next 09:00"
        func task(_ name: String, _ state: GlyphState, _ agent: String, _ added: Int, _ removed: Int, _ age: String,
                  unread: Bool = false, waiting: String = "", terminals: [WorkTreeTerminal] = []) -> WorkTreeTask {
            var task = WorkTreeTask(id: "/w/" + name, name: name, state: state, unread: unread, agent: agent, terminals: terminals)
            task.added = added
            task.removed = removed
            task.age = age
            task.waiting = waiting
            return task
        }
        let cadex = WorkTreeProject(id: "/cadex", name: "cadex", branch: "main", tasks: [
            task("orchestration-e", .working, "Claude · bkdg", 214, 38, "4m", terminals: [
                WorkTreeTerminal(id: "t1", title: "Claude", state: .working, note: "Opus"),
                WorkTreeTerminal(id: "t2", title: "npm run dev", state: .done, note: ":5173"),
                WorkTreeTerminal(id: "t3", title: "make macos-test", state: .working, note: "38s")]),
            task("perf-subagent-window", .needs, "Claude · bhband", 12, 6, "1m", unread: true, waiting: "approve Bash"),
            task("bell-cards", .done, "Codex", 40, 9, "22m", unread: true),
            task("windows-port-tabs", .idle, "Claude · bkdg", 0, 0, "2d"),
        ])
        let site = WorkTreeProject(id: "/site", name: "bhband-site", branch: "main", tasks: [
            task("checkout-copy", .needs, "Claude · bhband", 31, 2, "now", unread: true, waiting: "question"),
            task("hero-images", .failed, "Claude · bhband", 3, 0, "1h"),
        ])
        tree.show([cadex, site], chosen: .task("/w/orchestration-e"))
        let window = NSWindow(contentRect: tree.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = tree
        tree.layoutSubtreeIfNeeded()
        guard let bitmap = tree.bitmapImageRepForCachingDisplay(in: tree.bounds) else { return }
        tree.cacheDisplay(in: tree.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/tree.png"))
    }),
]
