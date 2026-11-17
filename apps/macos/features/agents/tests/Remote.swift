import Checks
import Foundation
@testable import Agents

// Sessions on another machine (plan 23, "Run on"; ADR 0031): its `claude
// agents --json` read over ssh. The interactive entries' shape is guessed
// from the background ones (only `[]` was seen on a real account).

let remoteChecks: [(name: String, body: Checks.Body)] = [
    ("another machine's sessions: open ones kept with their machine, ended ones left out", {
        let json = #"""
        [{"id":"bg12","sessionId":"s-bg","kind":"background","state":"blocked","cwd":"/home/dev/app.worktrees/fix","name":"fix","startedAt":1763300000000,"waitingFor":"permission prompt"},
         {"sessionId":"s-int","kind":"interactive","state":"working","cwd":"/home/dev/app.worktrees/fix"},
         {"sessionId":"s-old","kind":"background","state":"completed","cwd":"/home/dev/app"},
         {"kind":"interactive","state":"working"}]
        """#
        let sessions = AgentBackground.parseRemote(Data(json.utf8), machine: "pc", destination: "dev@pc.tail1234.ts.net")
        expect(sessions.map(\.id) == ["s-bg", "s-int"], "\(sessions.map(\.id))")
        expect(sessions.allSatisfy { $0.machine == "pc" && $0.account.dir == "ssh://dev@pc.tail1234.ts.net" && $0.pid == 0 })
        expect(sessions[0].status == .waiting && sessions[0].job == "bg12" && sessions[0].waitingFor == "permission prompt")
        expect(sessions[1].status == .working && sessions[1].job == nil && sessions[1].name == "fix")
        expect(AgentBackground.parseRemote(Data("not json".utf8), machine: "pc", destination: "pc").isEmpty)
    }),
    ("the page shown tells the app, which reads the machines only meanwhile; their sessions join the list", {
        let controller = AgentsController.shared
        // A home of its own: the owner's accounts are never read by a test.
        let home = NSTemporaryDirectory() + "cadex-agents-remote-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let before = controller.home
        controller.home = home
        defer { controller.home = before }
        var told: [Bool] = []
        controller.onWatching = { told.append($0) }
        let id = controller.watch {}
        expect(told.isEmpty, "watched (the notifier does it all the time) is not the page shown")
        controller.pageShown(true)
        controller.pageShown(true)
        controller.pageShown(false)
        expect(told == [true], "another window's page still shows")
        let remote = AgentBackground.parseRemote(Data(#"[{"sessionId":"r1","state":"working","cwd":"/home/dev/x"}]"#.utf8), machine: "pc", destination: "pc")
        controller.remote = remote
        expect(controller.sessions.contains { $0.id == "r1" })
        controller.pageShown(false)
        controller.stop(id)
        expect(told == [true, false], "\(told)")
        controller.onWatching = nil
        controller.remote = []
    }),
]
