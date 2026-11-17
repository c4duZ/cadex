import AppKit
import Checks
import Foundation
import UILooks
@testable import Memory

// The Memory page (plan 22 phase H): the CLI's JSON read as the contract
// says (canned answers: the CLI is built apart), the wiki read from a temp
// folder, the origin of each page and the fallback to projects.json.

func write(_ path: String, _ text: String) {
    try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    fm.createFile(atPath: path, contents: Data(text.utf8))
}

/// A stand-in `cadex`: prints its arguments, then stdin, and exits `code`.
func fakeCadex(_ dir: String, code: Int) -> String {
    let path = dir + "/cadex-\(code)"
    let script = "#!/bin/sh\necho \"$@\"\ncat\necho 'warned' >&2\nexit \(code)\n"
    fm.createFile(atPath: path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
    return path
}

@MainActor
func pageTests() -> [(name: String, body: Checks.Body)] { [
    ("overview: down says only that; up gives the wiki, the model and the import by account", {
        expect(MemoryOverview.parse(["running": false]) == MemoryOverview())
        let up = MemoryOverview.parse(["running": true, "workspace": "w", "project": "p", "wiki_dir": "/m/wiki/p", "model": "downloading",
                                       "pages": 42, "sessions": 17,
                                       "imported": ["state": "done", "sessions": 120,
                                                    "accounts": [["dir": "/U/.claude", "sessions": 100], ["dir": "/U/.claude-work", "sessions": 20]]]])
        expect(up.running && up.wikiDir == "/m/wiki/p" && up.pages == 42 && up.sessions == 17)
        expect(up.importState == "done" && up.importedSessions == 120 && up.importedAccounts.map(\.dir) == ["/U/.claude", "/U/.claude-work"])
        expect(MemoryOverview.parse(["running": true, "wiki_dir": NSNull()]).wikiDir == nil, "null wiki_dir")
        let names = MemoryStatusText.imported(up) { $0 == "/U/.claude" ? "Personal" : "Work" } ?? ""
        expect(names.hasSuffix("Personal (100), Work (20)"), names)
        expect(MemoryStatusText.engine(up).contains(MemoryStatusText.model("downloading")))
        expect(MemoryStatusText.counts(MemoryOverview()) == nil, "no counts with the engine down")
    }),
    ("status: down, and the agent's spending, queue and last runs with cost", {
        let down = MemoryAgentStatus.parse(["running": false])
        expect(!down.running && MemoryStatusText.agent(down) == MemoryStatusText.agent(nil))
        let status = MemoryAgentStatus.parse([
            "enabled": true, "paused": true, "spent_today_usd": 0.42, "daily_budget_usd": 1, "proposals_pending": 2, "claude_version": "2.1.0",
            "queue": [["kind": "dream", "project": "p", "state": "waiting"]],
            "recent": [["at": "2026-11-16T10:00:00Z", "kind": "consolidate", "project": "p", "cost_usd": 0.04, "ok": true],
                       ["at": "2026-11-16T11:00:00Z", "kind": "dream", "project": "p", "cost_usd": 0.1, "ok": false, "error": "cap"]],
        ])
        expect(status.running && status.enabled && status.paused && status.proposalsPending == 2 && status.claudeVersion == "2.1.0")
        expect(MemoryStatusText.agent(status).contains("US$ 0.42 / 1.00"), MemoryStatusText.agent(status))
        expect(MemoryStatusText.queue(status) == ["dream · waiting"])
        let now = MemoryJSON.date("2026-11-16T12:00:00Z")!
        let recent = MemoryStatusText.recent(status, now: now)
        expect(recent.count == 2 && recent[0].hasPrefix("dream · US$ 0.10 · 1h") && recent[0].hasSuffix(": cap"), "\(recent)")
        expect(recent[1] == "consolidate · US$ 0.04 · 2h", "\(recent)")
    }),
    ("proposals: listed with their preview, one without an id skipped, ⌘K's words matched", {
        let list = MemoryProposal.parseList(["proposals": [
            ["id": "p1", "title": "Use WAL", "path": "decisions/wal.md", "kind": "decision", "summary": "SQLite in WAL mode",
             "created_at": "2026-11-16T10:00:00.123Z", "body": "---\ntitle: x\n\nLine one\nLine two"],
            ["title": "no id"],
            ["id": "p3", "path": "gotchas/tz.md"],
        ]])
        expect(list.map(\.id) == ["p1", "p3"], "\(list.map(\.id))")
        expect(list[0].createdAt != nil, "fractional seconds")
        expect(list[1].title == "gotchas/tz.md", "the path when untitled")
        expect(list[0].preview.contains("Line one"))
        expect(MemoryProposalSource.matching(list, "wal sqlite").map(\.id) == ["p1"])
        expect(MemoryProposalSource.matching(list, "").count == 2)
    }),
    ("the wiki as a tree: folders by name, pages newest first, no dotfiles, .git or non-Markdown", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        write(dir + "/sessions/0a1b2c3d-1111-2222-3333-444455556666.md", "---\ntitle: \"Fix the login\"\nagent: claude\nupdated_at: 2026-11-16T10:00:00Z\n---\nbody")
        write(dir + "/decisions/wal.md", """
            ---
            title: 'Use WAL'
            kind: decision
            session_id: abcdef12-0000
            sources:
              - resource: session:abcdef12-0000
                author: claude-code
            generated:
              by: memory-agent
              at: 2026-11-15T10:00:00Z
            ---
            We use WAL.
            """)
        write(dir + "/decisions/older.md", "---\ntitle: Older\nupdated_at: 2026-11-01T10:00:00Z\n---\n")
        write(dir + "/_rules/style.md", "No frontmatter here.")
        write(dir + "/.git/HEAD", "ref")
        write(dir + "/.hidden.md", "x")
        write(dir + "/notes.txt", "x")
        let tree = MemoryWiki.tree(dir)
        expect(tree.folders.map(\.name) == ["_rules", "decisions", "sessions"], "\(tree.folders.map(\.name))")
        expect(tree.pages.isEmpty && tree.count == 4, "\(tree.count)")
        let decisions = tree.folders[1].pages
        expect(decisions.map(\.title) == ["Use WAL", "Older"], "\(decisions.map(\.title))")
        expect(decisions[0].sessionID == "abcdef12-0000" && decisions[0].kind == "decision" && decisions[0].agent == "claude-code")
        expect(decisions[0].relative == "decisions/wal.md")
        let session = tree.folders[2].pages[0]
        expect(session.title == "Fix the login" && session.sessionID == "0a1b2c3d-1111-2222-3333-444455556666", "the id from sessions/<id>.md")
        expect(tree.folders[0].pages[0].title == "style" && tree.folders[0].pages[0].sessionID == nil, "no frontmatter: the file's name")
        let now = MemoryJSON.date("2026-11-16T13:00:00Z")!
        expect(MemoryStatusText.origin(session, account: "Work", now: now).hasSuffix("0a1b2c3d · Work · 3h"))
        expect(MemoryStatusText.origin(session, account: nil, now: now).hasSuffix("0a1b2c3d · claude · 3h"), "the agent without the History")
    }),
    ("frontmatter: a session named only by a source; a page without one has none", {
        let front = MemoryFrontmatter.parse("---\ntitle: A: b\nsources:\n- resource: sessions/99aa.md\n  author: x\ntags: [a, b]\n---\n")
        expect(front.scalar("title") == "A: b")
        expect(MemoryWiki.sessionID(front, relative: "concepts/a.md") == "99aa")
        expect(MemoryWiki.sessionID(MemoryFrontmatter.parse("---\ntitle: x\n---"), relative: "concepts/a.md") == nil)
        expect(MemoryWiki.sessionID(MemoryFrontmatter(), relative: "sessions/deep/x.md") == nil, "only sessions/<id>.md")
        expect(MemoryFrontmatter.parse("title: not fenced").scalar("title") == nil)
    }),
    ("off: the page's state says so and nothing else is read", {
        let off = MemoryPageState(enabled: false)
        expect(!off.enabled && off.overview == nil && off.tree == nil)
        expect(!MemoryStatusText.offText.isEmpty)
        let view = MemoryView()
        view.show(off)
        expect(view.state?.enabled == false && !view.isShowing, "not on screen: it never asked")
    }),
    ("projects.json: the wiki with the engine down, by root or key; the overview's wins; a saved page finds its project", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let key = MemoryProject.key(root: "/r/two")
        write(dir + "/projects.json", """
            {"projects":[{"workspace":"w","project":"p1","root":"/r/one","wiki_dir":"\(dir)/wiki/one"},
                         {"workspace":"w","project":"\(key)","root":"/elsewhere","wiki_dir":"\(dir)/wiki/two"},
                         {"workspace":"w","project":"p3","root":"/r/three","wiki_dir":""}]}
            """)
        expect(MemoryPageState.wikiDir(overview: nil, root: "/r/one", folder: dir) == dir + "/wiki/one")
        expect(MemoryPageState.wikiDir(overview: nil, root: "/r/two", folder: dir) == dir + "/wiki/two", "by the key")
        expect(MemoryPageState.wikiDir(overview: nil, root: "/r/three", folder: dir) == nil, "no wiki_dir")
        var overview = MemoryOverview()
        overview.wikiDir = "/from/overview"
        expect(MemoryPageState.wikiDir(overview: overview, root: "/r/one", folder: dir) == "/from/overview")
        expect(MemoryProjects.entry(holding: dir + "/wiki/one/decisions/a.md", folder: dir)?.root == "/r/one")
        expect(MemoryProjects.entry(holding: dir + "/wiki/onex/a.md", folder: dir) == nil, "a prefix is not a folder")
        expect(MemoryProjects.read(folder: dir + "/none").isEmpty)
    }),
    ("the CLI's plain text (briefing) and stdin (write-page); stderr only for an empty stdout", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let text: (Int32, String) = await withCheckedContinuation { done in
            MemoryAgent.runText(tools: fakeCadex(dir, code: 0), words: ["briefing", "--cwd", "/r"], environment: [:]) { done.resume(returning: ($0, $1)) }
        }
        expect(text.0 == 0 && text.1 == "memory-agent briefing --cwd /r\n", "\(text)")
        let script = dir + "/json"
        fm.createFile(atPath: script, contents: Data("#!/bin/sh\nbody=$(cat)\nprintf '{\"ok\":true,\"path\":\"%s\"}' \"$body\"\n".utf8),
                      attributes: [.posixPermissions: 0o755])
        let written: (Int32, String?) = await withCheckedContinuation { done in
            MemoryAgent.run(tools: script, words: ["write-page"], input: "concepts/a.md", environment: [:]) { done.resume(returning: ($0, $1["path"] as? String)) }
        }
        expect(written.0 == 0 && written.1 == "concepts/a.md", "\(written)")
        let failing = dir + "/fail"
        fm.createFile(atPath: failing, contents: Data("#!/bin/sh\necho '{\"error\":\"no engine\"}' >&2\nexit 1\n".utf8),
                      attributes: [.posixPermissions: 0o755])
        let failed: (Int32, String?) = await withCheckedContinuation { done in
            MemoryAgent.run(tools: failing, words: ["status"], environment: [:]) { done.resume(returning: ($0, $1["error"] as? String)) }
        }
        expect(failed.0 == 1 && failed.1 == "no engine", "\(failed)")
    }),
    ("costs keep the digits that matter", {
        expect(MemoryStatusText.usd(0) == "0.00" && MemoryStatusText.usd(0.42) == "0.42" && MemoryStatusText.usd(0.0043) == "0.0043")
    }),
    ("the page drawn (CADEX_SNAPSHOT_DIR: memory-page.png), with a wiki, the agent and a proposal", {
        guard let out = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        write(dir + "/decisions/tenant-files.md", "---\ntitle: One SQLite file per tenant\nkind: decision\nsession_id: 77777777-7777-4777-8777-777777777777\nagent: claude-code\nupdated_at: 2026-11-16T15:10:00Z\n---\nbody")
        // Written today: it is what "LEARNED TODAY" shows (plan 26 C2c).
        let today = ISO8601DateFormatter().string(from: Date())
        write(dir + "/gotchas/batch-timeout.md", "---\ntitle: Batches above 1000 rows hit the API timeout\nkind: gotcha\nupdated_at: \(today)\n---\n")
        write(dir + "/sessions/77777777-7777-4777-8777-777777777777.md", "---\ntitle: LARK-1 tenant storage\nsession_id: 77777777-7777-4777-8777-777777777777\nagent: claude-code\n---\n")
        write(dir + "/_rules/style.md", "---\ntitle: Identifiers in English\nkind: rule\n---\n")
        let overview = MemoryOverview.parse(["running": true, "workspace": "default", "project": "lark", "wiki_dir": dir, "model": "loaded",
                                             "pages": 4, "sessions": 12, "imported": ["state": "done", "sessions": 120,
                                                                                     "accounts": [["dir": "/U/.claude", "sessions": 100], ["dir": "/U/.claude-work", "sessions": 20]]]])
        let agent = MemoryAgentStatus.parse(["enabled": true, "paused": false, "spent_today_usd": 0.0043, "daily_budget_usd": 1.0,
                                             "queue": [["kind": "consolidate", "project": "lark", "state": "running"]],
                                             "recent": [["at": "2026-11-16T15:00:00Z", "kind": "bootstrap", "project": "lark", "cost_usd": 0.0017, "ok": true]],
                                             "proposals_pending": 1, "claude_version": "2.1.325 (Claude Code)"])
        let proposals = MemoryProposal.parseList(["proposals": [["id": "p1", "title": "Always run migrations in a transaction", "path": "_rules/migrations.md",
                                                                 "kind": "rule", "summary": "Seen in 3 sessions", "created_at": "2026-11-16T14:00:00Z",
                                                                 "body": "Run every migration inside a transaction."]]])
        let view = MemoryView(frame: NSRect(x: 0, y: 0, width: 320, height: 760))
        view.accountName = { $0.hasSuffix("work") ? "Work" : "Personal" }
        view.show(MemoryPageState(enabled: true, overview: overview, agent: agent, proposals: proposals, wikiDir: dir, tree: MemoryWiki.tree(dir)))
        let host = NSView(frame: view.frame)
        host.wantsLayer = true
        host.layer?.backgroundColor = DesignTokens.Inspector.bg.cgColor
        host.addSubview(view)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/memory-page.png"))
    }),
] }
