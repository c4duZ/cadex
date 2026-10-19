import AppKit
import Checks
@testable import Explorer
@testable import GitHistory

// Tests of the git-history feature. Run with `make macos-test` (see
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

func commit(_ name: String, in dir: String) {
    FileManager.default.createFile(atPath: dir + "/" + name, contents: Data("\(name)\n".utf8))
    git(["add", "--", name], in: dir)
    git(["commit", "--quiet", "-m", "adiciona \(name)"], in: dir)
}

/// A repository with a feature branch merged into main, authorized.
@MainActor
func mergedRepository() -> String {
    let dir = NSTemporaryDirectory() + "cadex-history-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    git(["init", "--quiet", "--initial-branch=main"], in: dir)
    git(["config", "user.name", "Ana"], in: dir)
    git(["config", "user.email", "ana@cadex"], in: dir)
    commit("a.txt", in: dir)
    git(["switch", "--quiet", "-c", "feature"], in: dir)
    commit("b.txt", in: dir)
    git(["switch", "--quiet", "main"], in: dir)
    commit("c.txt", in: dir)
    git(["merge", "--quiet", "--no-ff", "-m", "junta feature", "feature"], in: dir)
    let folder = WorkspaceFolder(arguments: ["Cadex"], cwd: "/")
    folder.open(dir)
    return folder.root
}

let exitCode = await Checks.run([
    ("a log line becomes a commit with its graph row", {
        let line = "abc1234def\tp1 p2\tAna\tana@x\t1700000000\tHEAD -> main, tag: v1\tolá 🎉\t1\t3\t0,0,0 1,1,3\t0,0,0 1,2,5"
        guard let c = HistoryCommit.parse(Substring(line)) else { return expect(false, "no commit") }
        expect(c.parents == ["p1", "p2"] && c.refs == ["HEAD -> main", "tag: v1"] && c.subject == "olá 🎉", "\(c)")
        expect(c.graph?.column == 1 && c.graph?.color == 3, "\(String(describing: c.graph))")
        expect(c.graph?.bottom.last == .init(from: 1, to: 2, color: 5))
        expect(c.graph?.width == 3)
        let search = HistoryCommit.parse(Substring("abc\t\tAna\ta@x\t0\t\tx\t-1\t0\t\t"))
        expect(search?.graph == nil && search?.parents == [])
        let subject = HistoryRows.subject(c).string
        expect(subject.contains(" main ") && subject.contains(" v1 ") && subject.hasSuffix("olá 🎉"), subject)
    }),
    ("a commit's details: parents, message and files with +/−", {
        let d = CommitDetails.parse("p1 p2\u{1e}junta\n\ncorpo\n\u{1e}M\t3\t1\ta.zig\t\nR\t0\t0\tnovo.txt\tvelho.txt\nA\t-\t-\timg.png\t\n")
        expect(d.parents == ["p1", "p2"] && d.message == "junta\n\ncorpo", "\(d)")
        expect(d.files.count == 3 && d.files[1].orig == "velho.txt" && d.files[2].added == nil, "\(d.files)")
        expect(HistoryDetailsView.line(d.files[0]).string == "M  a.zig  +3 −1")
    }),
    ("the tab loads the log with the graph, details, the search and a new commit", {
        let repo = mergedRepository()
        let document = HistoryDocument(root: repo)
        let loaded = await eventually { document.state == .ready && document.commits.count == 4 }
        expect(loaded, "\(document.state) \(document.commits.count)")
        let merge = document.commits.first
        expect(merge?.subject == "junta feature" && merge?.parents.count == 2 && merge?.graph != nil, "\(String(describing: merge))")
        expect(document.historyView.table.numberOfRows == 4)

        document.select(merge)
        let detailed = await eventually { document.details != nil }
        expect(detailed && document.details?.files.map(\.path) == ["b.txt"], "\(String(describing: document.details))")
        var opened: [String] = []
        document.onOpenDiff = { _, sha, path, _ in opened = [sha, path] }
        if let file = document.details?.files.first { document.openDiff(file) }
        expect(opened == [merge?.sha ?? "", "b.txt"], "\(opened)")

        document.setFilter("c.txt")
        expect(document.shown.count == 1 && !document.showsGraph)
        document.searchRepository("ADICIONA")
        let found = await eventually { document.searchResults?.count == 3 }
        expect(found, "\(String(describing: document.searchResults?.count))")
        document.setFilter("")
        expect(document.shown.count == 4 && document.showsGraph)

        commit("d.txt", in: repo)
        document.diskChanged([repo + "/.git/refs/heads"])
        let updated = await eventually { document.commits.first?.subject == "adiciona d.txt" && document.commits.count == 5 }
        expect(updated, "\(document.commits.map(\.subject))")
        try? FileManager.default.removeItem(atPath: repo)
    }),
])
exit(exitCode)
