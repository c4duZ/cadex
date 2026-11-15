import Checks
import Foundation
@testable import Agents

// The project folder rule, `finished` and background sessions: the bugs the
// test loop found on 2026-11-14 (Claude Code 2.1.325). Apart from main.swift
// to keep each file under 500 lines.

let folderChecks: [(name: String, body: Checks.Body)] = [
    ("a background session is open only while its job has a live worker; one session per job", {
        let home = NSTemporaryDirectory() + "cadex-bg-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: home) }
        let a = AgentAccount(dir: home + "/.claude-a", name: "A", isDefault: false)
        // The roster as Claude Code 2.1.325 wrote it with one `claude --bg` running (2026-11-14).
        write(a.dir + "/daemon/roster.json", #"{"proto":1,"supervisorPid":27628,"workers":{"2e7947f0":{"pid":27695,"sessionId":"s"},"dead0000":{"pid":4}}}"#)
        expect(AgentBackground.liveJobs(a, alive: { $0 == 27695 }) == ["2e7947f0"], "a worker whose process is gone is not open")
        write(a.dir + "/daemon/roster.json", #"{"proto":1,"supervisorPid":14899,"workers":{}}"#)
        expect(AgentBackground.liveJobs(a, alive: { _ in true }).isEmpty, "no workers: every job is parked")
        expect(AgentBackground.liveJobs(AgentAccount(dir: home + "/none", name: "N", isDefault: false)).isEmpty, "no roster: no daemon")
        let b = AgentAccount(dir: home + "/.claude-b", name: "B", isDefault: false)
        let cwd = home + "/w"
        write(AgentProjectFolder.path(for: cwd, in: b) + "/s1.jsonl", "")
        func job(_ account: AgentAccount) -> AgentSession {
            var s = AgentSession(account: account, pid: 0, id: "s1", name: "x", cwd: cwd, status: .waiting, since: Date())
            s.job = "j1"
            return s
        }
        let one = AgentBackground.distinct([job(a), job(b)])
        expect(one.count == 1 && one[0].account.dir == b.dir, "the account holding its conversation keeps it")
    }),
    ("project folders: every non-alphanumeric is a dash; past 200, the prefix and a hash", {
        expect(AgentProjectFolder.name(for: "/x/a b_c.d-é") == "-x-a-b-c-d--", AgentProjectFolder.name(for: "/x/a b_c.d-é"))
        // The 282-character path of the test loop and the folder Claude Code made for it (2026-11-14).
        let long = "/private/tmp/claude-501/-Users-cadu-Cadu-Trabalho-cadu-cadex/80268cb2-63dd-4b13-82e0-fd9025c08018/scratchpad/test-loop/t17/"
            + (1...7).map { String(format: "pasta-bem-comprida-%02d/", $0) }.joined() + "final"
        let name = AgentProjectFolder.name(for: long)
        expect(name.count == 207 && name.hasPrefix(String(claudeFolder(long).prefix(200))) && name.hasSuffix("-s3x6ke"), name)
        let home = NSTemporaryDirectory() + "cadex-folders-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: home) }
        let account = AgentAccount(dir: home, name: "x", isDefault: false)
        let other = "/" + String(repeating: "q", count: 230)
        let onDisk = String(claudeFolder(other).prefix(200)) + "-zzzzzz"
        try? fm.createDirectory(atPath: home + "/projects/" + onDisk, withIntermediateDirectories: true)
        expect(AgentProjectFolder.path(for: other, in: account) == home + "/projects/" + onDisk, "an unknown hash falls back to the one folder with the prefix")
    }),
    ("subagents in a folder with spaces, '_' and accents, and `finished` when Claude Code writes it", {
        let home = NSTemporaryDirectory() + "cadex-agents-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: home) }
        let account = AgentAccount(dir: home + "/.claude", name: "x", isDefault: true)
        let cwd = home + "/meu projeto_é.v2"
        let session = AgentSession(account: account, pid: 1, id: "s", name: "s", cwd: cwd, status: .working, since: Date())
        let dir = home + "/.claude/projects/" + claudeFolder(cwd) + "/s/subagents"
        write(dir + "/agent-done.meta.json", #"{"description":"Feito","spawnDepth":1,"finished":true}"#)
        write(dir + "/agent-done.jsonl", "{}\n")
        write(dir + "/agent-long.meta.json", #"{"description":"Comando longo","spawnDepth":1}"#)
        write(dir + "/agent-long.jsonl", "{}\n")
        try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)], ofItemAtPath: dir + "/agent-long.jsonl")
        let found = AgentSubagent.read(session)
        expect(found.count == 2, "\(AgentSubagent.folder(of: session))")
        expect(found.first { $0.description == "Feito" }?.isRunning == false, "finished: done, though written just now")
        expect(found.first { $0.description == "Comando longo" }?.isRunning == true, "no finished yet: running, though quiet 60 s")
        expect(AgentStop.log(of: session) == home + "/.claude/projects/" + claudeFolder(cwd) + "/s.jsonl")
    }),
    ("background sessions: open ones from `claude agents --json`, and how a tab opens them", {
        let account = AgentAccount(dir: "/h/.claude-x", name: "X", isDefault: false)
        let json = #"""
        [{"pid":1,"cwd":"/r","kind":"interactive","sessionId":"i","name":"term","status":"idle"},
         {"id":"2e0affcb","cwd":"/r","kind":"background","startedAt":1794691740317,"sessionId":"b1","name":"criar arquivo",
          "status":"waiting","waitingFor":"permission prompt","state":"blocked"},
         {"id":"aa85002c","cwd":"/r","kind":"background","sessionId":"b2","name":"rodando","state":"working"},
         {"id":"07cc5810","cwd":"/r","kind":"background","sessionId":"b3","name":"pronta","state":"done"}]
        """#
        let found = AgentBackground.parse(Data(json.utf8), account: account)
        expect(found.map(\.id) == ["b1", "b2"], "\(found.map(\.id))")
        expect(found[0].status == .waiting && found[0].job == "2e0affcb" && found[0].waitingFor == "permission prompt" && found[0].pid == 0)
        expect(found[1].status == .working)
        expect(AgentBackground.parse(Data("not json".utf8), account: account).isEmpty)
        expect(AgentsLayout.detail(found[0], project: AgentProject(root: "/r", name: "r", branch: "main"), inCadex: false)
               == "waiting for you · X · in the background")
        expect(AgentLaunch.attachCommand(job: "2e0affcb", account: account) == "CLAUDE_CONFIG_DIR='/h/.claude-x' claude attach 2e0affcb")
        expect(AgentLaunch.attachCommand(job: "ab; rm -rf ~", account: AgentAccount(dir: "/h/.claude", name: "d", isDefault: true))
               == "claude attach abrm-rf", "only letters, digits and dashes reach the shell")
    }),
]
