import Checks
import Darwin
import Foundation
@testable import AgentTools

// The kit for a `claude` typed in a Cadex terminal (plan 22, phase C): no
// token, the asking process's ancestry read by the app from the kernel.

@MainActor let kitChecks: [(name: String, body: Checks.Body)] = [
    ("the ancestry comes from the kernel: this process, then its parent", {
        let mine = AgentKitRequest.ancestry(of: getpid())
        expect(mine.count >= 2 && mine[0] == getpid() && mine[1] == getppid(), "\(mine)")
        let request = AgentKitRequest(pids: [1234], ancestry: mine, configDir: "", cwd: "/", userSettings: nil, arguments: [])
        expect(request.comesFrom(shells: [getppid()]), "a shell above the asking process")
        expect(!request.comesFrom(shells: [1234, 999_999]), "the pids cadex listed are not trusted")
        expect(!request.comesFrom(shells: []) && !request.comesFrom(shells: [1]))
    }),
    ("a kit request over the socket: under a Cadex shell gets the kit, anything else a refusal", {
        let dir = "/tmp/cx-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let server = AgentToolsServer(folder: dir + "/sockets", tokens: AgentSessionTokens(folder: dir + "/tokens"))
        try server.start()
        defer { server.stop() }
        let line = #"{"v":1,"kit":true,"pids":[1],"config_dir":"/c","cwd":"/w","user_settings":"x.json","args":["-c"]}"#
        expect((await sendAsync(server.path, line))?.contains("\"ok\":false") == true, "no handler: refused")

        var asked: [AgentKitRequest] = []
        var shells: [Int32] = [getppid()]
        server.onKit = { request in
            asked.append(request)
            guard request.comesFrom(shells: shells) else { return .refused("not a Cadex terminal") }
            return .kit(arguments: ["--settings", "/k/s.json"], unset: ["CLAUDECODE"], pathFirst: "/H")
        }
        let answer = await sendAsync(server.path, line) ?? ""
        let object = (try? JSONSerialization.jsonObject(with: Data(answer.utf8))) as? [String: Any] ?? [:]
        expect(object["ok"] as? Bool == true && object["args"] as? [String] == ["--settings", "/k/s.json"]
               && object["unset"] as? [String] == ["CLAUDECODE"] && object["path_first"] as? String == "/H", answer)
        expect(asked.first?.ancestry.first == getpid() && asked.first?.configDir == "/c" && asked.first?.cwd == "/w"
               && asked.first?.userSettings == "x.json" && asked.first?.arguments == ["-c"], "\(asked)")

        shells = [999_999]
        let refused = await sendAsync(server.path, line) ?? ""
        expect(refused.contains("\"ok\":false") && refused.contains("not a Cadex terminal"), refused)
        let plain = await sendAsync(server.path, #"{"v":1,"kit":true,"user_settings":null}"#) ?? ""
        expect(asked.last?.userSettings == nil && asked.last?.arguments == [], plain)
    }),
]
