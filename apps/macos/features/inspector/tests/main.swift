import AppKit
import Checks
import Foundation
@testable import Inspector

// Tests of the inspector feature. Run with `make macos-test` (see shared/checks/Checks.swift for
// why this is an executable).

@MainActor
func tabs(_ views: [NSView]) -> [InspectorTab] {
    [InspectorTab(id: "changes", title: "Changes", command: "git.show", view: views[0], actions: [
        InspectorAction("git.fetch", .arrowsClockwise, "Fetch"), InspectorAction("git.pull", .arrowDown, "Pull"),
        InspectorAction("git.push", .arrowUp, "Push"), InspectorAction("git.review-open", .gitDiff, "Review"),
     ], more: [InspectorAction("git.refresh", .arrowClockwise, "Refresh")]),
     InspectorTab(id: "files", title: "Files", command: "explorer.focus", view: views[1]),
     InspectorTab(id: "history", title: "History", command: "git.show-history", view: views[2], actions: [
        InspectorAction("git.history-in-tab", .arrowSquareOut, "Open in a Tab"),
     ]),
     InspectorTab(id: "memory", title: "Memory", command: "memory.show", view: views[3])]
}

let exitCode = await Checks.run([
    ("the page shown by its command is the lit icon, the others not (Files opened by explorer.focus)", { @MainActor in
        let views = (0..<4).map { _ in NSView() }
        let inspector = InspectorView(tabs: tabs(views), shortcut: nil) { _ in true }
        inspector.show("changes")
        inspector.show("files")
        expect(inspector.tabButtons.filter(\.isOn).map(\.id) == ["files"])
        expect(inspector.tabButtons.map(\.toolTip) == ["Changes", "Files", "History", "Memory"], "the name under the pointer")
    }),
    ("the tabs in order with ⌥⌘I; one page shows, the others are hidden (they read only while shown)", {
        let views = (0..<4).map { _ in NSView() }
        var shown: [String] = []
        let view = InspectorView(tabs: tabs(views), shortcut: "⌥⌘I") { _ in }
        view.onShow = { shown.append($0) }
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
        expect(view.tabTitles == ["Changes", "Files", "History", "Memory"], "\(view.tabTitles)")
        expect(views.allSatisfy(\.isHidden), "nothing shows before a tab is chosen")
        view.show("history")
        expect(view.tab == "history" && !views[2].isHidden && views.enumerated().allSatisfy { $0.offset == 2 || $0.element.isHidden })
        expect(shown == ["history"], "\(shown)")
        view.show("nope")
        expect(view.tab == "history", "an unknown id changes nothing")
    }),
    ("the scope row: the tab's name or the app's words, three buttons and the rest under ⋯", {
        let view = InspectorView(tabs: tabs((0..<4).map { _ in NSView() }), shortcut: nil) { _ in }
        view.show("changes")
        expect(view.scopeText == "Changes", view.scopeText)
        expect(view.scopeCommands == ["git.fetch", "git.pull", "git.push", "…"], "\(view.scopeCommands)")
        view.setScope(InspectorScope("orchestration-e · against main", command: "git.switch-branch"), for: "changes")
        expect(view.scopeText == "orchestration-e · against main", view.scopeText)
        view.setScope(InspectorScope("cadex"), for: "files")
        expect(view.scopeText == "orchestration-e · against main", "another tab's words wait for it")
        view.show("files")
        expect(view.scopeText == "cadex" && view.scopeCommands.isEmpty, "\(view.scopeCommands)")
        view.show("history")
        expect(view.scopeCommands == ["git.history-in-tab"], "no ⋯ with nothing more: \(view.scopeCommands)")
    }),
    ("a click on a tab runs its command (ADR 0005), as ⌘K does", {
        var ran: [String] = []
        let view = InspectorView(tabs: tabs((0..<4).map { _ in NSView() }), shortcut: nil) { ran.append($0) }
        view.frame = NSRect(x: 0, y: 0, width: 320, height: 600)
        view.layoutSubtreeIfNeeded()
        let button = view.subviews.compactMap { $0 as? NSStackView }.first?.arrangedSubviews.compactMap { $0 as? InspectorTabButton }
            .first { $0.id == "memory" }
        button?.onPress?()
        expect(ran == ["memory.show"], "\(ran)")
    }),
])
exit(exitCode)
