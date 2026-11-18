import AppKit
import Checks
@testable import Tabs

// The bar's places to go (plan 36 phase D): a task's item in the project's bar goes to its tabs and
// "‹ project" back; the tabs that do not fit go under "» N", the active one always shown.

@MainActor
let groupChecks: [(name: String, body: Checks.Body)] = [
    ("a task's item goes to its tabs and \"‹ project\" back; ⌘1… count the shown", {
        let tabs = makeTabs()
        tabs.groupOf = { folder in (folder ?? "").hasPrefix("/r/task") ? "/r/task" : "" }
        tabs.extrasOf = { group in
            group == "" ? [TabsExtra(title: "task  ›", command: "", identity: "task:/r/task", group: "/r/task", state: .working)]
                : [TabsExtra(title: "‹ r", command: "", identity: "back:", group: "", leading: true)]
        }
        tabs.open(FakeDocument("/r/a.txt"))
        tabs.open(FakeDocument("/r/task/b.txt"))
        tabs.open(FakeDocument("/r/c.txt"))
        expect(tabs.bar.items.map(\.title) == ["a.txt", "c.txt", "task  ›"], "\(tabs.bar.items.map(\.title))")
        expect(tabs.bar.items.last?.state == .working, "the task's state before its name")
        tabs.bar.onSelect?(tabs.bar.items.last!.id)
        expect(tabs.bar.items.map(\.title) == ["‹ r", "b.txt"], "in the task: \(tabs.bar.items.map(\.title))")
        tabs.bar.onSelect?(tabs.bar.items.first!.id)
        expect(tabs.activeDocument?.identity == "/r/c.txt", "back to the project's last used: \(tabs.activeDocument?.identity ?? "")")
    }),
    ("tabs that do not fit go under \"» N\", the active one kept", {
        let tabs = makeTabs()
        for name in ["a", "b", "c", "d", "e"] { tabs.open(FakeDocument("/x/\(name).txt")) }
        tabs.bar.room = 160
        let titles = tabs.bar.items.map(\.title)
        expect(titles.last == "» \(tabs.overflowHidden.count)" && !tabs.overflowHidden.isEmpty, "\(titles)")
        expect(titles.contains("e.txt"), "the active one stays in the bar: \(titles)")
        tabs.bar.room = 1200
        expect(tabs.overflowHidden.isEmpty && !tabs.bar.items.contains { $0.title.hasPrefix("»") }, "wide again: all shown")
    }),
]
