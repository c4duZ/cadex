import Darwin
import Foundation
import SessionKit

/// The app's socket (docs/adr/0022-terminal-daemon.md): where the sessions
/// Cadex opened talk to the app, through `cadex hook` now and the CLI and MCP
/// of plan 20 later. `~/Library/Application Support/Cadex/sockets/app.sock`,
/// the folder 0700. A connection counts only from a process of this user
/// (getpeereid) carrying a session's token, or asking for the kit from
/// under one of Cadex's terminals; anything else is closed with no answer. One line in, one line out: `{"ok":true}` and, for a hook that
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
    /// A command the agent asks for (docs/adr/0024-agent-tools.md): the app
    /// checks its list and runs it, answering once through `reply` (a
    /// command may wait on a page). Without it, every request is refused.
    public var onCommand: (@MainActor (AgentCommandRequest, _ reply: @escaping @MainActor (AgentCommandAnswer) -> Void) -> Void)?
    /// The kit for a `claude` typed in a Cadex terminal (AgentKitRequest.swift,
    /// plan 22 phase C): the app checks the asking process is under one of
    /// its terminals' shells and builds the kit. Without it, refused.
    public var onKit: (@MainActor (AgentKitRequest) -> AgentKitAnswer)?
    /// `cadex automations due` (docs/adr/0034-scheduled-automations.md): "check
    /// your agenda". No token: it says nothing of what to run, so any process
    /// of this user (getpeereid) may at most bring a check forward.
    public var onDue: (@MainActor () -> Void)?
    /// `cadex attach` (plan 39 B): the terminals open in Cadex, each with the
    /// daemon's name of its session, the project and the tab. No token, only
    /// this user (getpeereid): the owner over SSH is that user, and the
    /// names say no more than `ps` does.
    public var onTerminals: (@MainActor () -> [[String: Any]])?
    /// The projects' names in the sidebar's order, beside the terminals (plan 39 D: the
    /// menu's n and c ask for one).
    public var onProjects: (@MainActor () -> [String])?
    /// `cadex new <project> [claude]` (plan 39 C): a new tab in the project, by the
    /// registered command, as a click; the answer names its session in the daemon.
    public var onNewTerminal: (@MainActor (_ project: String, _ claude: Bool) -> [String: Any])?
    /// `cadex share <file>` (plan 39 E): its link on the tailnet; with no file, the links
    /// still valid. Only local: any process of this user may share its own files.
    public var onShare: (@MainActor (_ path: String?, _ reply: @escaping @MainActor ([String: Any]) -> Void) -> Void)?
    public let path: String
    let tokens: AgentSessionTokens
    private let queue = DispatchQueue(label: "cadex.agent-tools.server", qos: .utility)
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    /// The socket file this server made (its inode), so it only ever removes its own
    /// (AgentToolsSocketFile.swift).
    var boundInode: ino_t?
    var folderWatch: DispatchSourceFileSystemObject?

    init(folder: String = SessionKit.socketsFolder, tokens: AgentSessionTokens = AgentSessionTokens()) {
        path = folder + "/app.sock"
        self.tokens = tokens
    }

    public var isListening: Bool { listener >= 0 }

    /// Binds the socket; a stale one from a crash is replaced, a live one (another Cadex, a
    /// `make run` beside the installed app) is left alone. Then watches it (`watchSocketFile`).
    public func start() throws {
        try bindSocket()
        watchSocketFile()
    }

    func bindSocket() throws {
        guard listener < 0 else { return }
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        chmod(folder, 0o700)
        if Self.answers(path) { throw AgentToolsError.inUse }
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
        boundInode = Self.inode(path)
        listener = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        folderWatch?.cancel()
        folderWatch = nil
        unbind()
    }

    /// Closes the listener and removes the file only if it is still this server's: a test
    /// instance quitting took the installed Cadex's app.sock with it, and every `cadex` and
    /// browser tool answered "not running" until a reopen (the owner, 2026-11-27).
    func unbind() {
        source?.cancel()
        source = nil
        listener = -1
        if let boundInode, Self.inode(path) == boundInode { unlink(path) }
        boundInode = nil
    }

    private func accept() {
        let client = Darwin.accept(listener, nil, nil)
        guard client >= 0 else { return }
        // Only this user's processes: another user is closed unheard.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); return }
        serve(client, local: true)
    }

    /// A connection from another machine of the owner's tailnet, already
    /// checked by WhoIs (plan 23, TailnetListener): the same protocol, with a
    /// session's token; never the kit request, which trusts the asking
    /// process's ancestry on this Mac.
    public func serveRemote(_ client: Int32) {
        queue.async { [weak self] in
            guard let self else { close(client); return }
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            self.serve(client, local: false)
        }
    }

    private func serve(_ client: Int32, local: Bool) {
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard let line = Self.readLine(client),
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { close(client); return }
        if object["due"] as? Bool == true {
            guard local else { close(client); return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onDue?() }
                Self.answer(client, nil)
            }
            return
        }
        if object["terminals"] as? Bool == true {
            guard local else { close(client); return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    Self.send(client, ["ok": true, "terminals": self?.onTerminals?() ?? [], "projects": self?.onProjects?() ?? []])
                }
            }
            return
        }
        if object["new"] as? Bool == true {
            guard local, let project = object["project"] as? String else { close(client); return }
            let claude = object["claude"] as? Bool == true
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    Self.send(client, self?.onNewTerminal?(project, claude) ?? ["ok": false, "error": "Cadex is closing"])
                }
            }
            return
        }
        if object["share"] != nil || object["shares"] as? Bool == true {
            guard local else { close(client); return }
            let path = object["share"] as? String
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let onShare = self?.onShare else { return Self.send(client, ["ok": false, "error": "Cadex is closing"]) }
                    onShare(path) { Self.send(client, $0) }
                }
            }
            return
        }
        // No token in a tab: a typed `claude` is checked by its ancestry.
        if object["kit"] as? Bool == true {
            guard local else { close(client); return }
            return answerKit(object, client)
        }
        guard let token = object["token"] as? String, let kit = tokens.kitSession(of: token) else { close(client); return }
        if let request = AgentCommandRequest.parse(object, kitSession: kit) { return answerCommand(request, client) }
        guard var event = AgentHookEvent.parse(object) else { close(client); return }
        event.kitSession = kit
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

    private func answerCommand(_ request: AgentCommandRequest, _ client: Int32) {
        let once = AgentToolsOnce()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                let reply: @MainActor (AgentCommandAnswer) -> Void = { answer in
                    guard once.take() else { return }
                    Self.send(client, answer.json)
                }
                guard let handler = self?.onCommand else { return reply(.failed("Agent tools are off in Cadex")) }
                handler(request, reply)
            }
        }
    }

    static func send(_ client: Int32, _ object: [String: Any]) {
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{\"ok\":false}".utf8)
        data.append(0x0A)
        _ = data.withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) }
        close(client)
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
    /// Another Cadex answers on this socket.
    case inUse
}
