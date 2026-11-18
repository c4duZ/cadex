import AppKit
import Checks
@testable import Tabs

/// A page (a project's, the automations): opens in a tab of its own that never shows in the bar.
final class FakePage: TabDocument {
    let view = NSView()
    let identity: String
    var title: String { identity }
    var hasUnsavedChanges: Bool { false }
    var onChange: (() -> Void)?
    var isPage: Bool { true }
    init(_ identity: String) { self.identity = identity }
    func focus() {}
    func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    func close() {}
}

/// Plan 34 A: pages under the bar, one at a time, Esc back to the terminal.
@MainActor
let pageChecks: [(name: String, body: Checks.Body)] = [
    ("a page never shows in the bar, which keeps the terminal tabs; one page at a time; leaving goes back to the terminal", {
        let tabs = makeTabs()
        tabs.newTab(cwd: NSTemporaryDirectory())
        let terminalTab = tabs.list.active
        let before = tabs.bar.items.map(\.id)
        tabs.open(FakePage("project:one"))
        Checks.expect(tabs.showsPage, "the page is shown")
        Checks.expect(tabs.bar.items.map(\.id) == before, "the bar is the same: \(tabs.bar.items.map(\.title))")
        Checks.expect(!tabs.bar.items.contains { $0.active }, "no tab lit with a page shown")
        tabs.open(FakePage("automation:"))
        Checks.expect(tabs.list.order.count == 2, "one page at a time: \(tabs.list.order.count) tabs")
        tabs.leavePage()
        Checks.expect(!tabs.showsPage && tabs.list.active == terminalTab, "back on the terminal")
        Checks.expect(tabs.bar.items.map(\.id) == before)
    }),
]
