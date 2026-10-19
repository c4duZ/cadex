import Foundation
import Checks
import CommandPalette
@testable import Explorer
@testable import Search

// Tests of the search feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

/// A small workspace, authorized in the core like the app does.
@MainActor
func sandbox() -> String {
    let path = NSTemporaryDirectory() + "cadex-search-\(UUID().uuidString)"
    let fm = FileManager.default
    try? fm.createDirectory(atPath: path + "/core/features/terminal", withIntermediateDirectories: true)
    fm.createFile(atPath: path + "/core/features/terminal/render.zig", contents: Data("// draws with libghostty\n".utf8))
    fm.createFile(atPath: path + "/README.md", contents: Data("Cadex\nBuilt on LibGhostty.\n".utf8))
    fm.createFile(atPath: path + "/.gitignore", contents: Data("zig-out/\n".utf8))
    try? fm.createDirectory(atPath: path + "/zig-out", withIntermediateDirectories: true)
    fm.createFile(atPath: path + "/zig-out/render.zig", contents: Data("libghostty".utf8))
    let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
    folder.open(path)
    return folder.root
}

/// Polls `body` on the main actor for up to ~5 s.
@MainActor
func eventually(_ body: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if body() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

let exitCode = await Checks.run([
    ("⌘P finds render.zig, not the ignored copy, and remembers what was opened", {
        let root = sandbox()
        var opened: [String] = []
        let search = SearchController(root: root, showHidden: false) { path, _, _ in opened.append(path) }
        var shown: [PaletteItem] = []
        let found = await eventually {
            search.files.search("render") { items, _ in shown = items }
            return !shown.isEmpty
        }
        expect(found)
        expect(shown.map(\.id) == ["core/features/terminal/render.zig"], "\(shown.map(\.id))")
        search.files.choose(shown[0])
        expect(opened == [root + "/core/features/terminal/render.zig"])
        search.files.search("") { items, _ in shown = items }
        expect(shown.map(\.id) == ["core/features/terminal/render.zig"])
        try? FileManager.default.removeItem(atPath: root)
    }),
    ("⌘⇧F streams results with the line, and an invalid regex says so", {
        let root = sandbox()
        var opened: [(String, Int?)] = []
        let search = SearchController(root: root, showHidden: false) { opened.append(($0, $1)) ; _ = $2 }
        var shown: [PaletteItem] = []
        var status: String?
        search.content.search("libghostty") { items, s in shown = items; status = s }
        let done = await eventually { status?.contains("arquivos") == true }
        expect(done, status ?? "nil")
        expect(shown.map(\.detail) == ["README.md:2", "core/features/terminal/render.zig:1"], "\(shown.map(\.detail))")
        search.content.choose(shown[1])
        expect(opened.first?.0 == root + "/core/features/terminal/render.zig" && opened.first?.1 == 1)
        search.content.regex = true
        search.content.search("(") { _, s in status = s }
        expect(status == ".* · Expressão regular inválida", status ?? "nil")
        search.content.stop()
        try? FileManager.default.removeItem(atPath: root)
    }),
    ("a new query drops the results of the old one", {
        let root = sandbox()
        let search = SearchController(root: root, showHidden: false) { _, _, _ in }
        var fromOld = 0
        search.content.search("Cadex") { items, _ in fromOld += items.count }
        var shown: [PaletteItem] = []
        var status: String?
        search.content.search("draws") { items, s in shown = items; status = s }
        _ = await eventually { status?.contains("arquivos") == true }
        expect(fromOld == 0, "\(fromOld)")
        expect(shown.map(\.detail) == ["core/features/terminal/render.zig:1"])
        try? FileManager.default.removeItem(atPath: root)
    }),
])
exit(exitCode)
