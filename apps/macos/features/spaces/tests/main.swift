import AppKit
import Checks
@testable import Spaces
import Tabs

// Tests of the spaces feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

@MainActor
func eventually(_ body: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if body() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

func tempFile() -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cadex-spaces-\(UUID().uuidString)")
    return dir.appendingPathComponent("spaces.json")
}

@MainActor
func controller(_ url: URL, window: NSWindow) -> SpacesController {
    SpacesController(fileURL: url) { TabsController(window: window) }
}

// The shell reports the real path: /tmp is /private/tmp.
let tmp = String(cString: realpath(NSTemporaryDirectory(), nil))

let exitCode = await Checks.run([
    ("a first launch has one space with a terminal in the folder", {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let url = tempFile()
        let spaces = controller(url, window: window)
        var shown: TabsController?
        spaces.onSwitch = { shown = $0 }
        spaces.start(folder: tmp) { _ in }
        expect(spaces.spaces.count == 1 && spaces.activeName == "Space 1")
        expect(shown === spaces.active && spaces.active?.isShown == true && spaces.active?.count == 1)
        spaces.spaces.forEach { $0.tabs.closeAll() }
    }),
    ("spaces saved and restored come back the same, with the active one", {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let url = tempFile()
        let saved = SavedSpaces(spaces: [
            .init(name: "api", tabs: TabsSnapshot(items: [.terminal(title: nil, layout: .pane(folder: tmp), focus: 0)], active: 0)),
            .init(name: "site", tabs: TabsSnapshot(items: [
                .terminal(title: "logs", layout: .split(sideBySide: false, ratio: 0.7, first: .pane(folder: "/"), second: .pane(folder: tmp)), focus: 1),
                .document(identity: "/nota.md"),
            ], active: 0)),
        ], active: 1)
        try? SpacesFile.save(saved, to: url)
        let spaces = controller(url, window: window)
        var reopened: [String] = []
        spaces.start(folder: "/") { reopened.append($0) }
        expect(reopened == ["/nota.md"] && spaces.activeName == "site", "\(reopened) \(spaces.activeName)")
        expect(spaces.spaces[0].tabs.isShown == false && spaces.spaces[1].tabs.isShown)
        var expected = saved
        expected.spaces[1].tabs.items.removeLast()
        let same = await eventually { spaces.saved == expected }
        expect(same, "\(spaces.saved)")

        spaces.saveNow()
        let again = controller(url, window: window)
        again.start(folder: "/") { _ in }
        let restored = await eventually { again.saved == expected }
        expect(restored, "\(again.saved)")
        (spaces.spaces + again.spaces).forEach { $0.tabs.closeAll() }
    }),
    ("a corrupted file is moved aside and the app starts fresh", {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let url = tempFile()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{ isto não é json".utf8).write(to: url)
        let spaces = controller(url, window: window)
        spaces.start(folder: tmp) { _ in }
        expect(spaces.spaces.count == 1 && spaces.active?.count == 1)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        expect(files.contains { $0.hasPrefix("spaces.bad-") } && !files.contains("spaces.json"), "\(files)")
        spaces.spaces.forEach { $0.tabs.closeAll() }
    }),
    ("new, next, rename and close; the last space stays", {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        let spaces = controller(tempFile(), window: window)
        spaces.start(folder: tmp) { _ in }
        spaces.newSpace(folder: tmp)
        expect(spaces.spaces.count == 2 && spaces.activeIndex == 1 && spaces.activeName == "Space 2")
        spaces.selectNext(step: 1)
        expect(spaces.activeIndex == 0 && spaces.spaces[0].tabs.isShown && !spaces.spaces[1].tabs.isShown)
        spaces.rename(at: 0, to: "  api ")
        spaces.rename(at: 0, to: "   ")
        expect(spaces.activeName == "api")
        spaces.closeActive()
        expect(spaces.spaces.count == 1 && spaces.activeName == "Space 2" && spaces.active?.isShown == true)
        spaces.closeActive()
        expect(spaces.spaces.count == 1)
        spaces.spaces.forEach { $0.tabs.closeAll() }
    }),
])
exit(exitCode)
