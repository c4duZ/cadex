import AppKit
import Checks
import Foundation
@testable import Home

// Tests of the home feature. Run with `make macos-test` (see shared/checks/Checks.swift for why
// this is an executable).

let exitCode = await Checks.run([
    ("the greeting follows the hour", {
        expect(HomeWords.greeting(hour: 8) == "Good morning" && HomeWords.greeting(hour: 14) == "Good afternoon")
        expect(HomeWords.greeting(hour: 21) == "Good evening" && HomeWords.greeting(hour: 3) == "Good evening")
    }),
    ("an open project's state: what needs you wins, then a finished agent, then the terminals", {
        expect(HomeWords.state(terminals: 2, needYou: 1, finished: "Claude") == .needsYou("2 terminals open · 1 needs you"))
        expect(HomeWords.state(terminals: 1, needYou: 0, finished: "Claude") == .finished("Claude finished"))
        expect(HomeWords.state(terminals: 3, needYou: 0, finished: nil) == .open("3 terminals open"))
        expect(HomeWords.state(terminals: 0, needYou: 0, finished: nil) == .closed)
    }),
    ("Clone's folder: the address's last part without .git, never a path", {
        expect(HomeWords.cloneFolder("https://github.com/o/repo.git") == "repo")
        expect(HomeWords.cloneFolder("git@github.com:o/site") == "site")
        expect(HomeWords.cloneFolder("https://x.org/a/b/") == "b")
        expect(HomeWords.cloneFolder("..") == "repository" && HomeWords.cloneFolder("") == "repository")
    }),
    ("when, and the home folder as ~", {
        let now = Date()
        expect(HomeWords.when(now, now: now) == "now" && HomeWords.when(now - 240, now: now) == "4m")
        expect(HomeWords.when(now - 3600, now: now) == "1h" && HomeWords.when(now - 3 * 86400, now: now) == "3d")
        expect(HomeWords.shortPath("/Users/a/Cadu/cadex", home: "/Users/a") == "~/Cadu/cadex")
        expect(HomeWords.shortPath("/tmp/x", home: "/Users/a") == "/tmp/x")
    }),
    ("the screen: the project in the prompt, Enter submits, @ asks for the project; a missing folder offers Remove", { @MainActor in
        var submitted: [String] = []
        var picked = 0
        var actions = HomeActions()
        actions.submit = { submitted.append($0) }
        actions.pickProject = { _ in picked += 1 }
        actions.shortcut = { $0 == .terminal ? "⌘T" : "" }
        let view = HomeView(actions: actions)
        view.frame = NSRect(x: 0, y: 0, width: 1100, height: 800)
        view.show(HomeState(project: "cadex", agent: "Claude · bkdg", recents: [
            HomeRecent(name: "cadex", folder: "/r/cadex", state: .needsYou("2 terminals open · 1 needs you"), usedAt: Date()),
            HomeRecent(name: "gone", folder: "/r/gone", state: .missing, usedAt: Date()),
        ]))
        view.layoutSubtreeIfNeeded()
        expect(view.field.placeholderAttributedString?.string == "What do you want to do in cadex?")
        view.field.stringValue = "fix the pay button"
        _ = view.control(view.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:)))
        expect(submitted == ["fix the pay button"])
        view.field.stringValue = "x@"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        expect(picked == 1 && view.field.stringValue == "x")
        func texts(_ v: NSView) -> [String] { ((v as? NSTextField).map { [$0.stringValue] } ?? []) + ((v as? NSButton).map { [$0.attributedTitle.string] } ?? []) + v.subviews.flatMap(texts) }
        let all = texts(view)
        expect(all.contains("Remove") && all.contains("RECENT PROJECTS") && all.contains("⌘T"), "\(all)")
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/home.png"))
        }
    }),
])
exit(exitCode)
