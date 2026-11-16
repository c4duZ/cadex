import Checks
import Darwin
import Foundation
@testable import AgentTools

// A connection from another machine of the tailnet (plan 23, phase F),
// handed over after WhoIs: the same protocol with a session's token, and
// never the kit, which trusts the asking process's ancestry on this Mac.

/// One line through one end of a socket pair served as a remote client.
func sendRemote(_ server: AgentToolsServer, _ line: String) async -> String? {
    var pair: [Int32] = [0, 0]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0 else { return nil }
    server.serveRemote(pair[1])
    let ours = pair[0]
    return await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            defer { close(ours) }
            _ = Array((line + "\n").utf8).withUnsafeBytes { write(ours, $0.baseAddress, $0.count) }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(ours, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(ours, &buffer, buffer.count)
            continuation.resume(returning: n > 0 ? String(decoding: buffer[0..<n], as: UTF8.self) : nil)
        }
    }
}

let remoteChecks: [(name: String, body: Checks.Body)] = [
    ("from another machine: a session's token is answered; the kit and no token are closed unheard", {
        let dir = "/tmp/cx-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let tokens = dir + "/tokens"
        try FileManager.default.createDirectory(atPath: tokens, withIntermediateDirectories: true)
        let token = String(repeating: "cd", count: 32)
        FileManager.default.createFile(atPath: tokens + "/r1.token", contents: Data(token.utf8))
        let server = AgentToolsServer(folder: dir + "/sockets", tokens: AgentSessionTokens(folder: tokens))
        var events: [String] = []
        var kits = 0
        server.onEvent = { events.append($0.event); return nil }
        server.onKit = { _ in kits += 1; return .refused("no") }
        let answer = await sendRemote(server, #"{"v":1,"token":"\#(token)","event":"Stop","pid":5,"payload":{"session_id":"x"}}"#)
        expect(answer?.contains("\"ok\":true") == true && events == ["Stop"], "\(String(describing: answer)) \(events)")
        expect(await sendRemote(server, #"{"kit":true,"pids":[1]}"#) == nil && kits == 0, "the kit is never asked from afar")
        expect(await sendRemote(server, #"{"v":1,"event":"Stop","pid":5}"#) == nil && events.count == 1)
    }),
]
