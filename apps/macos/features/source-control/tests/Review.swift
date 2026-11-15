import AppKit
import Checks
@testable import Explorer
@testable import SourceControl

// The review tab (plan 21, phase B2): the rows, the mapping to the patch
// git stages from, and a real repository reviewed and staged by change.

func gitOutput(_ args: [String], in dir: String) -> String {
    let p = Process()
    let pipe = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["git"] + args
    p.currentDirectoryURL = URL(fileURLWithPath: dir)
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    try? p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// A file of `count` lines "l1"… with line `n` of `changed` turned into "L<n>".
func sample(_ count: Int, changed: Set<Int> = []) -> String {
    (1...count).map { changed.contains($0) ? "L\($0)" : "l\($0)" }.joined(separator: "\n") + "\n"
}

func patchFor(_ changes: [Int], total: Int) -> String {
    var patch = "diff --git a/f b/f\n--- a/f\n+++ b/f\n"
    for n in changes {
        let start = max(n - 3, 1)
        let end = min(n + 3, total)
        patch += "@@ -\(start),\(end - start + 1) +\(start),\(end - start + 1) @@\n"
        for i in start...end { patch += i == n ? "-l\(i)\n+L\(i)\n" : " l\(i)\n" }
    }
    return patch
}

@MainActor
func reviewFile(_ path: String, changes: [Int], total: Int) -> ReviewFileDiff {
    let file = GitRepository.ReviewFile(status: "M", added: changes.count, removed: changes.count, path: path, orig: "")
    return ReviewFileDiff(file: file, diff: GitRepository.Diff(before: sample(total), after: sample(total, changed: Set(changes)),
                                                               patch: patchFor(changes, total: total), binary: false, tooLarge: false))
}

let reviewChecks: [(name: String, body: Checks.Body)] = [
    ("the rows: a header, the changes with 3 lines around, the rest folded and opened on demand", {
        let files = [reviewFile("a.txt", changes: [10, 25], total: 40)]
        var options = ReviewLayout.Options()
        let layout = ReviewLayout(files: files, options: options) { _ in nil }
        expect(layout.fileStarts == [0] && layout.changeStarts.count == 2, "\(layout.changeStarts)")
        let folds = layout.rows.compactMap { if case .fold(_, let region, let count) = $0 { return (region, count) } else { return nil } }
        // 1–6 before the first change, 14–21 between, 29–40 after.
        expect(folds.map(\.1) == [6, 8, 12], "\(folds)")
        expect(ReviewLayout.text(of: layout.rows[layout.changeStarts[0]], in: files) == "l10", "the removed line first")
        options.opened.insert("0:1")
        expect(ReviewLayout(files: files, options: options) { _ in nil }.rows.count == layout.rows.count + 7, "the middle fold opens")
        options.showAll = true
        let all = ReviewLayout(files: files, options: options) { _ in nil }
        expect(!all.rows.contains { if case .fold = $0 { return true } else { return false } })
    }),
    ("annotations: under their line, a folded line opened, a stale one at the top; the marked lines with their context", {
        let files = [reviewFile("a.txt", changes: [10, 25], total: 40)]
        let note = ReviewAnnotation(id: "n1", path: "a.txt", old: false, line: 18, title: "a.txt, line 18", text: "why?", stale: false)
        let stale = ReviewAnnotation(id: "n2", path: "a.txt", old: false, line: 99, title: "gone", text: "old", stale: true)
        let layout = ReviewLayout(files: files, options: .init(), annotations: [note, stale]) { _ in nil }
        expect(layout.rows[1] == .annotation(file: 0, index: 1), "stale under the header: \(layout.rows[1])")
        guard let at = layout.rows.firstIndex(of: .annotation(file: 0, index: 0)) else { return expect(false, "no note") }
        expect(layout.rows[at - 1] == .line(file: 0, kind: .context, old: 18, new: 18, change: nil), "\(layout.rows[at - 1])")
        expect(layout.changeStarts.count == 2)
        let review = ReviewDocument(request: .init(repo: "/nonexistent", base: "HEAD"))
        review.files = files
        review.relayout()
        guard let row = review.text.layout.rows.firstIndex(of: .line(file: 0, kind: .added, old: nil, new: 10, change: 0)) else { return expect(false, "no line 10") }
        review.text.go(to: row)
        let selection = review.markedSelection()
        expect(selection == ReviewLineSelection(path: "a.txt", old: false, start: 10, end: 10, lines: ["L10"], before: ["l7", "l8", "l9"], after: ["l11", "l12", "l13"]),
               "\(String(describing: selection))")
    }),
    ("a new file is all added lines; a binary says so", {
        let new = GitRepository.ReviewFile(status: "?", added: 2, removed: 0, path: "n.txt", orig: "")
        let diff = ReviewFileDiff(file: new, diff: GitRepository.Diff(before: "", after: "x\ny\n", patch: "@@ -0,0 +1,2 @@\n+x\n+y\n", binary: false, tooLarge: false))
        let layout = ReviewLayout(files: [diff], options: .init()) { _ in nil }
        expect(layout.rows == [.header(file: 0), .line(file: 0, kind: .added, old: nil, new: 1, change: 0), .line(file: 0, kind: .added, old: nil, new: 2, change: 0)], "\(layout.rows)")
        let binary = ReviewLayout(files: [diff], options: .init()) { _ in "Binary file" }
        expect(binary.rows == [.header(file: 0), .note(file: 0, text: "Binary file")])
    }),
    ("marked lines map to the unstaged patch by number, removed ones by text and place; unstaging by text", {
        let patch = "diff --git a/a b/a\n--- a/a\n+++ b/a\n@@ -1,3 +1,4 @@\n one\n-two\n+TWO\n three\n+four\n"
        let four = ReviewStaging.Marked(kind: .added, text: "four", anchor: 4)
        expect(ReviewStaging.indices(of: [four], in: patch, unstage: false) == [8])
        let two = ReviewStaging.Marked(kind: .removed, text: "two", anchor: 2)
        let upper = ReviewStaging.Marked(kind: .added, text: "TWO", anchor: 2)
        expect(ReviewStaging.indices(of: [two, upper], in: patch, unstage: false) == [5, 6])
        expect(ReviewStaging.indices(of: [ReviewStaging.Marked(kind: .removed, text: "two", anchor: 40)], in: patch, unstage: false).isEmpty, "too far")
        expect(ReviewStaging.indices(of: [ReviewStaging.Marked(kind: .added, text: "four", anchor: 99)], in: patch, unstage: true) == [8])
    }),
    ("50 files with 100 changes each lay out fast", {
        let files = (0..<50).map { reviewFile("f\($0).txt", changes: Array(stride(from: 5, to: 1000, by: 10)), total: 1000) }
        let start = Date()
        let layout = ReviewLayout(files: files, options: .init()) { _ in nil }
        let seconds = Date().timeIntervalSince(start)
        expect(layout.fileStarts.count == 50 && layout.changeStarts.count == 5000, "\(layout.changeStarts.count)")
        expect(seconds < 1.5, "\(seconds) s")
    }),
    ("a real task reviewed against main: files, j/k, and one change staged", {
        let dir = NSTemporaryDirectory() + "cadex-review-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "T"], ["config", "user.email", "t@cadex"]] { git(args, in: dir) }
        FileManager.default.createFile(atPath: dir + "/a.txt", contents: Data("one\ntwo\nthree\n".utf8))
        git(["add", "."], in: dir)
        git(["commit", "-qm", "start"], in: dir)
        git(["switch", "-qc", "task"], in: dir)
        FileManager.default.createFile(atPath: dir + "/a.txt", contents: Data("one\nTWO\nthree\n".utf8))
        git(["commit", "-qam", "agent"], in: dir)
        FileManager.default.createFile(atPath: dir + "/a.txt", contents: Data("one\nTWO\nthree\nfour\n".utf8))
        FileManager.default.createFile(atPath: dir + "/b.txt", contents: Data("new\n".utf8))
        let real = URL(fileURLWithPath: dir).resolvingSymlinksInPath().path
        WorkspaceFolder(arguments: ["Cadex"], cwd: "/").open(real)  // the core runs git only in authorized folders
        let review = ReviewDocument(request: .init(repo: real, start: "main"))
        let loaded = await eventually { review.files.count == 2 }
        expect(loaded, "\(review.files.map(\.file))")
        guard review.files.map(\.file.path) == ["a.txt", "b.txt"], review.text.layout.fileStarts.count == 2 else { return expect(false, "\(review.files.map(\.file))") }
        review.nextFile()
        expect(review.text.cursor == review.text.layout.fileStarts[1], "j goes to b.txt")
        review.previousFile()
        guard let four = review.text.layout.rows.firstIndex(where: { ReviewLayout.text(of: $0, in: review.files) == "four" }) else { return expect(false, "no four") }
        review.text.go(to: four)
        review.stageChange(unstage: false)
        let staged = await eventually { gitOutput(["diff", "--cached"], in: real).contains("+four") }
        expect(staged, gitOutput(["diff", "--cached"], in: real))
        expect(!gitOutput(["diff", "--cached"], in: real).contains("+TWO"), "the committed change is not staged again")
    }),
]
