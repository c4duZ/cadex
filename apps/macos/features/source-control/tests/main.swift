import AppKit
import Checks
@testable import Explorer
@testable import SourceControl

// Tests of the source-control feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

@MainActor
func eventually(_ body: () -> Bool) async -> Bool {
    for _ in 0..<100 {
        if body() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return false
}

func git(_ args: [String], in dir: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["git"] + args
    p.currentDirectoryURL = URL(fileURLWithPath: dir)
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

let exitCode = await Checks.run([
    ("status lines from the core become entries and rows", {
        let s = GitRepository.parseStatus("main\tabc\torigin/main\t1\t2\n0\tM\t.\ta.zig\t\n0\t.\tM\tb.zig\t\n1\tR\t.\tnovo.txt\tvelho.txt\n3\t?\t?\tnovo.md\t\n")
        expect(s.branch == "main" && s.ahead == 1 && s.behind == 2)
        expect(s.entries.count == 4)
        expect(s.entries[0].isStaged && !s.entries[0].isUnstaged)
        expect(s.entries[3].isUnstaged && s.entries[3].letter(staged: false) == "?")
        let rows = SourceControlRow.rows(for: s)
        expect(rows.first == .header(title: "Staged", staged: true, count: 2), "\(rows)")
        expect(rows.count == 6, "\(rows.count)")
    }),
    ("a list shows at most 1000 files and says how many there are", {
        var s = GitRepository.Status()
        s.entries = (0..<1500).map { GitRepository.Entry(kind: .untracked, index: "?", worktree: "?", path: "f\($0)", orig: "") }
        let rows = SourceControlRow.rows(for: s)
        expect(rows.count == 1 + SourceControlRow.limit + 1, "\(rows.count)")
        guard case let .header(title, _, _) = rows.last else { return expect(false, "no note") }
        expect(title.contains("1500"), title)
    }),
    ("removed and added lines from a patch", {
        let patch = "diff --git a/x b/x\n--- a/x\n+++ b/x\n@@ -1,3 +1,3 @@\n um\n-dois\n+DOIS\n três\n@@ -10,2 +10,3 @@\n dez\n+onze\n doze\n"
        let lines = DiffLines(patch: patch)
        expect(lines.removed == [2], "\(lines.removed)")
        expect(lines.added == [2, 11], "\(lines.added)")
    }),
    ("the panel finds the repository and reads its status; stage and commit", {
        let dir = NSTemporaryDirectory() + "cadex-git-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        git(["init", "--quiet", "--initial-branch=main"], in: dir)
        git(["config", "user.name", "Teste"], in: dir)
        git(["config", "user.email", "t@cadex"], in: dir)
        FileManager.default.createFile(atPath: dir + "/a.txt", contents: Data("a\n".utf8))
        let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
        folder.open(dir)
        var marks: [String: Character] = [:]
        let controller = SourceControlController(folder: folder.root) { _ in true }
        controller.onMarks = { marks = $0 }
        let ready = await eventually { controller.state == .ready && controller.status.entries.count == 1 }
        expect(ready, "\(controller.state) \(controller.status)")
        expect(marks[folder.root + "/a.txt"] == "?", "\(marks)")
        controller.stageAll()
        _ = await eventually { controller.status.entries.first?.isStaged == true }
        controller.panel.messageForTests("primeiro commit")
        controller.commit()
        let committed = await eventually { controller.status.entries.isEmpty && controller.status.oid != "(initial)" }
        expect(committed, "\(controller.status)")
        try? FileManager.default.removeItem(atPath: dir)
    }),
])
exit(exitCode)
