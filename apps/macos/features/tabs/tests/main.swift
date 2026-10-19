import AppKit
import Checks
@testable import Tabs

// Tests of the tabs feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("a new tab goes right after the active one and becomes active", {
        var list = TabList()
        list.insert(1)
        list.insert(2)
        list.select(1)
        list.insert(3)
        expect(list.order == [1, 3, 2], "\(list.order)")
        expect(list.active == 3)
    }),
    ("positions for ⌘1 to ⌘9", {
        var list = TabList()
        [1, 2, 3].forEach { list.insert($0) }
        expect(list.id(atPosition: 1) == 1 && list.id(atPosition: 3) == 3)
        expect(list.id(atPosition: 5) == nil && list.id(atPosition: 0) == nil)
    }),
    ("Ctrl+Tab goes back to the tab used before", {
        var list = TabList()
        [1, 2, 3].forEach { list.insert($0) }
        list.select(1)
        expect(list.previouslyUsed == 3, "\(list.recent)")
        expect(list.leastRecentlyUsed == 2, "\(list.recent)")
    }),
    ("closing the active tab activates the one used before it", {
        var list = TabList()
        [1, 2, 3].forEach { list.insert($0) }
        list.select(1)
        list.select(3)
        list.remove(3)
        expect(list.active == 1, "\(String(describing: list.active))")
        list.remove(1)
        list.remove(2)
        expect(list.active == nil && list.order.isEmpty)
    }),
    ("dragging moves a tab to a new position", {
        var list = TabList()
        [1, 2, 3].forEach { list.insert($0) }
        list.move(1, to: 2)
        expect(list.order == [2, 3, 1], "\(list.order)")
        list.move(1, to: -5)
        expect(list.order == [1, 2, 3], "\(list.order)")
    }),
    ("the folder gives the tab title, home is ~", {
        expect(folderTitle("/Users/cadu/projeto", home: "/Users/cadu") == "projeto")
        expect(folderTitle("/Users/cadu", home: "/Users/cadu") == "~")
        expect(folderTitle(nil, home: "/Users/cadu") == "~")
        expect(folderTitle("/", home: "/Users/cadu") == "/")
    }),
])
exit(exitCode)
