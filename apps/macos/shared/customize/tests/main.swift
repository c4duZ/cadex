import AppKit
import Checks
import Foundation
@testable import Customize

// Tests of the shared Customize window. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

func row(_ id: String, _ on: Bool = true, subtitle: String? = nil) -> CustomizeEntry {
    .row(CustomizeRow(id: id, icon: .files, title: id.capitalized, subtitle: subtitle, on: on))
}

let exitCode = await Checks.run([
    ("rows belong to the title above them", {
        let entries: [CustomizeEntry] = [.header("Left"), row("folder"), .header("Right"), row("environment"), row("ram", false)]
        expect(CustomizeLayout.sections(entries).map { $0.map(\.id) } == [["folder"], ["environment", "ram"]])
        expect(CustomizeLayout.sections([.header("Left"), .header("Right"), row("cpu")]).map { $0.map(\.id) } == [[], ["cpu"]])
    }),
    ("moving a row past a title changes its section; none goes above the first title", {
        let entries: [CustomizeEntry] = [.header("Left"), row("folder"), .header("Right"), row("environment")]
        let moved = CustomizeLayout.moved(entries, from: 3, to: 1)
        expect(CustomizeLayout.sections(moved).map { $0.map(\.id) } == [["environment", "folder"], []], "\(moved)")
        expect(CustomizeLayout.moved(entries, from: 1, to: 0) == entries, "the first title stays first")
        expect(CustomizeLayout.moved(entries, from: 0, to: 3) == entries, "titles do not move")
    }),
    ("flipping a switch changes only that row", {
        let flipped = CustomizeLayout.flipped([.header("X"), row("a"), row("b")], "b")
        expect(flipped.compactMap(\.row).map(\.on) == [true, false])
    }),
    ("a dragged thing lands in the slot under its middle", {
        let widths: [CGFloat] = [30, 30, 30]
        expect(CustomizeLayout.dropIndex(at: 5, widths: widths, spacing: 2) == 0)
        expect(CustomizeLayout.dropIndex(at: 47, widths: widths, spacing: 2) == 1, "the middle of slot 1 is slot 1")
        expect(CustomizeLayout.dropIndex(at: 200, widths: widths, spacing: 2) == 2)
    }),
    ("dragging a row reorders the list while the mouse moves, the row on top, across a title", {
        let list = CustomizeList()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(list)
        list.frame = NSRect(x: 0, y: 0, width: 300, height: 260)
        list.show([.header("Left"), row("folder"), .header("Right"), row("environment"), row("ram", false)], colors: CustomizeColors())
        list.layoutSubtreeIfNeeded()
        var changes: [[CustomizeEntry]] = []
        list.onChange = { changes.append($0) }
        @MainActor func event(_ type: NSEvent.EventType, _ y: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: list.convert(NSPoint(x: 20, y: y), to: nil), modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        // From Right's last row (ram) up into Left.
        let start = list.views[4].frame.midY
        let end = list.views[1].frame.midY
        list.mouseDown(with: event(.leftMouseDown, start))
        var y = start
        while y > end {
            y = max(y - 4, end)
            list.mouseDragged(with: event(.leftMouseDragged, y))
        }
        expect(CustomizeLayout.sections(list.entries).first?.map(\.id).contains("ram") == true, "moved before the mouse goes up: \(list.entries)")
        expect(list.subviews.last === list.views[list.entries.firstIndex { $0.row?.id == "ram" } ?? 0], "the dragged row is on top")
        list.mouseUp(with: event(.leftMouseUp, y))
        expect(changes.count == 1, "one change per drop")
    }),
    ("a page inside the settings window: its rows, each change to its owner, a refresh shows a new list", {
        var status: [[CustomizeEntry]] = []
        let page = CustomizePage(id: "statusBar", title: "Status Bar", icon: .slidersHorizontal, note: "n",
                                 entries: [.header("Left"), row("folder"), .header("Right"), row("ram", false)]) { status.append($0) }
        let view = CustomizePageView(page)
        expect(view.entries.compactMap(\.row).map(\.id) == ["folder", "ram"])
        expect(view.fittingSize.height > 0, "its height is its rows'")
        let moved = CustomizePage(id: "statusBar", title: "Status Bar", icon: .slidersHorizontal, note: "n",
                                  entries: [.header("Left"), row("ram"), .header("Right"), row("folder")]) { status.append($0) }
        view.refresh(moved)
        expect(view.entries.compactMap(\.row).map(\.id) == ["ram", "folder"])
        expect(status.isEmpty, "showing changes nothing")
    }),
])
exit(exitCode)
