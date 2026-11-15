import Foundation
import Checks
@testable import Review

// Tests of the review feature's comments. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

func comment(_ lines: [String], start: Int, before: [String] = [], after: [String] = [], body: String = "fix") -> ReviewComment {
    ReviewComment(path: "a.swift", old: false, start: start, end: start + lines.count - 1, lines: lines, before: before, after: after, body: body)
}

let exitCode = await Checks.run([
    ("a comment follows its lines when the agent adds lines above, and picks the copy whose context agrees", {
        let c = comment(["let x = 1"], start: 3, before: ["func a() {"], after: ["}"])
        let moved = c.placed(in: ["// new", "// new", "import A", "func a() {", "let x = 1", "}"])
        expect(moved.start == 5 && moved.end == 5 && !moved.stale, "\(moved.start)")
        let twice = c.placed(in: ["func b() {", "let x = 1", "}", "func a() {", "let x = 1", "}"])
        expect(twice.start == 5, "the context says which copy: \(twice.start)")
        let gone = c.placed(in: ["func a() {", "let y = 2", "}"])
        expect(gone.stale && gone.start == 3, "stale keeps where it was")
        expect(gone.placed(in: ["func a() {", "let x = 1", "}"]).stale == false, "back when the lines come back")
    }),
    ("the list survives the app: add, edit, delete, sent ones go to the history", {
        let dir = NSTemporaryDirectory() + "cadex-review-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = ReviewCommentStore(repo: "app", worktree: "fix-login", dir: dir)
        expect(store.path.hasSuffix("/app/fix-login.json"), store.path)
        let comments = ReviewComments(store: store)
        var changes = 0
        comments.onChange = { changes += 1 }
        let first = comment(["a"], start: 1, body: "one")
        comments.add(first)
        comments.add(comment(["b"], start: 9, body: "two"))
        comments.edit(first.id, body: "one, edited")
        let again = ReviewComments(store: store)
        expect(again.pending.count == 2 && again.pending[0].body == "one, edited", "\(again.pending.map(\.body))")
        let text = again.message(worktree: "fix-login", order: ["a.swift"]) ?? ""
        expect(text.contains("1. a.swift, line 1:\n   > a\n   one, edited") && text.contains("2. a.swift, line 9:"), text)
        again.markSent(text)
        let later = ReviewComments(store: store)
        expect(later.pending.isEmpty && later.sent.count == 1 && later.sent[0].comments.count == 2)
        later.add(comment(["c"], start: 2))
        later.delete(later.pending[0].id)
        expect(later.pending.isEmpty && changes == 3, "\(changes)")
        expect(ReviewCommentStore.safe("../x/y") == "-x-y", ReviewCommentStore.safe("../x/y"))
    }),
    ("placing again: a file gone from the review makes its comments stale; the order follows the files", {
        let dir = NSTemporaryDirectory() + "cadex-review-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let comments = ReviewComments(store: ReviewCommentStore(repo: "r", worktree: "w", dir: dir))
        var b = comment(["x"], start: 4)
        b.path = "b.swift"
        comments.add(b)
        comments.add(comment(["y"], start: 2))
        comments.place { path, _ in path == "a.swift" ? ["q", "y"] : nil }
        expect(comments.pending.first { $0.path == "b.swift" }?.stale == true)
        expect(comments.sorted(["a.swift", "b.swift"]).map(\.path) == ["a.swift", "b.swift"])
    }),
])
exit(exitCode)
