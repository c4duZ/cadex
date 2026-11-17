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
    ("the check line: which commands are a check, and its words", {
        for line in ["make check", "npm test", "swift build -c release", "pytest -q", "cargo clippy --tests", "make macos-test"] {
            expect(CheckLine.isCheck(line), line)
        }
        for line in ["ls", "git status", "make", "npm install", "python3 -m http.server 5173"] { expect(!CheckLine.isCheck(line), line) }
        let now = Date()
        expect(CheckLine.text("make check", passed: true, endedAt: now - 130, now: now) == "make check passed · 2 min ago")
        expect(CheckLine.text("npm test", passed: false, endedAt: now, now: now) == "npm test failed · now")
    }),
    ("status lines from the core become entries and rows", {
        let s = GitRepository.parseStatus("main\tabc\torigin/main\t1\t2\n0\tM\t.\ta.zig\t\n0\t.\tM\tb.zig\t\n1\tR\t.\tnovo.txt\tvelho.txt\n3\t?\t?\tnovo.md\t\n")
        expect(s.branch == "main" && s.ahead == 1 && s.behind == 2)
        expect(s.entries.count == 4)
        expect(s.entries[0].isStaged && !s.entries[0].isUnstaged)
        expect(s.entries[3].isUnstaged && s.entries[3].letter(staged: false) == "?")
        // Changes' rows (plan 26 C2): the counts' files with the status entry of each, by path.
        let files = GitRepository.parseReviewFiles("M\t3\t1\tcore/a.zig\t\n?\t-\t-\tnovo.md\t\nM\t2\t0\tdocs/c.md\t\n")
        let rows = ChangesRow.rows(files, entries: s.entries, keep: nil)
        expect(rows.map(\.name) == ["a.zig", "novo.md", "c.md"] && rows[0].folder == "core" && rows[1].letter == "A", "\(rows)")
        expect(rows[1].entry?.path == "novo.md" && rows[2].entry == nil, "a file changed only in commits has no entry")
        expect(ChangesRow.rows(files, entries: s.entries, keep: ["docs/c.md"]).map(\.name) == ["c.md"], "the last turn keeps its files")
    }),
    ("a list shows at most 500 files (docs/spec/inspector.md)", {
        let files = (0..<800).map { GitRepository.ReviewFile(status: "?", added: nil, removed: nil, path: "f\($0)", orig: "") }
        expect(ChangesRow.rows(files, entries: [], keep: nil).count == ChangesRow.limit)
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
        // The list reads only while the tab shows (plan 26 C2): on screen, in a window.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = controller.view
        let ready = await eventually { controller.state == .ready && controller.status.entries.count == 1 }
        expect(ready, "\(controller.state) \(controller.status)")
        expect(marks[folder.root + "/a.txt"] == "?", "\(marks)")
        controller.stageAll()
        _ = await eventually { controller.status.entries.first?.isStaged == true }
        let listed = await eventually { controller.changeRows.map(\.name) == ["a.txt"] }
        expect(listed, "uncommitted lists the new file: \(controller.changeRows)")
        controller.scope = .lastTurn
        let noTurn = await eventually { controller.changeRows.isEmpty }
        expect(noTurn, "no turn seen: nothing")
        controller.lastTurnFiles = { _ in [controller.repositoryRoot! + "/a.txt"] }
        controller.scope = .uncommitted
        controller.scope = .lastTurn
        let turn = await eventually { controller.changeRows.map(\.name) == ["a.txt"] }
        expect(turn, "the turn's file: \(controller.changeRows)")
        controller.scope = .uncommitted
        controller.commit(message: "primeiro commit", all: false)
        let committed = await eventually { controller.status.entries.isEmpty && controller.status.oid != "(initial)" }
        expect(committed, "\(controller.status)")
        // Settled first: a read started before hiding may still run and see the new file.
        _ = await eventually { controller.changeRows.isEmpty && !controller.changesRunning }
        controller.view.isHidden = true
        FileManager.default.createFile(atPath: dir + "/b.txt", contents: Data("b\n".utf8))
        controller.refresh()
        _ = await eventually { controller.status.entries.count == 1 }
        expect(controller.changeRows.isEmpty && controller.changesStale, "hidden: nothing read \(controller.changeRows.map(\.name)) \(controller.changesStale)")
        controller.view.isHidden = false
        let shown = await eventually { controller.changeRows.map(\.name) == ["b.txt"] }
        expect(shown, "shown again, it reads: \(controller.changeRows)")
        window.contentView = nil
        try? FileManager.default.removeItem(atPath: dir)
    }),
])
let reviewExit = await Checks.run(reviewChecks)
let conflictExit = await Checks.run(conflictChecks)
exit(exitCode != 0 ? exitCode : (reviewExit != 0 ? reviewExit : conflictExit))
