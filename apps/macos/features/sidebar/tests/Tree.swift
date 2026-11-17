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
]
