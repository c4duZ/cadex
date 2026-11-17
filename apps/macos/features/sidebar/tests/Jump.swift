import Checks
@testable import Sidebar
import StateGlyph

// ⌘J's rows (plan 29 phase C): the groups in the mockup's order, what it says of each, the filter.

let jumpChecks: [(name: String, body: Checks.Body)] = [
    ("⌘J: what needs you, then what finished, then what works; idle work left out; a project's agent too", {
        var asks = WorkTreeTask(id: "/w/a", name: "perf-window", state: .needs)
        asks.waiting = "approve Bash"
        var done = WorkTreeTask(id: "/w/b", name: "bell-cards", state: .done)
        done.comment = "PR #41"
        let works = WorkTreeTask(id: "/w/c", name: "orchestration-e", state: .working,
                                 terminals: [WorkTreeTerminal(id: "t1", title: "Claude", state: .working, note: "wiring the wake check")])
        let idle = WorkTreeTask(id: "/w/d", name: "old", state: .idle)
        var agent = WorkTreeTerminal(id: "t2", title: "Claude", state: .needs)
        agent.waiting = "a question"
        let shell = WorkTreeTerminal(id: "t3", title: "zsh")
        let project = WorkTreeProject(id: "/w", name: "cadex", branch: "main", tasks: [works, idle, done, asks], terminals: [shell, agent])
        let rows = JumpRow.rows([project])
        expect(rows.map(\.name) == ["perf-window", "Claude", "bell-cards", "orchestration-e"], "\(rows.map(\.name))")
        expect(rows.map(\.detail) == ["cadex · approve Bash", "cadex · a question", "cadex · PR #41", "cadex · wiring the wake check"], "\(rows.map(\.detail))")
        expect(rows.map(\.group) == [0, 0, 1, 2])
        expect(rows[1].pick == .terminal("t2") && rows[0].pick == .task("/w/a"))
        expect(rows.filter { $0.matches("wake cadex") }.map(\.name) == ["orchestration-e"])
    }),
]
