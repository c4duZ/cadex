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
    ("in the sidebar the history shows the graph and the subject on one line, nothing else", {
        let repo = mergedRepository()
        let document = HistoryDocument(root: repo)
        document.compact = true
        _ = await eventually { document.state == .ready && document.commits.count == 4 }
        let table = document.historyView.table
        let shown = table.tableColumns.filter { !$0.isHidden }.map(\.identifier.rawValue)
        expect(shown == ["graph", "subject"] && table.headerView == nil, "\(shown)")
        let subject = HistoryRows.subject(document.commits[0])
        let style = subject.attribute(.paragraphStyle, at: subject.length - 1, effectiveRange: nil) as? NSParagraphStyle
        expect(style?.lineBreakMode == .byTruncatingTail, "the subject never wraps over the next row")
        document.compact = false
        expect(table.tableColumns.allSatisfy { !$0.isHidden } && table.headerView != nil, "the tab gets its columns back")
        document.compact = true
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] {
            let view = document.view
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/history-compact.png"))
            }
        }
        try? FileManager.default.removeItem(atPath: repo)
    }),
    ("in the sidebar, hidden and sized late as the app builds it, the list still gets the height", {
        let repo = mergedRepository()
        let host = NSView()
        let outer = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let window = NSWindow(contentRect: outer.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = outer
        host.translatesAutoresizingMaskIntoConstraints = false
        host.isHidden = true
        outer.addSubview(host)
        NSLayoutConstraint.activate([host.topAnchor.constraint(equalTo: outer.topAnchor), host.bottomAnchor.constraint(equalTo: outer.bottomAnchor),
                                     host.leadingAnchor.constraint(equalTo: outer.leadingAnchor), host.trailingAnchor.constraint(equalTo: outer.trailingAnchor)])
        let document = HistoryDocument(root: repo)
        document.compact = true
        let view = document.view
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: host.topAnchor), view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                                     view.leadingAnchor.constraint(equalTo: host.leadingAnchor), view.trailingAnchor.constraint(equalTo: host.trailingAnchor)])
        host.isHidden = false
        _ = await eventually { document.state == .ready && document.commits.count == 4 }
        outer.layoutSubtreeIfNeeded()
        let table = document.historyView.table
        let listHeight = table.enclosingScrollView?.frame.height ?? 0
        expect(table.numberOfRows > 0 && listHeight > 200, "rows \(table.numberOfRows), list \(listHeight) high")
        (table.dataSource as? HistoryCompactRows)?.press(0)
        _ = await eventually { table.numberOfRows == 5 }
        outer.layoutSubtreeIfNeeded()
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"], let bitmap = outer.bitmapImageRepForCachingDisplay(in: outer.bounds) {
            outer.cacheDisplay(in: outer.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/history-repro.png"))
        }
        try? FileManager.default.removeItem(atPath: repo)
    }),
    ("the sidebar's rows: a commit opens its files under it, a file opens its diff, a click closes it", {
        expect(HistoryCompactRows.items(commits: 3, expandedAt: 1, files: 2) == [.commit(0), .commit(1), .file(1, 0), .file(1, 1), .commit(2)])
        expect(HistoryCompactRows.items(commits: 2, expandedAt: nil, files: 5) == [.commit(0), .commit(1)])
        let tipped = HistoryCommit(sha: "abc1234567", parents: [], author: "Ana", email: "a@x", date: Date(timeIntervalSince1970: 0),
                                   refs: ["HEAD -> main", "origin/main"], subject: "a subject far too long for 240 points", graph: nil)
        let tip = HistoryCompactRows.tip(tipped).split(separator: "\n").map(String.init)
        expect(tip.count == 5 && tip[0] == "a subject far too long for 240 points" && tip[1] == "main, origin/main"
               && tip[2] == "Ana <a@x>" && tip[4] == "abc1234567", "\(tip)")
        let repo = mergedRepository()
        let document = HistoryDocument(root: repo)
        document.compact = true
        _ = await eventually { document.state == .ready && document.commits.count == 4 }
        let table = document.historyView.table
        expect(table.numberOfRows == 4 && table.delegate?.tableView?(table, heightOfRow: 0) ?? 0 > 30, "two lines per commit")
        let rows = table.dataSource as? HistoryCompactRows
        rows?.press(0)
        let opened = await eventually { table.numberOfRows == 5 }
        expect(opened, "the merge's file shows under it: \(table.numberOfRows) rows")
        var diffs: [String] = []
        document.onOpenDiff = { _, _, path, _ in diffs.append(path) }
        rows?.press(1)
        expect(diffs == ["b.txt"], "\(diffs)")
        rows?.press(0)
        expect(table.numberOfRows == 4, "a second click closes it")
        let sha = document.commits[2].sha
        let other = HistoryDocument(root: repo)
        other.select(sha: sha)
        let picked = await eventually { other.selectedSha == sha }
        expect(picked, "a SHA asked before the log came is selected when it comes")
        try? FileManager.default.removeItem(atPath: repo)
    }),
])
exit(exitCode)
