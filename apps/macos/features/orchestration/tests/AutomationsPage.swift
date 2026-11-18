import AppKit
import Checks
@testable import Orchestration

// The Automations page (plan 34 F): empty with Create automation in the middle, or the table.

@MainActor
func automationsPage(_ lines: [AutomationsLine], enabled: Bool) -> (AutomationsPageDocument, NSWindow) {
    var actions = AutomationsPageActions()
    actions.load = { (lines, enabled) }
    let page = AutomationsPageDocument(actions: actions)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = page.view
    page.refresh()
    page.view.layoutSubtreeIfNeeded()
    return (page, window)
}

@MainActor
func saveAutomationsSnapshot(_ view: NSView, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + name + ".png"))
}

@MainActor
func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
    ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
}

let automationsPageTests: [(name: String, body: Checks.Body)] = [
    ("empty, the page fills the area with Create automation and, off, says creating turns them on", { @MainActor in
        let (page, _) = automationsPage([], enabled: false)
        let empty = views(AutomationsEmpty.self, in: page.view).first
        Checks.expect(empty != nil, "the empty state shows")
        Checks.expect((empty?.frame.height ?? 0) > 400, "it fills the area: \(empty?.frame.height ?? 0)")
        saveAutomationsSnapshot(page.view, "automations-empty")
    }),
    ("with automations, a table: the head and a line each, the switch on or off", { @MainActor in
        let lines = [AutomationsLine(id: "a", name: "Review open PRs", when: "Weekdays 09:00", project: "bkdg-center", account: "bhband",
                                     last: "done today", lastState: .done, next: "tomorrow 09:00", on: true),
                     AutomationsLine(id: "b", name: "Update dependencies", when: "Every Monday 08:00", project: "cadex", account: "fba. + BKDG",
                                     last: "never", lastState: nil, next: "—", on: false)]
        let (page, _) = automationsPage(lines, enabled: true)
        Checks.expect(views(AutomationsEmpty.self, in: page.view).isEmpty)
        Checks.expect(views(AutomationTableRow.self, in: page.view).count == 3, "the head and two lines")
        Checks.expect(views(AutomationSwitch.self, in: page.view).count == 2)
        saveAutomationsSnapshot(page.view, "automations-table")
    }),
]
