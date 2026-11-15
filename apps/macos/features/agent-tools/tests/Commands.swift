import Checks
import Foundation
@testable import AgentTools

// Command requests from the agent (plan 20 phase B; docs/adr/0024-agent-tools.md):
// `cadex run` and its shortcuts on the app's socket.

let commandChecks: [(name: String, body: Checks.Body)] = [
    ("a session's command request reaches the app with its kit session and pids; the answer goes back; no token, no answer", {
        let dir = "/tmp/cx-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/tokens", withIntermediateDirectories: true)
        let token = String(repeating: "cd", count: 32)
        FileManager.default.createFile(atPath: dir + "/tokens/kit-7.token", contents: Data(token.utf8))
        let server = AgentToolsServer(folder: dir + "/sockets", tokens: AgentSessionTokens(folder: dir + "/tokens"))
        try server.start()
        defer { server.stop() }
        var asked: [AgentCommandRequest] = []
        server.onCommand = { request, reply in
            asked.append(request)
            reply(AgentCommandList.allows(request.id ?? "") ? .ok("the owner was notified") : .failed("\(request.id ?? "") is not allowed for agents"))
        }
        let line = #"{"v":1,"token":"\#(token)","run":"agent-tools.notify","args":{"text":"oi"},"pids":[42,7]}"#
        let answer = await sendAsync(server.path, line)
        let reply = answer.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        expect(answer?.hasSuffix("\n") == true && reply?["ok"] as? Bool == true && reply?["result"] as? String == "the owner was notified", "\(String(describing: answer))")
        expect(asked == [AgentCommandRequest(id: "agent-tools.notify", arguments: ["text": "oi"], pids: [42, 7], kitSession: "kit-7")], "\(asked)")
        let refused = await sendAsync(server.path, #"{"v":1,"token":"\#(token)","run":"app.quit","args":{},"pids":[]}"#)
        expect(refused?.contains("not allowed for agents") == true && refused?.contains("\"ok\":false") == true, "\(String(describing: refused))")
        let list = await sendAsync(server.path, #"{"v":1,"token":"\#(token)","list":true,"pids":[]}"#)
        expect(list != nil && asked.last?.id == nil, "the list is a request without an id")
        let stranger = await sendAsync(server.path, #"{"v":1,"token":"\#(String(repeating: "ef", count: 32))","run":"agent-tools.notify","args":{},"pids":[]}"#)
        expect(stranger == nil && asked.count == 3, "no session's token: closed unheard")
    }),
    ("the agent's list opens, notifies, sets the task and drives the preview, and never closes, deletes or changes a setting", {
        for id in ["agent-tools.open-file", "agent-tools.open-diff", "agent-tools.notify", "preview.open", "worktrees.set-status", "worktrees.set-comment"] {
            expect(AgentCommandList.allows(id), id)
        }
        for id in ["app.quit", "window.close", "tab.close", "git.discard", "git.push", "settings.open", "agents.approve", "agent-tools.toggle", "worktrees.remove"] {
            expect(!AgentCommandList.allows(id), id)
        }
    }),
    ("the plugin the kit passes has its manifest and short skills that send the agent to the binary", {
        guard let folder = AgentToolsPlugin.folder else { return expect(false, "no plugin folder") }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: folder + "/.claude-plugin/plugin.json"))) as? [String: Any]
        expect(manifest?["name"] as? String == "cadex")
        for skill in ["cadex", "cadex-task"] {
            let text = try String(contentsOfFile: folder + "/skills/\(skill)/SKILL.md", encoding: .utf8)
            expect(text.hasPrefix("---\nname: \(skill)\n") && text.contains("cadex skills get"), skill)
        }
    }),
]
