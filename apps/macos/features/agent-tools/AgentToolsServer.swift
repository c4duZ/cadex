import Darwin
import Foundation
import SessionKit

/// The app's socket (docs/adr/0022-terminal-daemon.md): where the sessions
/// Cadex opened talk to the app, through `cadex hook` now and the CLI and MCP
/// of plan 20 later. `~/Library/Application Support/Cadex/sockets/app.sock`,
/// the folder 0700. A connection counts only from a process of this user
/// (getpeereid) carrying a session's token; anything else is closed with no
/// answer. One line in, one line out: `{"ok":true}` and, for a hook that
/// should print something, its "stdout".
public final class AgentToolsServer: @unchecked Sendable {
    public static let shared = AgentToolsServer()

    /// What the app does with an event; returns what the hook prints (nil:
    /// nothing). Called on the main thread.
    public var onEvent: (@MainActor (AgentHookEvent) -> String?)?
    /// A permission request: the app answers later, on the owner's click,
    /// through `reply` (once; nil answers nothing and the TUI's dialog
    /// decides). `cancelled` runs if the hook goes away first: Claude Code
    /// was answered in the terminal (docs/adr/0023-answer-agent-permissions.md).
    public var onPermission: (@MainActor (AgentHookEvent, _ reply: @escaping @MainActor (String?) -> Void, _ cancelled: AgentToolsCancel) -> Void)?
    public let path: String
    let tokens: AgentSessionTokens
    private let queue = DispatchQueue(label: "cadex.agent-tools.server", qos: .utility)
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?

    init(folder: String = SessionKit.socketsFolder, tokens: AgentSessionTokens = AgentSessionTokens()) {
        path = folder + "/app.sock"
        self.tokens = tokens
    }

    public var isListening: Bool { listener >= 0 }

    /// Binds the socket; a stale one from a crash is replaced.
    public func start() throws {
        guard listener < 0 else { return }
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(folder, 0o700)
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentToolsError.socket(errno) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); throw AgentToolsError.pathTooLong }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); throw AgentToolsError.socket(errno) }
        chmod(path, 0o600)
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        listener = -1
        unlink(path)
    }

    private func accept() {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        // Only this user's processes: another user is closed unheard.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); return }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard let line = Self.readLine(client),
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let token = object["token"] as? String, tokens.isValid(token),
              let event = AgentHookEvent.parse(object) else { close(client); return }
        if event.event == "PermissionRequest" { return waitForOwner(event, client) }
        DispatchQueue.main.async { [weak self] in
            let printed = MainActor.assumeIsolated { self?.onEvent?(event) ?? nil }
            Self.answer(client, printed)
        }
    }

    /// Holds the hook's connection until the owner clicks, or until the
    /// hook goes away (Claude Code was answered in the TUI and stops
    /// listening), whichever comes first; one answer at most.
    private func waitForOwner(_ event: AgentHookEvent, _ client: Int32) {
        let cancel = AgentToolsCancel()
        let state = AgentToolsOnce()
        let watch = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
        watch.setEventHandler {
            // Readable with nothing to read: the other end closed.
            var byte: UInt8 = 0
            if recv(client, &byte, 1, MSG_PEEK) <= 0, state.take() {
                watch.cancel()
                close(client)
                DispatchQueue.main.async { MainActor.assumeIsolated { cancel.fire() } }
            }
        }
        watch.resume()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let handler = self?.onPermission else {
                    if state.take() { watch.cancel(); Self.answer(client, nil) }
                    return
                }
                handler(event, { printed in
                    guard state.take() else { return }
                    watch.cancel()
                    Self.answer(client, printed)
                }, cancel)
            }
        }
    }

    static func answer(_ client: Int32, _ printed: String?) {
        var reply: [String: Any] = ["ok": true]
        if let printed { reply["stdout"] = printed }
        var data = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data("{\"ok\":true}".utf8)
        data.append(0x0A)
        _ = data.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
        close(client)
    }

    /// One line, at most 1 MB, within the read timeout.
    static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while data.count < 1024 * 1024 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
            if let end = data.firstIndex(of: 0x0A) { return data.prefix(upTo: end) }
        }
        return data.isEmpty ? nil : data
    }
}

public enum AgentToolsError: Error {
    case socket(Int32)
    case pathTooLong
}
