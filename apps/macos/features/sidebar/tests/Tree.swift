import AppKit
import Checks
@testable import Sidebar

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
    ("a picture of the tree with a task in full (CADEX_SNAPSHOT_DIR: tree.png)", {
        guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
        let tree = WorkTreeView(newTaskShortcut: "⌘N") { _ in }
        tree.frame = NSRect(x: 0, y: 0, width: 292, height: 520)
        var fix = WorkTreeTask(id: "/r.worktrees/orchestration-e", name: "orchestration-e", state: .working, unread: true, agent: "Claude · bkdg",
                               terminals: [WorkTreeTerminal(id: "t2", title: "Claude", state: .working, note: "Opus"),
                                           WorkTreeTerminal(id: "t3", title: "npm run dev", state: .done, note: ":5173")])
        fix.added = 312
        fix.removed = 41
        fix.age = "4m"
        var bell = WorkTreeTask(id: "/r.worktrees/bell-cards", name: "bell-cards", state: .needs, agent: "Codex · work")
        bell.waiting = "waits for a permission"
        bell.age = "1m"
        let done = WorkTreeTask(id: "/r.worktrees/perf", name: "perf-subagent-window", state: .done, agent: "Claude · bhband")
        tree.show([WorkTreeProject(id: "/r", name: "cadex", branch: "main", tasks: [fix, bell, done], terminals: [WorkTreeTerminal(id: "t1", title: "zsh")])],
                  chosen: .task(fix.id))
        let window = NSWindow(contentRect: tree.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = tree
        tree.layoutSubtreeIfNeeded()
        guard let bitmap = tree.bitmapImageRepForCachingDisplay(in: tree.bounds) else { return }
        tree.cacheDisplay(in: tree.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/tree.png"))
    }),
]
