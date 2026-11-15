import AppKit
import Checks
import SessionKit
import Foundation
@testable import Agents

// The unified history (plan 18 phase D; docs/spec/agents.md, Histórico):
// transcripts laid out as Claude Code 2.1.325 writes them (2026-11-14).

func line(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
}

func userLine(_ text: String, session: String, cwd: String, at: String, branch: String = "main") -> String {
    line(["type": "user", "sessionId": session, "cwd": cwd, "gitBranch": branch, "timestamp": at,
          "message": ["role": "user", "content": text]])
}

func appendTo(_ path: String, _ text: String) {
    let handle = FileHandle(forWritingAtPath: path)!
    handle.seekToEndOfFile()
    handle.write(Data(text.utf8))
    try? handle.close()
}

let historyChecks: [(name: String, body: Checks.Body)] = [
    ("the top level is read from the bytes: the type, a tool result, strings and nesting followed", {
        let top = AgentHistoryReader.topLevel(Data(#"{"message":{"type":"x","content":"a \"type\":\"user\" {"},"type":"assistant","n":[1,{"toolUseResult":1}]}"#.utf8))
        expect(top.known && top.type == "assistant" && !top.toolResult, "\(top)")
        let result = AgentHistoryReader.topLevel(Data(#"{"type":"user","toolUseResult":{"stdout":"x"}}"#.utf8))
        expect(result.type == "user" && result.toolResult)
        expect(!AgentHistoryReader.topLevel(Data("[1]".utf8)).known)
    }),
    ("a transcript: its folder, branch, dates, first prompt and titles from the lines; tool results never kept", {
        let dir = NSTemporaryDirectory() + "cadex-history-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: dir) }
        let path = dir + "/s1.jsonl"
        let result = line(["type": "user", "sessionId": "s1", "cwd": "/w", "timestamp": "2026-11-14T10:00:05Z", "toolUseResult": ["stdout": "SECRET"],
                           "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t", "content": "SECRET"]]]])
        let summary = line(["type": "user", "sessionId": "s1", "cwd": "/w/tree", "timestamp": "2026-11-14T09:59:00Z", "isCompactSummary": true,
                            "message": ["role": "user", "content": "This session is being continued from a previous conversation"]])
        write(path, summary + userLine("[Request interrupted by user]", session: "s1", cwd: "/w/tree", at: "2026-11-14T09:59:30Z")
              + userLine("Fix the deploy\nmore detail", session: "s1", cwd: "/w/tree", at: "2026-11-14T10:00:00Z", branch: "feature/x")
              + line(["type": "assistant", "sessionId": "s1", "cwd": "/w/tree", "timestamp": "2026-11-14T10:00:02Z",
                      "message": ["role": "assistant", "content": [["type": "text", "text": "Done with the servers."], ["type": "tool_use", "name": "Bash"]]]])
              + result + line(["type": "ai-title", "aiTitle": "Deploy fix", "sessionId": "s1"]) + "{broken\n")
        var entry = AgentHistoryEntry(id: "s1", path: path, account: "/h/.claude")
        let texts = AgentHistoryReader.readNew(&entry)
        expect(entry.cwd == "/w/tree" && entry.branch == "feature/x" && entry.firstPrompt == "Fix the deploy", "a tool result's line is skipped whole: \(entry)")
        expect(entry.title == "Deploy fix" && entry.unreadable == 1 && entry.origin == nil)
        expect(entry.started == AgentHistoryReader.date("2026-11-14T09:59:00Z") && entry.updated == AgentHistoryReader.date("2026-11-14T10:00:02Z"))
        expect(texts.contains("Done with the servers.") && !texts.contains { $0.contains("SECRET") }, "\(texts)")
        appendTo(path, line(["type": "custom-title", "customTitle": "Mine", "sessionId": "s1"]))
        let before = entry.offset
        expect(AgentHistoryReader.readNew(&entry).isEmpty && entry.title == "Mine" && entry.offset > before, "only the new line is read")
    }),
    ("a huge line is skipped as it passes; one still being written is read again from its start", {
        let dir = NSTemporaryDirectory() + "cadex-history-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: dir) }
        let path = dir + "/s2.jsonl"
        let blob = String(repeating: "x", count: 300_000)
        write(path, userLine("before", session: "s2", cwd: "/a", at: "2026-11-14T10:00:00Z") + "{\"type\":\"user\",\"x\":\"" + blob)
        var entry = AgentHistoryEntry(id: "s2", path: path, account: "/h")
        _ = AgentHistoryReader.readNew(&entry)
        let firstLine = UInt64(userLine("before", session: "s2", cwd: "/a", at: "2026-11-14T10:00:00Z").utf8.count)
        expect(entry.offset == firstLine, "stays on the huge line's start: \(entry.offset)")
        appendTo(path, "\"}\n" + userLine("after", session: "s2", cwd: "/b", at: "2026-11-14T11:00:00Z"))
        let texts = AgentHistoryReader.readNew(&entry)
        expect(texts == ["after"] && entry.cwd == "/b" && entry.unreadable == 0, "\(texts) \(entry.unreadable)")
    }),
    ("the index: every account's transcripts, only what grew, a gone file forgotten, a fork knows its origin", {
        let home = NSTemporaryDirectory() + "cadex-history-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: home) }
        let a = AgentAccount(dir: home + "/.claude", name: "A", isDefault: true)
        let b = AgentAccount(dir: home + "/.claude-b", name: "B", isDefault: false)
        let folder = "/projects/-w"
        write(a.dir + folder + "/orig.jsonl", userLine("codeword banana", session: "orig", cwd: "/w", at: "2026-11-14T09:00:00Z"))
        write(b.dir + folder + "/copy.jsonl", userLine("codeword banana", session: "orig", cwd: "/w", at: "2026-11-14T09:00:00Z")
              + userLine("go on", session: "copy", cwd: "/w", at: "2026-11-14T12:00:00Z"))
        // 2.1.325's form: sessionId rewritten, the origin in session_id.
        write(b.dir + folder + "/new.jsonl", line(["type": "user", "sessionId": "new", "session_id": "orig", "cwd": "/w", "timestamp": "2026-11-14T09:00:00Z",
                                                  "message": ["role": "user", "content": "codeword banana"]])
              + line(["type": "user", "sessionId": "new", "session_id": "new", "cwd": "/w", "timestamp": "2026-11-14T12:00:00Z",
                      "message": ["role": "user", "content": "and now"]]))
        write(b.dir + folder + "/copy/subagents/agent-1.jsonl", userLine("sub", session: "copy", cwd: "/w", at: "2026-11-14T12:00:00Z"))
        let store = AgentHistoryStore(path: ":memory:")
        var entries = store.refresh(accounts: [a, b])
        expect(entries.count == 3, "subagents are not conversations: \(entries.map(\.id))")
        let copy = entries.first { $0.id == "copy" }
        expect(copy?.account == b.dir && copy?.origin == "orig" && copy?.originPath == a.dir + folder + "/orig.jsonl", "\(String(describing: copy))")
        let new = entries.first { $0.id == "new" }
        expect(new?.origin == "orig" && new?.originPath == a.dir + folder + "/orig.jsonl", "2.1.325's form: \(String(describing: new))")
        expect(store.search("banana") == [a.dir + folder + "/orig.jsonl", b.dir + folder + "/copy.jsonl", b.dir + folder + "/new.jsonl"])
        appendTo(a.dir + folder + "/orig.jsonl", userLine("papaya now", session: "orig", cwd: "/w", at: "2026-11-14T13:00:00Z"))
        entries = store.refresh(accounts: [a, b])
        expect(store.search("papaya") == [a.dir + folder + "/orig.jsonl"] && store.search("banana").count == 3, "the old texts stay, once")
        try? fm.removeItem(atPath: b.dir + folder + "/copy.jsonl")
        entries = store.refresh(accounts: [a, b])
        expect(Set(entries.map(\.id)) == ["orig", "new"] && store.search("go").isEmpty)
    }),
    ("the list: this project or all, the words in title, folder or branch or in what was said, groups newest first", {
        func entry(_ id: String, _ cwd: String, _ account: String, _ title: String, _ hours: Double) -> AgentHistoryEntry {
            var e = AgentHistoryEntry(id: id, path: "/p/" + id, account: account)
            e.cwd = cwd
            e.aiTitle = title
            e.branch = "main"
            e.updated = Date(timeIntervalSince1970: 1_800_000_000 - hours * 3600)
            return e
        }
        let all = [entry("1", "/code/app", "/h/.claude", "Deploy fix", 1), entry("2", "/code/web", "/h/.claude-b", "Header", 2),
                   entry("3", "/code/app/sub", "/h/.claude-b", "Tests", 3)]
        let root = { (cwd: String) in cwd.hasPrefix("/code/app") ? "/code/app" : cwd }
        let name = { (dir: String) in dir.hasSuffix("-b") ? "B" : "A" }
        let rows = AgentHistoryRows.make(all, query: "", matches: nil, project: nil, grouping: .project, accountName: name, projectOf: root)
        expect(rows == [.header("app", 2), .entry(all[0]), .entry(all[2]), .header("web", 1), .entry(all[1])], "\(rows)")
        let here = AgentHistoryRows.make(all, query: "", matches: nil, project: "/code/app", grouping: .account, accountName: name, projectOf: root)
        expect(here == [.header("A", 1), .entry(all[0]), .header("B", 1), .entry(all[2])])
        let found = AgentHistoryRows.make(all, query: "deploy", matches: ["/p/2"], project: nil, grouping: .folder, accountName: name, projectOf: root)
        expect(found.compactMap { if case .entry(let e) = $0 { return e.id } else { return nil } } == ["1", "2"], "title or what was said")
        expect(AgentHistoryRows.detail(all[1], accountName: "B", now: Date(timeIntervalSince1970: 1_800_000_000)) == "web · main · B · 2h")
    }),
    ("resume types the owner's command by id; continuing goes by path with --fork-session", {
        let folder = NSTemporaryDirectory() + "cadex-history-kit-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: folder) }
        let kit = SessionKit.forTests(folder: folder)
        var e = AgentHistoryEntry(id: "abc", path: "/h/.claude-b/projects/-w/abc.jsonl", account: "/h/.claude-b")
        e.cwd = "/nowhere/at/all"
        expect(AgentHistoryLaunch.resume(e, kit: kit) == "CLAUDE_CONFIG_DIR=/h/.claude-b claude --resume abc")
        let other = AgentAccount(dir: "/h/.claude-c", name: "C", isDefault: false)
        expect(AgentHistoryLaunch.continueIn(e, account: other, kit: kit)
               == "CLAUDE_CONFIG_DIR=/h/.claude-c claude --resume /h/.claude-b/projects/-w/abc.jsonl --fork-session")
        let home = AgentAccount(dir: NSHomeDirectory() + "/.claude", name: "D", isDefault: true)
        expect(AgentHistoryLaunch.continueIn(e, account: home, kit: kit) == "claude --resume /h/.claude-b/projects/-w/abc.jsonl --fork-session")
        expect(AgentHistoryLaunch.folder(e) == NSHomeDirectory(), "a folder that is gone opens home")
    }),
    ("a continued session lists its own subagents and the origin's, and opens each in its folder", {
        let home = NSTemporaryDirectory() + "cadex-history-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: home) }
        let a = AgentAccount(dir: home + "/.claude", name: "A", isDefault: true)
        let b = AgentAccount(dir: home + "/.claude-b", name: "B", isDefault: false)
        let cwd = home + "/w"
        let folder = AgentProjectFolder.name(for: cwd)
        let originDir = a.dir + "/projects/" + folder + "/orig"
        write(originDir + ".jsonl", userLine("hi", session: "orig", cwd: cwd, at: "2026-11-14T09:00:00Z"))
        write(originDir + "/subagents/agent-old.meta.json", #"{"agentType":"Explore","description":"Found the bug","finished":true}"#)
        write(originDir + "/subagents/agent-old.jsonl", "")
        let copyDir = b.dir + "/projects/" + folder + "/copy"
        write(copyDir + ".jsonl", line(["type": "user", "sessionId": "copy", "session_id": "orig", "cwd": cwd, "timestamp": "2026-11-14T09:00:00Z",
                                        "message": ["role": "user", "content": "hi"]]))
        write(copyDir + "/subagents/agent-new.meta.json", #"{"agentType":"Plan","description":"New one"}"#)
        write(copyDir + "/subagents/agent-new.jsonl", "")
        let session = AgentSession(account: b, pid: 1, id: "copy", name: "copy", cwd: cwd, status: .working, since: Date())
        let origins = AgentSubagent.origins(of: session, accounts: [a, b])
        expect(origins == [originDir + "/subagents"], "\(origins)")
        let agents = AgentSubagent.read(session, origins: origins)
        expect(Set(agents.map(\.description)) == ["Found the bug", "New one"], "\(agents.map(\.description))")
        let old = agents.first { $0.id == "agent-old" }!
        expect(AgentTranscriptDocument.path(of: old, in: session) == originDir + "/subagents/agent-old.jsonl", "the origin's file opens")
        let plain = AgentSession(account: a, pid: 1, id: "orig", name: "o", cwd: cwd, status: .working, since: Date())
        expect(AgentSubagent.origins(of: plain, accounts: [a, b]).isEmpty, "a session that was not continued has none")
    }),
    ("the History page reads only while it shows: hidden in a window, nothing is watched", {
        let history = AgentHistoryController.shared
        let page = AgentHistoryView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        page.isHidden = true
        let window = NSWindow(contentRect: page.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(page)
        expect(!history.isWatching, "hidden: no watch")
        page.isHidden = false
        expect(history.isWatching || history.accounts().isEmpty, "shown: it watches")
        page.isHidden = true
        expect(!history.isWatching, "hidden again: the watch stops")
        page.removeFromSuperview()
    }),
]
