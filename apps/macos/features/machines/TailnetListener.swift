import Darwin
import Foundation

/// The port other machines of the tailnet reach Cadex on (docs/spec/machines.md,
/// "Aceitar outras máquinas"; ADR 0031): TCP bound only to this Mac's 100.x
/// address, never to every interface, and only with machines.acceptRemote
/// on (off by default). Each connection is asked to the Tailscale daemon
/// (WhoIs): only a device of the same tailnet user passes, to `onAccepted`,
/// which speaks the app socket's protocol; any other is closed unheard.
/// The base for the cadexd and the phone, which come later.
public final class TailnetListener: @unchecked Sendable {
    public static let shared = TailnetListener()
    /// Cadex's port on the tailnet (plan 23, phase F).
    public static let port: UInt16 = 47_100

    /// A connection that passed WhoIs; the app hands it to the app socket's
    /// server. Called off the main thread; the receiver owns `fd`.
    public var onAccepted: (@Sendable (Int32) -> Void)?
    /// Who owns the peer `ip:port`, by the daemon (tests put a fake).
    var whois: @Sendable (String) -> String? = { address in
        guard let endpoint = TailscaleDaemon().find() else { return nil }
        let query = address.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".:"))) ?? address
        return LocalAPI.call(endpoint, "GET", "/localapi/v0/whois?addr=" + query).flatMap(Tailnet.whoisOwner)
    }

    private let queue = DispatchQueue(label: "cadex.tailnet.listener", qos: .utility)
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var closed: DispatchSemaphore?
    private var owner = ""
    public private(set) var address = ""

    public var isListening: Bool {
        lock.lock()
        defer { lock.unlock() }
        return fd >= 0
    }

    /// Listens on `ip` (this Mac's 100.x address) for devices of `owner`
    /// (this Mac's owner id). Again with the same: nothing; another: moves.
    @discardableResult
    public func start(ip: String, owner: String, port: UInt16 = TailnetListener.port) -> Bool {
        lock.lock()
        let same = fd >= 0 && address == ip && self.owner == owner
        lock.unlock()
        if same { return true }
        stop()
        guard !ip.isEmpty, !owner.isEmpty, !ip.contains(":") else { return false }
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var bound = sockaddr_in()
        bound.sin_family = sa_family_t(AF_INET)
        bound.sin_port = port.bigEndian
        guard inet_pton(AF_INET, ip, &bound.sin_addr) == 1 else { close(socket); return false }
        let ok = withUnsafePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard ok == 0, listen(socket, 8) == 0 else { close(socket); return false }
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        source.setEventHandler { [weak self] in self?.accept(socket) }
        let closed = DispatchSemaphore(value: 0)
        source.setCancelHandler {
            close(socket)
            closed.signal()
        }
        lock.lock()
        fd = socket
        address = ip
        self.owner = owner
        self.source = source
        self.closed = closed
        lock.unlock()
        source.resume()
        return true
    }

    /// Returns once the socket is closed: the port is free again for the
    /// next start (the close used to come a moment later, on the queue, and
    /// a start right after found the address in use; make check, 2026-11-16).
    public func stop() {
        lock.lock()
        let old = source, wait = closed
        source = nil
        closed = nil
        fd = -1
        address = ""
        lock.unlock()
        old?.cancel()
        if old != nil { wait?.wait() }
    }

    private func accept(_ listener: Int32) {
        var peer = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let client = withUnsafeMutablePointer(to: &peer) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.accept(listener, $0, &length) } }
        guard client >= 0 else { return }
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &peer.sin_addr, &text, socklen_t(INET_ADDRSTRLEN))
        let from = String(cString: text) + ":" + String(UInt16(bigEndian: peer.sin_port))
        lock.lock()
        let expected = owner
        lock.unlock()
        // Another user's device (a node shared with the owner) or an answer
        // the daemon does not give: closed with no word.
        guard let who = whois(from), who == expected, let onAccepted else { close(client); return }
        onAccepted(client)
    }
}
