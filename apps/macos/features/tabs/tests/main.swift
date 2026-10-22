import AppKit
import CoreGraphics
import Checks
@testable import Tabs
import Icons
import Terminal

// Tests of the tabs feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

/// A document that is nothing but its identity, for the tabs' rules.
@MainActor
final class FakeDocument: TabDocument {
    let view = NSView()
    let identity: String
    var title: String { (identity as NSString).lastPathComponent }
    var hasUnsavedChanges = false
    var onChange: (() -> Void)?
    var closed = false
    /// What confirmClose answers: true closes, as "Descartar" would.
    var closes = true

    init(_ identity: String) { self.identity = identity }

    func focus() {}
    func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { if closes { close() } }
    func close() { closed = true }
}

@MainActor
func makeTabs() -> TabsController {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    let tabs = TabsController(window: window)
    tabs.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 600)
    return tabs
}

@MainActor
func eventually(_ body: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if body() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

let exitCode = await Checks.run([
    ("a picked element goes to an agent first, then any running program, never an idle shell", {
        let order = AgentCandidate.order([
            AgentCandidate(title: "~/painel", running: false),
            AgentCandidate(title: "npm run dev", running: true),
            AgentCandidate(title: "✳ Ajustar o botão", running: true),
            AgentCandidate(title: "claude", running: false),
            AgentCandidate(title: "Codex", running: true),
        ])
        expect(order == [2, 4, 1], "\(order)")
    }),
    ("a pick goes to the terminal clicked last, in any tab; never clicked ones after", {
        // Terminals 1, 2, 3 in the tabs' order; 3 was clicked, then the
        // preview, then 1, then the preview again: 1 first, then 3.
        expect(AgentCandidate.recentFirst([1, 2, 3], recent: [1, 3]) == [1, 3, 2])
        expect(AgentCandidate.recentFirst([1, 2], recent: [9, 2]) == [2, 1], "a closed terminal is skipped")
        expect(AgentCandidate.recentFirst([1, 2], recent: []) == [1, 2])
    }),
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
    ("a saved layout comes back with the same splits, ratios and folders", {
        let tree = PaneTree.leaf(1).splitting(1, axis: .horizontal, newPane: 2).splitting(2, axis: .vertical, newPane: 3)
            .settingRatio(0.3, at: [])
        let folders = [1: "/a", 2: "/b", 3: "/c"]
        let layout = tree.snapshot { .pane(folder: folders[$0]!) }
        expect(layout.folders == ["/a", "/b", "/c"])
        let snapshot = TabsSnapshot(items: [.terminal(title: "api", layout: layout, focus: 2), .document(identity: "/x.md")], active: 1)
        let data = try! JSONEncoder().encode(snapshot)
        let back = try! JSONDecoder().decode(TabsSnapshot.self, from: data)
        expect(back == snapshot, String(decoding: data, as: UTF8.self))
        var next = 10
        let rebuilt = PaneTree.from(layout) { defer { next += 1 }; return next }
        expect(rebuilt == .split(.horizontal, .leaf(10), .split(.vertical, .leaf(11), .leaf(12), ratio: 0.5), ratio: 0.3), "\(rebuilt)")
    }),
    ("tabs saved and restored come back the same, documents through the app", {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let first = TabsController(window: window)
        // realpath, as the shell reports it: resolvingSymlinksInPath drops /private.
        let tmp = String(cString: realpath(NSTemporaryDirectory(), nil))
        let saved = TabsSnapshot(items: [
            .terminal(title: nil, layout: .pane(folder: tmp), focus: 0),
            .terminal(title: "dois", layout: .split(sideBySide: true, ratio: 0.4, first: .pane(folder: "/"), second: .pane(folder: tmp)), focus: 1),
            .document(identity: "/sumiu.txt"),
        ], active: 1)
        var asked: [String] = []
        first.restore(saved) { asked.append($0); return nil }
        expect(asked == ["/sumiu.txt"] && first.count == 2, "\(asked) \(first.count)")
        // The document could not be reopened: the rest stays, the active one too.
        var expected = saved
        expected.items.removeLast()
        let ok = await eventually { first.snapshot() == expected }
        expect(ok, "\(first.snapshot())")
        first.closeAll()
        expect(first.count == 0)
    }),
    ("a document tab's icon comes from what it shows", {
        expect(TabsController.tabIcon(for: "/repo/README.md").0 == .fileMd)
        expect(TabsController.tabIcon(for: "/repo/App.swift").1 == .systemOrange)
        expect(TabsController.tabIcon(for: "diff:work:/repo/core/build.zig").0 == .fileCode)
        expect(TabsController.tabIcon(for: "history:/repo").0 == .gitCommit)
        expect(TabsController.tabIcon(for: "preview:http://localhost:3000").0 == .globe)
    }),
    ("the middle button closes the tab under it, on release over the same tab", {
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 400, height: 30))
        bar.items = [.init(id: 1, title: "um", active: true), .init(id: 2, title: "dois", active: false)]
        var closed: [Int] = []
        bar.onClose = { closed.append($0) }
        // Built in memory and handed to the view: never posted, so the
        // owner's pointer and apps are untouched.
        func middle(_ type: CGEventType, x: CGFloat) -> NSEvent {
            let cg = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: 10), mouseButton: .center)!
            return NSEvent(cgEvent: cg)!
        }
        bar.otherMouseDown(with: middle(.otherMouseDown, x: 20))
        bar.otherMouseUp(with: middle(.otherMouseUp, x: 20))
        expect(closed == [1], "\(closed)")
        // Pressed on one tab, released on another: nothing closes.
        bar.otherMouseDown(with: middle(.otherMouseDown, x: 20))
        bar.otherMouseUp(with: middle(.otherMouseUp, x: 390))
        expect(closed == [1], "\(closed)")
    }),
    ("panes in a row share the space equally, nested splits too", {
        // 1 | 2 | 3 by splitting the last pane each time.
        let three = PaneTree.leaf(1).splitting(1, axis: .horizontal, newPane: 2)
            .splitting(2, axis: .horizontal, newPane: 3).balanced()
        let frames = three.frames(in: CGRect(x: 0, y: 0, width: 300, height: 100))
        expect(frames.values.allSatisfy { abs($0.width - 100) <= 1 }, "\(frames)")
        // 1 | (2 over 3): the column counts once across, its two halves split down.
        let mixed = PaneTree.leaf(1).splitting(1, axis: .horizontal, newPane: 2)
            .splitting(2, axis: .vertical, newPane: 3).balanced()
        let f = mixed.frames(in: CGRect(x: 0, y: 0, width: 200, height: 100))
        expect(f[1]?.width == 100 && f[2]?.width == 100 && f[2]?.height == 50, "\(f)")
        // Closing one of three gives the other two half each.
        let two = three.removing(2)!.balanced()
        expect(two.frames(in: CGRect(x: 0, y: 0, width: 300, height: 100)).values.allSatisfy { $0.width == 150 })
    }),
    ("a document opens in a tab of its own; its identity again goes back to it", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        let a = FakeDocument("/repo/a.md")
        tabs.open(a)
        expect(tabs.count == 2 && tabs.activeDocument === a && tabs.activeTerminal == nil)
        tabs.select(position: 1)
        expect(tabs.activeDocument == nil && tabs.activeTerminal != nil)
        tabs.open(FakeDocument("/repo/a.md"))
        expect(tabs.count == 2 && tabs.activeDocument === a, "\(tabs.count)")
        tabs.closeAll()
    }),
    ("the focused pane decides the active terminal or document, in any tab", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        let tab = tabs.activeTab!
        let b = FakeDocument("/repo/b.swift")
        tabs.split(tab, axis: .horizontal, with: .document(b))
        expect(tabs.activeDocument === b && tabs.activeTerminal == nil && tabs.activePaneCount == 2)
        tabs.focusPane(step: 1)
        expect(tabs.activeDocument == nil && tabs.activeTerminal != nil)
        tabs.newTab(cwd: "/")
        expect(tabs.document(identity: "/repo/b.swift") === b && tabs.allDocuments.count == 1)
        // A new terminal beside a document starts in the document's folder.
        tabs.open(b)
        expect(tabs.activeTab === tab && tabs.activeDocument === b)
        expect(tab.focused.folder == "/repo")
        tabs.closeAll()
        expect(b.closed)
    }),
    ("a plan 7 spaces.json comes back the same: a document tab is a tab of one pane", {
        let json = """
        {"items":[{"terminal":{"layout":{"pane":{"folder":"/"}},"focus":0}},{"document":{"identity":"/x.md"}}],"active":1}
        """
        let old = try! JSONDecoder().decode(TabsSnapshot.self, from: Data(json.utf8))
        let tabs = makeTabs()
        tabs.restore(old) { FakeDocument($0) }
        expect(tabs.count == 2 && tabs.activeDocument?.identity == "/x.md")
        let ok = await eventually {
            tabs.snapshot() == TabsSnapshot(items: [
                .terminal(title: nil, layout: .pane(folder: "/"), focus: 0),
                .terminal(title: nil, layout: .document(identity: "/x.md"), focus: 0),
            ], active: 1)
        }
        expect(ok, "\(tabs.snapshot())")
        tabs.closeAll()
    }),
    ("a terminal and a document side by side come back side by side; a gone document becomes a terminal", {
        let tmp = String(cString: realpath(NSTemporaryDirectory(), nil))
        let layout = TabsSnapshot.Layout.split(sideBySide: true, ratio: 0.5, first: .pane(folder: "/"), second: .document(identity: tmp + "/a.md"))
        let saved = TabsSnapshot(items: [.terminal(title: nil, layout: layout, focus: 1)], active: 0)
        let tabs = makeTabs()
        tabs.restore(saved) { FakeDocument($0) }
        let same = await eventually { tabs.snapshot() == saved }
        expect(same && tabs.activeDocument?.identity == tmp + "/a.md", "\(tabs.snapshot())")
        let gone = makeTabs()
        gone.restore(saved) { _ in nil }
        let asTerminal = TabsSnapshot.Layout.split(sideBySide: true, ratio: 0.5, first: .pane(folder: "/"), second: .pane(folder: tmp))
        let ok = await eventually { gone.snapshot().items == [.terminal(title: nil, layout: asTerminal, focus: 1)] }
        expect(ok, "\(gone.snapshot())")
        tabs.closeAll()
        gone.closeAll()
    }),
    ("beside: a split to the right first, then the document pane is reused, never stacked", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.layoutSubtreeIfNeeded()
        let a = FakeDocument("/r/a.md"), b = FakeDocument("/r/b.md")
        tabs.open(a, beside: true)
        expect(tabs.count == 1 && tabs.activePaneCount == 2 && tabs.activeDocument === a)
        expect(tabs.activeTab?.tree == .split(.horizontal, .leaf(1), .leaf(2), ratio: 0.5), "\(tabs.activeTab!.tree)")
        tabs.focusPane(step: 1)
        tabs.open(b, beside: true)
        expect(tabs.activePaneCount == 2 && tabs.activeDocument === b && a.closed, "\(tabs.activePaneCount)")
        // Already open: its pane gets the focus, nothing else changes.
        tabs.newTab(cwd: "/")
        tabs.open(FakeDocument("/r/b.md"), beside: true)
        expect(tabs.count == 2 && tabs.activeDocument === b && tabs.activePaneCount == 2)
        tabs.closeAll()
    }),
    ("pane headers: only with 2+ panes; ✕ closes that pane alone; maximize; never", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.layoutSubtreeIfNeeded()
        guard let layout = tabs.activeTab?.layout else { return expect(false) }
        layout.layoutSubtreeIfNeeded()
        expect(layout.headerViews.isEmpty, "one pane, no header")
        let doc = FakeDocument("/r/CLAUDE.md")
        tabs.open(doc, beside: true)
        layout.layoutSubtreeIfNeeded()
        expect(layout.headerViews.count == 2, "\(layout.headerViews.count)")
        let docPane = tabs.activeTab!.tree.leaves.last!
        expect(layout.headerViews[docPane]?.info.title == doc.title && layout.headerViews[docPane]?.focused == true)
        expect(layout.panes[docPane]!.frame.minY == PaneHeaderView.height, "the pane starts under its header")
        // Issue #1: the file's ✕ closes the file only, never the tab or the window.
        layout.onHeaderAction?(docPane, .close)
        layout.layoutSubtreeIfNeeded()
        expect(doc.closed && tabs.count == 1 && tabs.activePaneCount == 1 && layout.headerViews.isEmpty)
        tabs.open(FakeDocument("/r/b.md"), beside: true)
        let terminalPane = tabs.activeTab!.tree.leaves.first!
        layout.onHeaderAction?(terminalPane, .zoom)
        layout.layoutSubtreeIfNeeded()
        expect(layout.zoomed == terminalPane && layout.panes[terminalPane]!.frame.height == layout.bounds.height - PaneHeaderView.height)
        expect(layout.panes[tabs.activeTab!.tree.leaves.last!]!.superview == nil, "the other pane is out of view")
        tabs.toggleZoom()
        layout.layoutSubtreeIfNeeded()
        expect(layout.zoomed == nil && layout.headerViews.count == 2 && layout.headerViews.values.allSatisfy { $0.superview?.superview === layout },
               "both headers back in view")
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] {
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 220))
            root.wantsLayer = true
            root.layer?.backgroundColor = NSColor(white: 0.11, alpha: 1).cgColor
            root.appearance = NSAppearance(named: .darkAqua)
            layout.removeFromSuperview()
            layout.translatesAutoresizingMaskIntoConstraints = true
            layout.frame = root.bounds
            layout.headerStyle = TabBarView.Style(activeFill: .darkGray, hoverFill: .gray, text: .white, secondaryText: NSColor(white: 0.6, alpha: 1),
                                                  accent: NSColor(red: 0.98, green: 0.45, blue: 0.2, alpha: 1))
            root.addSubview(layout)
            let window = NSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = root
            PaneLooks.frameColor = NSColor(white: 0.17, alpha: 1)
            PaneLooks.cardColor = NSColor(white: 0.07, alpha: 1)
            for view in layout.panes.values {
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor(white: 0.07, alpha: 1).cgColor
            }
            layout.layoutSubtreeIfNeeded()
            layout.headerViews.values.forEach { $0.layoutSubtreeIfNeeded() }
            if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/pane-headers.png"))
            }
        }
        PaneLooks.paneHeaders = "never"
        layout.layoutSubtreeIfNeeded()
        expect(layout.headerViews.isEmpty)
        PaneLooks.paneHeaders = "split"
        tabs.closeAll()
    }),
    ("dragging a pane: zones by the diagonals, center and header swap, measured on the start", {
        let three = PaneTree.split(.horizontal, .leaf(1), .split(.horizontal, .leaf(2), .leaf(3), ratio: 0.5), ratio: 0.5)
        expect(three.moving(1, beside: 3, edge: .down) == .split(.horizontal, .leaf(2), .split(.vertical, .leaf(3), .leaf(1), ratio: 0.5), ratio: 0.5))
        expect(three.swapping(1, 3) == .split(.horizontal, .leaf(3), .split(.horizontal, .leaf(2), .leaf(1), ratio: 0.5), ratio: 0.5))
        // Two panes side by side: 1 on the left (0-600), 2 on the right (600-1200), 24 pt headers.
        let frames: [Int: CGRect] = [1: CGRect(x: 0, y: 0, width: 600, height: 600), 2: CGRect(x: 600, y: 0, width: 600, height: 600)]
        func drop(_ x: CGFloat, _ y: CGFloat) -> PaneDrop? { PaneDrop.at(CGPoint(x: x, y: y), dragged: 1, frames: frames, header: 24) }
        expect(drop(900, 10) == PaneDrop(target: 2, side: nil), "the owner's case: right along the header row swaps")
        expect(drop(900, 312) == PaneDrop(target: 2, side: nil), "the center swaps")
        expect(drop(1180, 300) == PaneDrop(target: 2, side: .right) && drop(900, 590) == PaneDrop(target: 2, side: .down))
        expect(drop(1150, 150) == PaneDrop(target: 2, side: .right) && drop(1150, 40) == PaneDrop(target: 2, side: .up), "corners go by the diagonal")
        expect(drop(300, 300) == nil, "over itself: nothing")
        let two = PaneTree.split(.horizontal, .leaf(1), .leaf(2), ratio: 0.5)
        expect(PaneDrop(target: 2, side: .left).applied(to: two, dragged: 1) == .split(.horizontal, .leaf(2), .leaf(1), ratio: 0.5), "a drop that changes nothing swaps")
        expect(PaneDrop(target: 2, side: .down).applied(to: two, dragged: 1) == .split(.vertical, .leaf(2), .leaf(1), ratio: 0.5))
        // A real tab: gray windows while dragging, the real panes only on release.
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.layoutSubtreeIfNeeded()
        tabs.open(FakeDocument("/r/a.md"), beside: true)
        guard let layout = tabs.activeTab?.layout else { return expect(false) }
        layout.layoutSubtreeIfNeeded()
        let (terminal, document) = (layout.tree.leaves[0], layout.tree.leaves[1])
        let start = layout.convert(CGPoint(x: 900, y: 10), to: nil)
        let left = layout.convert(CGPoint(x: 20, y: 300), to: nil)
        layout.onHeaderAction?(document, .drag(.began, start))
        layout.onHeaderAction?(document, .drag(.moved, left))
        expect(layout.subviews.contains { $0 is PaneDragBoard } && layout.tree.leaves == [terminal, document], "gray windows, real panes untouched")
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let root = NSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 600))
            let window = NSWindow(contentRect: root.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = root
            let parent = layout.superview
            layout.removeFromSuperview()
            layout.translatesAutoresizingMaskIntoConstraints = true
            layout.frame = root.bounds
            root.addSubview(layout)
            if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/pane-drag.png"))
            }
            layout.removeFromSuperview()
            parent?.addSubview(layout)
        }
        layout.onHeaderAction?(document, .drag(.ended, left))
        expect(layout.tree.leaves == [document, terminal], "\(layout.tree)")
        // Dropped with no zone (over itself): nothing changes.
        layout.onHeaderAction?(terminal, .drag(.began, left))
        layout.onHeaderAction?(terminal, .drag(.ended, layout.convert(CGPoint(x: 900, y: 300), to: nil)))
        expect(layout.tree.leaves == [document, terminal])
        tabs.closeAll()
    }),
    ("docking: a pane at one side of the outermost split keeps its share", {
        let three = PaneTree.split(.horizontal, .leaf(1), .split(.horizontal, .leaf(2), .leaf(3), ratio: 0.5), ratio: 0.5)
        let docked = three.docking(9, first: false)
        expect(docked == .split(.horizontal, three, .leaf(9), ratio: 0.5))
        expect(three.docking(9, first: true) == .split(.horizontal, .leaf(9), three, ratio: 0.5))
        guard case .split(_, let rest, _, let ratio) = docked.balanced(keeping: 9) else { return expect(false) }
        expect(ratio == 0.5, "the file keeps half: \(ratio)")
        expect(rest == three.balanced(), "the panes beside it share theirs evenly")
        guard case .split(_, _, _, let even) = docked.balanced(keeping: nil) else { return expect(false) }
        expect(abs(even - 0.75) < 0.001, "without docking, four in a row")
    }),
    ("beside: the file takes half the tab, the terminals share the rest and get it back (issue #5)", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.layoutSubtreeIfNeeded()
        tabs.split(.horizontal)
        let terminals = tabs.activeTab!.tree
        let doc = FakeDocument("/r/notes.md")
        tabs.open(doc, beside: true)
        guard let tab = tabs.activeTab, case .split(.horizontal, let rest, .leaf(let docPane), let ratio) = tab.tree else {
            return expect(false, "\(tabs.activeTab!.tree)")
        }
        expect(ratio == 0.5 && rest == terminals && tab.panes[docPane]?.document === doc, "\(tab.tree)")
        // A new terminal splits the terminals' half; the file keeps its own.
        tab.focus(rest.leaves[0])
        tabs.split(.horizontal)
        guard case .split(_, let more, .leaf(docPane), 0.5) = tab.tree else { return expect(false, "\(tab.tree)") }
        expect(more.leaves.count == 3, "\(more)")
        tabs.removePane(docPane, from: tab)
        expect(tab.tree == more.balanced(), "closing the file gives the terminals the whole tab")
        TabsController.documentsOnLeft = true
        tabs.open(FakeDocument("/r/left.md"), beside: true)
        guard case .split(.horizontal, .leaf(let leftPane), more.balanced(), 0.5) = tab.tree else { return expect(false, "\(tab.tree)") }
        expect(tab.panes[leftPane]?.document != nil)
        TabsController.documentsOnLeft = false
        tabs.closeAll()
    }),
    ("beside: an unsaved document is not replaced, and the asking one stays", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.layoutSubtreeIfNeeded()
        let a = FakeDocument("/r/a.swift")
        tabs.open(a, beside: true)
        a.hasUnsavedChanges = true
        let b = FakeDocument("/r/b.swift")
        tabs.open(b, beside: true)
        expect(tabs.activePaneCount == 3 && !a.closed && tabs.activeDocument === b)
        // The history opening a diff: the diff goes beside it, not over it.
        let c = FakeDocument("diff:work:/r/b.swift")
        tabs.open(c, beside: true, keeping: b)
        expect(!b.closed && tabs.activePaneCount == 4, "\(tabs.activePaneCount)")
        a.hasUnsavedChanges = false
        tabs.closeAll()
    }),
    ("beside with no room to split opens a new tab; the setting off opens a new tab", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.frame.size.width = 200
        tabs.view.layoutSubtreeIfNeeded()
        tabs.open(FakeDocument("/r/a.md"), beside: true)
        expect(tabs.count == 2 && tabs.activePaneCount == 1, "\(tabs.count)")
        tabs.open(FakeDocument("/r/b.md"), beside: false)
        expect(tabs.count == 3)
        tabs.closeAll()
    }),
    ("a press in a document gives its pane the focus; ⌘] goes through it", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.layoutSubtreeIfNeeded()
        let a = FakeDocument("/r/a.md")
        tabs.open(a, beside: true)
        tabs.focusPane(step: 1)
        expect(tabs.activeTerminal != nil)
        let press = a.view.gestureRecognizers.compactMap { $0 as? PanePressRecognizer }
        expect(press.count == 1)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        press.first?.mouseDown(with: down)
        expect(tabs.activeDocument === a && tabs.activeTerminal == nil)
        tabs.focusPane(step: 1)
        expect(tabs.activeTerminal != nil)
        tabs.closeAll()
    }),
    ("⌘D in a document opens a terminal beside it; ⌘W asks the document", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.layoutSubtreeIfNeeded()
        let a = FakeDocument("/tmp/a.md")
        tabs.open(a, beside: false)
        tabs.view.layoutSubtreeIfNeeded()
        tabs.split(.horizontal)
        expect(tabs.activePaneCount == 2 && tabs.activeTerminal != nil)
        tabs.focusPane(step: -1)
        a.closes = false
        tabs.closeFocusedPane()
        expect(tabs.activePaneCount == 2 && !a.closed, "cancelled: the pane stays")
        a.closes = true
        tabs.closeFocusedPane()
        expect(tabs.activePaneCount == 1 && a.closed && tabs.activeTerminal != nil)
        tabs.closeAll()
    }),
    ("the tab's title and dot come from its panes", {
        let tabs = makeTabs()
        tabs.newTab(cwd: "/")
        tabs.view.layoutSubtreeIfNeeded()
        let a = FakeDocument("/r/a.md")
        tabs.open(a, beside: true)
        expect(tabs.bar.items.first?.title == "a.md" && tabs.bar.items.first?.icon == .fileMd)
        a.hasUnsavedChanges = true
        tabs.focusPane(step: 1)
        expect(tabs.bar.items.first?.title.hasPrefix("● ") == true, "\(tabs.bar.items)")
        a.hasUnsavedChanges = false
        tabs.closeAll()
    }),
])
exit(exitCode)
