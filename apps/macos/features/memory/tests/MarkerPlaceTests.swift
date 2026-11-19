import Checks
import Foundation
@testable import Memory

// The .ai-memory.toml Cadex makes in every project and the "only on this Mac" line (plan 35 B).

func markerPlaceTests() -> [(name: String, body: Checks.Body)] { [
    ("the template is upstream's project init, the brief on, the rest commented at upstream's defaults", {
        expect(MemoryMarker.template(project: "my \"app\"").contains("project = \"my \\\"app\\\"\""), "quoted as TOML")
        let text = MemoryMarker.template(project: "app")
        let marker = MemoryMarker.read(text)
        expect(marker.workspace == "default" && marker.project == "app", "\(marker)")
        expect(marker.briefing, "the brief on, written")
        var defaults = MemoryMarker()
        defaults.workspace = marker.workspace
        defaults.project = marker.project
        defaults.briefing = true
        expect(marker == defaults, "every other key at its default\n\(text)")
        for commented in ["# max_chars = 4000", "# inject_on_subagent_start = false", "# contribute = true", "# consume = true", "# ignore_paths = []"] {
            expect(text.contains(commented), commented)
        }
        expect(text.contains("docs/marker-file.md"), "says what the file is")
        // The screen edits it: a key written lands in its table, the comments stay.
        var edited = marker
        edited.briefingChars = 6000
        let out = edited.written(over: text)
        expect(out.contains("# inject_on_subagent_start = false\nmax_chars = 6000"), out)
        expect(MemoryMarker.read(out).briefingChars == 6000 && out.contains("# Cadex made this file"), out)
    }),
    ("ensure makes the file once, named as the memory names the project, and never overwrites", {
        let repo = scratch() + "/shop"
        try? fm.createDirectory(atPath: repo + "/.git", withIntermediateDirectories: true)
        expect(MemoryMarker.ensure(folder: repo), "made")
        let path = repo + "/" + MemoryMarker.fileName
        let made = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        expect(MemoryMarker.read(made).project == "shop", made)
        try? "project = \"mine\"\n".write(toFile: path, atomically: true, encoding: .utf8)
        expect(!MemoryMarker.ensure(folder: repo), "not again")
        expect((try? String(contentsOfFile: path, encoding: .utf8)) == "project = \"mine\"\n", "the owner's file stays")
        let left = (try? fm.contentsOfDirectory(atPath: repo)) ?? []
        expect(!left.contains { $0.hasSuffix(".tmp") }, "no temporary file left: \(left)")
        expect(!MemoryMarker.ensure(folder: repo + "/missing"), "no folder, no file")
    }),
    ("a worktree's file names the main checkout, and only on this Mac goes in the common dir's exclude", {
        let base = scratch()
        let main = base + "/app"
        try? fm.createDirectory(atPath: main + "/.git/worktrees/task", withIntermediateDirectories: true)
        let tree = base + "/app-task"
        try? fm.createDirectory(atPath: tree, withIntermediateDirectories: true)
        try? "gitdir: \(main)/.git/worktrees/task\n".write(toFile: tree + "/.git", atomically: true, encoding: .utf8)
        try? "../..\n".write(toFile: main + "/.git/worktrees/task/commondir", atomically: true, encoding: .utf8)
        expect(MemoryMarker.projectName(folder: tree) == "app", MemoryMarker.projectName(folder: tree))
        let exclude = MemoryProject.canonical(main) + "/.git/info/exclude"
        expect(MemoryMarkerPlace.excludeFile(folder: tree) == exclude, "\(String(describing: MemoryMarkerPlace.excludeFile(folder: tree)))")
        expect(!MemoryMarkerPlace.isLocalOnly(folder: main))
        try? fm.createDirectory(atPath: main + "/.git/info", withIntermediateDirectories: true)
        try? "# git ls-files --others --exclude-from=.git/info/exclude\n*.log".write(toFile: exclude, atomically: true, encoding: .utf8)
        expect(MemoryMarkerPlace.setLocalOnly(true, folder: tree))
        expect(MemoryMarkerPlace.setLocalOnly(true, folder: main))
        let on = (try? String(contentsOfFile: exclude, encoding: .utf8)) ?? ""
        expect(on == "# git ls-files --others --exclude-from=.git/info/exclude\n*.log\n/.ai-memory.toml\n", on)
        expect(MemoryMarkerPlace.isLocalOnly(folder: tree) && MemoryMarkerPlace.isLocalOnly(folder: main))
        expect(MemoryMarkerPlace.setLocalOnly(false, folder: main))
        let off = (try? String(contentsOfFile: exclude, encoding: .utf8)) ?? ""
        expect(off == "# git ls-files --others --exclude-from=.git/info/exclude\n*.log\n", off)
        expect(!MemoryMarkerPlace.setLocalOnly(true, folder: scratch()), "outside git: nothing to write")
    }),
    ("the exclude edit is exact: another line that only looks like it stays", {
        expect(MemoryMarkerPlace.excluding(true, in: "") == "/.ai-memory.toml\n")
        expect(MemoryMarkerPlace.excluding(false, in: ".ai-memory.toml\nx") == ".ai-memory.toml\nx", "not ours, untouched")
        expect(MemoryMarkerPlace.excluding(false, in: "a\n/.ai-memory.toml\nb\n") == "a\nb\n")
    }),
] }
