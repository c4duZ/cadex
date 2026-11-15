import Foundation
import Checks
@testable import Review

// Line authorship (plan 21 phase E): marks that follow unchanged lines, an
// agent's edit marking its lines, the owner's edit taking them, the limits.

let authorshipChecks: [(name: String, body: Checks.Body)] = [
    ("marks follow unchanged lines; changed ones lose them; an edit adds its lines", {
        let marks = [AuthorRange(start: 2, end: 3, session: "s1")]
        let moved = Authorship.carry(marks, from: ["a", "b", "c", "d"], to: ["new", "a", "b", "C", "d"])
        expect(moved == [AuthorRange(start: 3, end: 3, session: "s1")], "\(moved)")
        let added = Authorship.add(moved, lines: [4...5], session: "s2")
        expect(added == [AuthorRange(start: 3, end: 3, session: "s1"), AuthorRange(start: 4, end: 5, session: "s2")], "\(added)")
    }),
    ("a tracked worktree: the agent's edit, then the owner's, then too big; ranges kept, never text", {
        let dir = NSTemporaryDirectory() + "cadex-authorship-\(UUID().uuidString)"
        let root = dir + "/wt"
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        FileManager.default.createFile(atPath: root + "/a.txt", contents: Data("one\ntwo\nthree\n".utf8))
        let tracker = ReviewAuthorshipTracker(root: root, repo: "app", worktree: "wt", dir: dir + "/store")
        tracker.record(path: root + "/a.txt", lines: [2...2], whole: false, session: "s1")
        expect(tracker.marks(of: "a.txt") == [2: "s1"])
        // The owner adds a line above and edits line two: the mark goes.
        FileManager.default.createFile(atPath: root + "/a.txt", contents: Data("zero\none\nTWO!\nthree\n".utf8))
        tracker.diskChanged(folders: [root])
        expect(tracker.marks(of: "a.txt").isEmpty, "\(tracker.marks(of: "a.txt"))")
        // A Write that makes a file marks it whole.
        FileManager.default.createFile(atPath: root + "/n.txt", contents: Data("x\ny\n".utf8))
        tracker.record(path: root + "/n.txt", lines: [], whole: true, session: "s2")
        expect(tracker.marks(of: "n.txt") == [1: "s2", 2: "s2"])
        let again = ReviewAuthorshipTracker(root: root, repo: "app", worktree: "wt", dir: dir + "/store")
        expect(again.marks(of: "n.txt") == [1: "s2", 2: "s2"], "kept on disk")
        let json = (try? String(contentsOfFile: dir + "/store/app/wt-authorship.json", encoding: .utf8)) ?? ""
        expect(!json.contains("zero") && !json.contains("TWO"), "ranges, not text: \(json)")
        FileManager.default.createFile(atPath: root + "/big.txt", contents: Data(count: ReviewAuthorshipTracker.fileLimit + 1))
        tracker.record(path: root + "/big.txt", lines: [1...1], whole: false, session: "s1")
        expect(tracker.files["big.txt"]?.stopped == true)
        let exported = tracker.export().flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        expect((exported?["files"] as? [[String: Any]])?.count == 3)
        // Removed outside Cadex: the sweep at launch forgets it.
        expect(FileManager.default.fileExists(atPath: dir + "/store/app/wt-versions"))
        try? FileManager.default.removeItem(atPath: root)
        ReviewAuthorshipTracker.sweep(dir: dir + "/store")
        expect(!FileManager.default.fileExists(atPath: dir + "/store/app/wt-authorship.json")
               && !FileManager.default.fileExists(atPath: dir + "/store/app/wt-versions"), "swept")
    }),
]
