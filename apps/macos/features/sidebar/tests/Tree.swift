import AppKit
import Checks
@testable import Sidebar
import StateGlyph

// sidebar.find from the work's model (plan 36: the tree's view went; the model stays for ⌘J and this).
@MainActor
let treeChecks: [(name: String, body: Checks.Body)] = [
    ("sidebar.find lists the projects, tasks and terminals by name; picked, it says which", {
        var picked: [WorkTreePick] = []
        let task = WorkTreeTask(id: "/r.worktrees/fix", name: "fix", state: .working, agent: "Claude · bkdg",
                                terminals: [WorkTreeTerminal(id: "t2", title: "claude", state: .working)])
        let source = WorkTreeFindSource(projects: [WorkTreeProject(id: "/r", name: "r", branch: "main", tasks: [task],
                                                                   terminals: [WorkTreeTerminal(id: "t1", title: "zsh")])]) { picked.append($0) }
        expect(source.items("").map(\.title) == ["r", "fix", "claude", "zsh"], "\(source.items("").map(\.title))")
        expect(source.items("r fix").map(\.title) == ["fix", "claude"], "the words in the title or the place")
        source.choose(source.items("fix")[0])
        source.choose(source.items("zsh")[0])
        expect(picked == [.task("/r.worktrees/fix"), .terminal("t1")], "\(picked)")
    }),
]
