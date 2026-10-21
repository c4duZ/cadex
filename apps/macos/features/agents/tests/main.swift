import AppKit
import Checks
import Foundation
import Icons
@testable import Agents

// Tests of the agents feature, on a fake home folder laid out the way
// Claude Code keeps its files (the proof of concept, 2026-10-21). Run with
// `make macos-test` (see shared/checks/Checks.swift for why this is an executable).

nonisolated(unsafe) let fm = FileManager.default

func write(_ path: String, _ text: String) {
    try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    fm.createFile(atPath: path, contents: Data(text.utf8))
}

/// A home with the default account and two others; one live session in a
/// repository, one waiting in a worktree, a dead one and a broken file.
func fakeHome() -> String {
    let home = NSTemporaryDirectory() + "cadex-agents-\(UUID().uuidString)"
    let me = ProcessInfo.processInfo.processIdentifier
    write(home + "/.claude.json", #"{"oauthAccount":{"organizationName":"Team Default"}}"#)
    write(home + "/.claude/sessions/1.json", #"{"pid":\#(me),"sessionId":"s1","cwd":"\#(home)/repo/sub","name":"repo-1","status":"busy","statusUpdatedAt":1792000000000}"#)
    write(home + "/.claude-work/.claude.json", #"{"oauthAccount":{"organizationName":"Liderhub"}}"#)
    write(home + "/.claude-work/sessions/2.json", #"{"pid":\#(me),"sessionId":"s2","cwd":"\#(home)/tree","name":"tree-2","status":"idle","statusUpdatedAt":1792000100000}"#)
    write(home + "/.claude-work/sessions/3.json", #"{"pid":999999,"sessionId":"s3","cwd":"\#(home)/repo","name":"dead","status":"busy"}"#)
    write(home + "/.claude-work/sessions/4.json", "{not json")
    write(home + "/.claude-band/.claude.json", #"{"oauthAccount":{"organizationName":"a@b.c's Organization"}}"#)
    write(home + "/.claude-nologin/sessions/x.json", "{}")
    write(home + "/repo/.git/HEAD", "ref: refs/heads/main\n")
    write(home + "/repo/sub/file.txt", "")
    write(home + "/gitdirs/tree/HEAD", "ref: refs/heads/feature/x\n")
    write(home + "/tree/.git", "gitdir: \(home)/gitdirs/tree\n")
    let sub = home + "/.claude/projects/" + (home + "/repo/sub").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-") + "/s1/subagents"
    write(sub + "/agent-a.meta.json", #"{"agentType":"general-purpose","description":"Mover Kakashi"}"#)
    write(sub + "/agent-a.jsonl", "{}\n")
    write(sub + "/agent-b.meta.json", #"{"agentType":"Explore","description":"Achar o bug"}"#)
    write(sub + "/agent-b.jsonl", "{}\n")
    try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -600)], ofItemAtPath: sub + "/agent-b.jsonl")
    return home
}

let exitCode = await Checks.run([
    ("accounts: ~/.claude and each ~/.claude-* with a login, named by organization or folder", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let accounts = AgentAccount.find(home: home)
        expect(accounts.map(\.name) == ["Team Default", "band", "Liderhub"], "\(accounts.map(\.name))")
        expect(accounts.first?.isDefault == true && accounts.count == 3, "a folder without .claude.json is not an account")
        let twins = AgentAccount.distinct([AgentAccount(dir: "/h/.claude", name: "BKDG", isDefault: true),
                                           AgentAccount(dir: "/h/.claude-bkdg", name: "BKDG", isDefault: false),
                                           AgentAccount(dir: "/h/.claude-x", name: "X", isDefault: false)])
        expect(twins.map(\.name) == ["BKDG · default", "BKDG · bkdg", "X"], "\(twins.map(\.name))")
    }),
    ("sessions: the live ones, in their status; a dead pid and a broken file are left out", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let work = AgentAccount.find(home: home).first { $0.name == "Liderhub" }!
        let read = AgentSession.read(work)
        expect(read.sessions.map(\.name) == ["tree-2"] && read.sessions.first?.status == .waiting, "\(read.sessions)")
        expect(read.unreadable == 1, "the broken file is counted, not fatal")
        expect(AgentSession.parse(["pid": 1, "sessionId": "x", "cwd": "/", "status": "thinking"], account: work)?.status == .other("thinking"))
        expect(AgentSession.parse(["pid": 1, "sessionId": "x", "cwd": "/", "status": "waiting"], account: work)?.status == .waiting)
        expect(AgentSession.parse(["pid": 1, "sessionId": "x", "cwd": "/", "status": "shell"], account: work)?.status == .waiting, "a turn that just ended")
        expect(AgentSession.parse(["sessionId": "x"], account: work) == nil, "no pid, no session")
    }),
    ("projects: the repository above the folder and its branch, a worktree too", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let repo = AgentProject.of(home + "/repo/sub")
        expect(repo.root == home + "/repo" && repo.name == "repo" && repo.branch == "main", "\(repo)")
        let tree = AgentProject.of(home + "/tree")
        expect(tree.branch == "feature/x", "\(tree)")
        expect(AgentProject.of(home + "/nowhere").branch == nil)
    }),
    ("subagents: described, newest first, running only if written in the last 30 s", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let session = AgentSession.read(AgentAccount.find(home: home)[0]).sessions[0]
        let subagents = AgentSubagent.read(session)
        expect(subagents.map(\.description) == ["Mover Kakashi", "Achar o bug"], "\(subagents)")
        expect(subagents.map(\.isRunning) == [true, false])
    }),
    ("the page groups by project, waiting first, and says where each one is", {
        let account = AgentAccount(dir: "/a", name: "BKDG", isDefault: false)
        func session(_ id: String, _ cwd: String, _ status: AgentSession.Status, _ at: Double) -> AgentSession {
            AgentSession(account: account, pid: 1, id: id, name: id, cwd: cwd, status: status, since: Date(timeIntervalSince1970: at))
        }
        let project = { (cwd: String) in AgentProject(root: cwd.hasPrefix("/x") ? "/x" : cwd, name: cwd.hasPrefix("/x") ? "x" : "y", branch: "main") }
        let groups = AgentsLayout.groups([session("a", "/x/1", .working, 30), session("b", "/x/2", .waiting, 10), session("c", "/y", .working, 20)], project: project)
        expect(groups.map(\.project.name) == ["x", "y"] && groups[0].sessions.map(\.id) == ["b", "a"], "\(groups.map { $0.sessions.map(\.id) })")
        let p = AgentProject(root: "/x", name: "x", branch: "main")
        expect(AgentsLayout.detail(session("a", "/x", .working, 0), project: p, inCadex: true) == "main · BKDG")
        expect(AgentsLayout.detail(session("b", "/x", .waiting, 0), project: p, inCadex: false) == "waiting for you · BKDG · outside Cadex")
        expect(AgentTime.short(since: Date(timeIntervalSinceNow: -200)) == "3m" && AgentTime.short(since: Date()) == "now")
    }),
    ("nothing off or unwatched reads: no stream, no timer", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let controller = AgentsController.shared
        controller.home = home
        expect(!controller.isRunning, "nobody watching")
        var changes = 0
        let token = controller.watch { changes += 1 }
        expect(controller.isRunning && controller.sessions.count == 2 && changes >= 1, "\(controller.sessions.map(\.name))")
        expect(controller.counts.working == 1 && controller.counts.waiting == 1)
        controller.toggle("s1")
        expect(controller.subagents.count == 2)
        controller.isEnabled = false
        expect(!controller.isRunning && controller.sessions.isEmpty, "agents.sessions off reads nothing")
        controller.isEnabled = true
        controller.stop(token)
        expect(!controller.isRunning, "the last watcher gone: nothing")
    }),
    ("a new session file shows up by itself", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let controller = AgentsController.shared
        controller.home = home
        let token = controller.watch {}
        let me = ProcessInfo.processInfo.processIdentifier
        write(home + "/.claude-work/sessions/9.json", #"{"pid":\#(me),"sessionId":"s9","cwd":"\#(home)","name":"new-9","status":"busy"}"#)
        let seen = await eventually { controller.sessions.contains { $0.id == "s9" } }
        expect(seen, "FSEvents brought it in")
        controller.stop(token)
    }),
    ("why it stopped, from the end of its log", {
        func line(_ object: [String: Any]) -> String { String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) }
        func assistant(_ content: [[String: Any]], stop: String) -> String { line(["type": "assistant", "message": ["stop_reason": stop, "content": content]]) }
        let bash = assistant([["type": "tool_use", "id": "t1", "name": "Bash"]], stop: "tool_use")
        let result = line(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": "t1"]]]])
        let done = assistant([["type": "text", "text": "pronto"]], stop: "end_turn")
        let meta = line(["type": "system", "subtype": "turn_duration"])
        expect(AgentStop.classify([assistant([["type": "thinking"]], stop: "tool_use"), bash]) == .permission("Bash"))
        expect(AgentStop.classify([assistant([["type": "tool_use", "id": "q", "name": "AskUserQuestion"]], stop: "tool_use")]) == .question)
        expect(AgentStop.classify([assistant([["type": "tool_use", "id": "p", "name": "ExitPlanMode"]], stop: "tool_use")]) == .question, "a plan to approve")
        expect(AgentStop.classify([bash, result, done, meta]) == .finished, "\(AgentStop.classify([bash, result, done, meta]))")
        expect(AgentStop.classify([bash, result]) == .unknown, "answered: working, not waiting")
        expect(AgentStop.classify([done, line(["type": "user", "message": ["content": "e agora?"]])]) == .unknown, "you wrote after it")
        expect(AgentStop.classify(["not json", meta]) == .unknown)
    }),
    ("a notification only when a working agent starts waiting, by kind, and not while you look", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let controller = AgentsController.shared
        controller.home = home
        let notifier = AgentNotifier(controller: controller)
        var stops: [String] = []
        notifier.didStop = { session, _ in stops.append(session.name) }
        notifier.kinds = .init(permission: false, question: true, finished: true)
        let me = ProcessInfo.processInfo.processIdentifier
        let file = home + "/.claude/sessions/1.json"
        let log = AgentStop.log(of: AgentSession.read(AgentAccount.find(home: home)[0]).sessions[0])
        write(log, #"{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"ok"}]}}"#)
        write(file, #"{"pid":\#(me),"sessionId":"s1","cwd":"\#(home)/repo/sub","name":"repo-1","status":"idle","statusUpdatedAt":1792000200000}"#)
        controller.reload()
        notifier.changed()
        expect(stops == ["repo-1"], "working → waiting, finished: \(stops)")
        notifier.changed()
        expect(stops == ["repo-1"], "still waiting: once")
        write(file, #"{"pid":\#(me),"sessionId":"s1","cwd":"\#(home)/repo/sub","name":"repo-1","status":"busy","statusUpdatedAt":1792000300000}"#)
        controller.reload()
        notifier.changed()
        notifier.isLooking = { _ in true }
        write(file, #"{"pid":\#(me),"sessionId":"s1","cwd":"\#(home)/repo/sub","name":"repo-1","status":"idle","statusUpdatedAt":1792000400000}"#)
        controller.reload()
        notifier.changed()
        expect(stops == ["repo-1"], "you were looking: none")
        expect(!notifier.wants(.permission("Bash")) && notifier.wants(.question) && notifier.wants(.finished))
        notifier.kinds = .init(permission: false, question: false, finished: false)
        expect(!controller.isRunning, "all three off: it stops reading")
    }),
    ("an icon per kind, white on the accent", {
        let png = AgentNotifyIcon.draw(.lockKey, accent: .orange)
        expect((png?.count ?? 0) > 500)
        expect(AgentNotifyIcon.icon(for: .permission("Bash")) == .lockKey && AgentNotifyIcon.icon(for: .question) == .question
               && AgentNotifyIcon.icon(for: .finished) == .checkCircle)
        if let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] {
            for (name, icon) in [("permission", Icon.lockKey), ("question", .question), ("finished", .checkCircle)] {
                try? AgentNotifyIcon.draw(icon, accent: NSColor(red: 0.85, green: 0.6, blue: 0.4, alpha: 1))?.write(to: URL(fileURLWithPath: dir + "/notify-\(name).png"))
            }
        }
    }),
    ("a renamed account takes its new name; a hidden one leaves Accounts", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let controller = AgentsController.shared
        controller.home = home
        let token = controller.watch {}
        controller.names = [home + "/.claude-work": "Liderhub"]
        controller.hidden = [home + "/.claude-band"]
        expect(controller.accounts.map(\.name) == ["Team Default", "band", "Liderhub"], "\(controller.accounts.map(\.name))")
        expect(controller.shownAccounts.map(\.name) == ["Team Default", "Liderhub"])
        expect(controller.sessions.first { $0.id == "s2" }?.account.name == "Liderhub", "its sessions carry the new name")
        controller.names = [:]
        controller.hidden = []
        controller.stop(token)
    }),
    ("the login: the Keychain item named after the folder, the plan, an expired one", {
        expect(AgentLogin.service(for: AgentAccount(dir: "/Users/cadu/.claude-diogo", name: "x", isDefault: false)) == "Claude Code-credentials-3bf25f07",
               "the hash the proof of concept found")
        expect(AgentLogin.service(for: AgentAccount(dir: "/Users/cadu/.claude", name: "x", isDefault: true)) == "Claude Code-credentials")
        let login = AgentLogin.parse(Data(#"{"claudeAiOauth":{"accessToken":"t","expiresAt":1000,"subscriptionType":"max"}}"#.utf8))
        expect(login?.token == "t" && login?.plan == "max" && login?.isExpired == true)
        expect(AgentLogin.parse(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil)
    }),
    ("usage: the session, the week and when each resets", {
        let json = #"{"five_hour":{"utilization":38.0,"resets_at":"2026-10-21T17:09:59.708997+00:00"},"seven_day":{"utilization":6.0,"resets_at":"2026-10-28T10:59:59+00:00"},"extra_usage":null}"#
        let usage = AgentUsage.parse(Data(json.utf8))
        expect(usage?.session?.percent == 38 && usage?.week?.percent == 6 && usage?.session?.resets != nil, "\(String(describing: usage))")
        expect(usage?.sonnetWeek == nil)
        expect(AgentUsage.parse(Data("{}".utf8)) == nil)
        expect(AgentMeter.color(95, accent: .blue) == .systemRed && AgentMeter.color(75, accent: .blue) == .systemOrange && AgentMeter.color(10, accent: .blue) == .blue)
    }),
    ("reading usage: 200, 401, 429 and a failure, and an expired login asks nothing", {
        let home = NSTemporaryDirectory() + "cadex-usage-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: home) }
        let future = (Date().timeIntervalSince1970 + 3600) * 1000
        for (name, expires) in [("ok", future), ("gone", 1000.0), ("busy", future), ("down", future)] {
            write(home + "/.claude-\(name)/.claude.json", "{}")
            write(home + "/.claude-\(name)/.credentials.json", #"{"claudeAiOauth":{"accessToken":"\#(name)","expiresAt":\#(expires),"subscriptionType":"team"}}"#)
        }
        let usage = AgentUsageController.shared
        usage.accounts = { AgentAccount.find(home: home) }
        var asked: [String] = []
        var agents: [String] = []
        usage.fetch = { request in
            let token = String((request.value(forHTTPHeaderField: "Authorization") ?? "").dropFirst(7))
            asked.append(token)
            agents.append(request.value(forHTTPHeaderField: "User-Agent") ?? "")
            let url = request.url!
            switch token {
            case "ok": return (Data(#"{"five_hour":{"utilization":2},"seven_day":{"utilization":94}}"#.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            case "busy": return (Data(), HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "120"])!)
            default: throw URLError(.notConnectedToInternet)
            }
        }
        expect(!usage.isRunning, "nobody watching: no timer")
        let token = usage.watch {}
        let done = await eventually { ["ok", "busy", "down"].allSatisfy { name in
            if case .loading = usage.states[home + "/.claude-\(name)"] ?? .loading { return false }
            return true
        } && usage.states[home + "/.claude-gone"] != nil }
        expect(done, "\(usage.states)")
        expect(usage.states[home + "/.claude-ok"]?.usage?.week?.percent == 94)
        expect(usage.states[home + "/.claude-gone"] == .expired && !asked.contains("gone"), "an expired login asks nothing: \(asked)")
        if case .failed = usage.states[home + "/.claude-busy"] {} else { expect(false, "429 is a failure that waits") }
        if case .failed(nil, nil) = usage.states[home + "/.claude-down"] {} else { expect(false, "no connection, nothing to keep") }
        expect(usage.plans[home + "/.claude-ok"] == "team")
        expect(agents.allSatisfy { $0.hasPrefix("Cadex/") }, "Cadex says it is Cadex: \(agents)")
        let before = asked.count
        usage.tick()
        try? await Task.sleep(nanoseconds: 300_000_000)
        expect(asked.count == before, "fresh readings and waits are not repeated: \(asked)")
        usage.stop(token)
        expect(!usage.isRunning)
    }),
    ("a picture of the page, with CADEX_SNAPSHOT_DIR", {
        guard let dir = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        AgentsController.shared.home = home
        let page = AgentsView()
        page.colors = AgentColors(text: .white, secondary: NSColor(white: 0.62, alpha: 1), accent: NSColor(red: 0.88, green: 0.64, blue: 0.35, alpha: 1),
                                  waiting: NSColor(red: 0.42, green: 0.66, blue: 1, alpha: 1), fill: NSColor(white: 0.17, alpha: 1))
        page.isInCadex = { $0.id == "s1" }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 320), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let root = NSView(frame: window.contentLayoutRect)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        page.frame = root.bounds
        page.autoresizingMask = [.width, .height]
        root.addSubview(page)
        window.contentView = root
        if AgentsController.shared.openSession != "s1" { AgentsController.shared.toggle("s1") }
        root.layoutSubtreeIfNeeded()
        if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/agents-page.png"))
        }
        AgentsController.shared.hidden = [home + "/.claude-band"]
        let usage = AgentUsageController.shared
        usage.accounts = { [] }
        usage.states[home + "/.claude"] = .expired
        usage.plans[home + "/.claude-work"] = "team"
        usage.states[home + "/.claude-work"] = .ready(AgentUsage(session: .init(percent: 19, resets: Date().addingTimeInterval(5400)),
                                                                   week: .init(percent: 97, resets: Date().addingTimeInterval(86400 * 3)), sonnetWeek: nil), Date())
        page.subtab = "accounts"
        root.layoutSubtreeIfNeeded()
        if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
            root.cacheDisplay(in: root.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/agents-accounts.png"))
        }
        AgentsController.shared.hidden = []
        page.removeFromSuperview()
    }),
])

@MainActor func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<60 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return condition()
}
exit(exitCode)
