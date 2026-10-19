import AppKit
import CoreGraphics
import Checks
@testable import Tabs

// Tests of the tabs feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("splitting puts the new pane after the old one, half and half", {
        let tree = PaneTree.leaf(1).splitting(1, axis: .horizontal, newPane: 2)
        expect(tree == .split(.horizontal, .leaf(1), .leaf(2), ratio: 0.5))
        let frames = tree.frames(in: CGRect(x: 0, y: 0, width: 201, height: 100), gap: 1)
        expect(frames[1] == CGRect(x: 0, y: 0, width: 100, height: 100), "\(frames)")
        expect(frames[2] == CGRect(x: 101, y: 0, width: 100, height: 100), "\(frames)")
    }),
    ("closing a pane gives its space to the sibling", {
        // 1 | (2 over 3); closing 2 leaves 1 | 3.
        let tree = PaneTree.leaf(1)
            .splitting(1, axis: .horizontal, newPane: 2)
            .splitting(2, axis: .vertical, newPane: 3)
        expect(tree.leaves == [1, 2, 3])
        expect(tree.removing(2) == .split(.horizontal, .leaf(1), .leaf(3), ratio: 0.5))
        expect(tree.removing(1) == .split(.vertical, .leaf(2), .leaf(3), ratio: 0.5))
        expect(PaneTree.leaf(1).removing(1) == nil)
    }),
    ("⌘] and ⌘[ go through the panes in reading order, wrapping", {
        let tree = PaneTree.leaf(1).splitting(1, axis: .horizontal, newPane: 2).splitting(2, axis: .vertical, newPane: 3)
        expect(tree.cycling(from: 1, by: 1) == 2)
        expect(tree.cycling(from: 3, by: 1) == 1)
        expect(tree.cycling(from: 1, by: -1) == 3)
    }),
    ("⌘⌥ arrows go to the pane on that side", {
        // 1 | (2 over 3)
        let tree = PaneTree.leaf(1).splitting(1, axis: .horizontal, newPane: 2).splitting(2, axis: .vertical, newPane: 3)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 200)
        expect(tree.neighbor(of: 1, .right, in: rect) != nil)
        expect(tree.neighbor(of: 2, .down, in: rect) == 3)
        expect(tree.neighbor(of: 3, .up, in: rect) == 2)
        expect(tree.neighbor(of: 3, .left, in: rect) == 1)
        expect(tree.neighbor(of: 1, .left, in: rect) == nil)
    }),
    ("dragging a divider sets the ratio of that split only", {
        let tree = PaneTree.leaf(1).splitting(1, axis: .horizontal, newPane: 2).splitting(2, axis: .vertical, newPane: 3)
        let moved = tree.settingRatio(0.3, at: [true])
        expect(moved == .split(.horizontal, .leaf(1), .split(.vertical, .leaf(2), .leaf(3), ratio: 0.3), ratio: 0.5))
        expect(tree.settingRatio(0.7, at: []) == .split(.horizontal, .leaf(1), .split(.vertical, .leaf(2), .leaf(3), ratio: 0.5), ratio: 0.7))
    }),
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
