import Foundation
import CCadex
import Checks
@testable import Explorer
import Icons

/// A fresh folder in the temporary directory, authorized in the core.
@MainActor
func sandbox() -> String {
    let path = NSTemporaryDirectory() + "cadex-explorer-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: path + "/src/deep", withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: path + "/b.txt", contents: Data("b".utf8))
    FileManager.default.createFile(atPath: path + "/.env", contents: nil)
    let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
    folder.open(path)
    return folder.root
}

// Tests of the explorer feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

let exitCode = await Checks.run([
    ("the launch folder is the first folder argument, flags skipped", {
        let folder = WorkspaceFolder.launchDirectory(arguments: ["Cadex", "-psn_0_42", "bin"], cwd: "/usr")
        expect(folder == "/usr/bin", "\(folder ?? "nil")")
        expect(WorkspaceFolder.launchDirectory(arguments: ["Cadex"], cwd: "/usr") == nil)
    }),
    ("without a launch folder the root is the home folder", {
        let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
        expect(folder.root == (NSHomeDirectory() as NSString).resolvingSymlinksInPath, folder.root)
    }),
    ("opening a folder authorizes it and changes the root once", {
        let folder = WorkspaceFolder(arguments: ["Cadex", "/usr"], cwd: "/")
        var changes: [String] = []
        folder.onChange = { changes.append($0) }
        expect(folder.open("/tmp"))
        expect(folder.root == "/private/tmp", folder.root)
        expect(folder.open("/private/tmp/."))
        expect(changes == ["/private/tmp"], "\(changes)")
        expect(!folder.open("/no/such/folder"))
        expect(folder.root == "/private/tmp")
    }),
    ("a reload keeps the rows that did not change, with their loaded children", {
        let root = FileNode(path: sandbox(), entry: nil)
        root.load()
        expect(root.children?.map(\.name) == ["src", ".env", "b.txt"], "\(root.children?.map(\.name) ?? [])")
        let src = root.children![0]
        src.load()
        FileManager.default.createFile(atPath: root.path + "/a.txt", contents: nil)
        root.load()
        expect(root.children?.map(\.name) == ["src", ".env", "a.txt", "b.txt"])
        expect(root.children![0] === src && src.isLoaded)
        expect(root.find(root.path + "/src/deep") === src.children![0])
        try? FileManager.default.removeItem(atPath: root.path)
    }),
    ("hidden files and empty folders as the tree shows them", {
        let root = FileNode(path: sandbox(), entry: nil)
        root.load()
        expect(root.visibleChildren(showHidden: false).map(\.name) == ["src", "b.txt"])
        let deep = root.children![0]
        deep.load()
        let empty = deep.children![0]
        empty.load()
        let note = empty.visibleChildren(showHidden: true)
        expect(note.count == 1 && note[0].isNote && note[0].name == "Pasta vazia")
        expect(empty.visibleChildren(showHidden: true)[0] === note[0])
        try? FileManager.default.removeItem(atPath: root.path)
    }),
    ("file operations refuse taken names and paths outside", {
        let root = sandbox()
        do throws(ExplorerError) {
            try ExplorerFiles.createFile(root + "/b.txt")
            expect(false, "created over an existing file")
        } catch {
            expect(error.status == CADEX_ALREADY_EXISTS)
        }
        do throws(ExplorerError) {
            try ExplorerFiles.createFile("/private/var/cadex-outside.txt")
            expect(false, "created outside")
        } catch {
            expect(error.message == "Fora da pasta aberta")
        }
        let renamed = try ExplorerFiles.rename(root + "/b.txt", to: "c.txt")
        expect(renamed == root + "/c.txt")
        // Not trashing here: each run would leave a file in the owner's Trash.
        do throws(ExplorerError) {
            try ExplorerFiles.trash("/private/var/cadex-outside.txt")
            expect(false, "trashed outside")
        } catch {
            expect(error.status == CADEX_NOT_AUTHORIZED)
        }
        try? FileManager.default.removeItem(atPath: root)
    }),
    ("icons by kind and extension", {
        expect(FileTypeIcon.icon(forFileNamed: "render.zig") == .fileCode)
        expect(FileTypeIcon.icon(forFileNamed: "README.md") == .fileMd)
        expect(FileTypeIcon.icon(forFileNamed: "Package.resolved") == .file)
        expect(FileTypeIcon.icon(forFileNamed: "settings.JSON") == .bracketsCurly)
        expect(FileTypeIcon.icon(forFileNamed: "Makefile") == .fileCode)
        expect(FileTypeIcon.icon(forFileNamed: ".gitignore") == .bracketsCurly)
        let folder = FileEntry(name: "src", kind: .directory, size: 0, linkToDirectory: false)
        expect(FileTypeIcon.icon(name: "src", entry: folder, expanded: true) == .folderOpen)
    }),
    ("the watcher reports a new file on the main thread", {
        let root = sandbox()
        var seen: [String] = []
        let watcher = FileWatcher(path: root) { changes in seen += changes.map(\.path) }
        expect(watcher != nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        FileManager.default.createFile(atPath: root + "/src/new.txt", contents: nil)
        for _ in 0..<50 where !seen.contains(root + "/src") { try await Task.sleep(nanoseconds: 100_000_000) }
        expect(seen.contains(root + "/src"), "\(seen)")
        watcher?.stop()
        try? FileManager.default.removeItem(atPath: root)
    }),
])
exit(exitCode)
