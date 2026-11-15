import Checks
import Darwin
import Foundation
@testable import AgentTools

// Tests of the app's socket, with a real socket in a temporary folder. Run
// with `make macos-test` (see shared/checks/Checks.swift for why this is an executable).

/// What `cadex hook` does: one line in, one line back (nil: closed unheard).
func send(_ path: String, _ line: String) -> String? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    defer { close(fd) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
    let ok = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard ok == 0 else { return nil }
    _ = Array((line + "\n").utf8).withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    var timeout = timeval(tv_sec: 2, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var buffer = [UInt8](repeating: 0, count: 4096)
    let n = read(fd, &buffer, buffer.count)
    return n > 0 ? String(decoding: buffer[0..<n], as: UTF8.self) : nil
}

/// Runs `send` off the main thread, so the server's main-thread reply can come.
func sendAsync(_ path: String, _ line: String) async -> String? {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: send(path, line)) }
    }
}

let exitCode = await Checks.run([
    ("a session's token gets its event to the app and the hook's stdout back; no token, no answer", {
        // A short folder: a Unix socket's path has a 104-byte limit.
        let dir = "/tmp/cx-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let tokens = dir + "/tokens"
        try FileManager.default.createDirectory(atPath: tokens, withIntermediateDirectories: true)
        let token = String(repeating: "ab", count: 32)
        FileManager.default.createFile(atPath: tokens + "/s1.token", contents: Data(token.utf8))
        let server = AgentToolsServer(folder: dir + "/sockets", tokens: AgentSessionTokens(folder: tokens))
        try server.start()
        defer { server.stop() }
        var events: [AgentHookEvent] = []
        server.onEvent = { event in
            events.append(event)
            return nil
        }
        // A permission waits for the click: here it comes 0.3 s later.
        var asked: [AgentHookEvent] = []
        server.onPermission = { event, reply, _ in
            asked.append(event)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reply("{\"decision\":\"x\"}") }
        }
        let mode = (try? FileManager.default.attributesOfItem(atPath: dir + "/sockets")[.posixPermissions] as? Int) ?? 0
        expect(mode == 0o700, "the sockets folder is 0700: \(String(mode, radix: 8))")

        let line = #"{"v":1,"token":"\#(token)","event":"SessionStart","pid":77,"payload":{"session_id":"s-1","transcript_path":"/t.jsonl","cwd":"/w","source":"clear"}}"#
        let answer = await sendAsync(server.path, line)
        expect(answer?.contains("\"ok\":true") == true, "\(String(describing: answer))")
        expect(events == [AgentHookEvent(event: "SessionStart", pid: 77, sessionID: "s-1", transcriptPath: "/t.jsonl", cwd: "/w", source: "clear",
                                         notificationType: nil, toolName: nil, toolSubject: nil, kitSession: "s1")], "\(events)")

        let permission = await sendAsync(server.path, #"{"v":1,"token":"\#(token)","event":"PermissionRequest","pid":77,"payload":{"tool_name":"Bash","tool_input":{"command":"rm x","description":"d"}}}"#)
        expect(permission?.contains("decision") == true, "the hook gets the owner's answer: \(String(describing: permission))")
        expect(asked.first?.toolName == "Bash" && asked.first?.toolSubject == "rm x", "\(asked)")
        expect(events.count == 1, "a permission goes to onPermission, not onEvent")

        let refused = await sendAsync(server.path, #"{"v":1,"token":"\#(String(repeating: "cd", count: 32))","event":"Stop","pid":1,"payload":{}}"#)
        expect(refused == nil && events.count == 1, "a wrong token is closed unheard")
        expect(await sendAsync(server.path, #"{"v":1,"event":"Stop"}"#) == nil, "no token, no answer")

        let later = String(repeating: "ef", count: 32)
        FileManager.default.createFile(atPath: tokens + "/s2.token", contents: Data(later.utf8))
        let fresh = await sendAsync(server.path, #"{"v":1,"token":"\#(later)","event":"Stop","pid":2,"payload":{}}"#)
        expect(fresh?.contains("ok") == true, "a session opened after the app started is known at its first word")
    }),
    ("a hook that goes away before the click (answered in the TUI) cancels the request", {
        let dir = "/tmp/cx-\(UUID().uuidString.prefix(8))"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let tokens = dir + "/tokens"
        try FileManager.default.createDirectory(atPath: tokens, withIntermediateDirectories: true)
        let token = String(repeating: "12", count: 32)
        FileManager.default.createFile(atPath: tokens + "/s.token", contents: Data(token.utf8))
        let server = AgentToolsServer(folder: dir + "/sockets", tokens: AgentSessionTokens(folder: tokens))
        try server.start()
        defer { server.stop() }
        var cancelled = false
        var answer: ((String?) -> Void)?
        server.onPermission = { _, reply, cancel in
            answer = reply
            cancel.onCancel = { cancelled = true }
        }
        // The hook connects, asks, and leaves without waiting for the answer.
        let path = server.path
        DispatchQueue.global().async {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
            _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
            let line = #"{"v":1,"token":"\#(token)","event":"PermissionRequest","pid":5,"payload":{"tool_name":"Bash"}}"# + "\n"
            _ = Array(line.utf8).withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            usleep(300_000)
            close(fd)
        }
        for _ in 0..<40 where !cancelled { try await Task.sleep(nanoseconds: 50_000_000) }
        expect(answer != nil && cancelled, "the app hears the hook left")
        answer?("{}")
    }),
])
exit(exitCode)
