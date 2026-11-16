import Foundation

/// Talks to the Tailscale daemon found by `TailscaleDaemon` (ADR 0030):
/// HTTP/1.0 over its Unix socket or 127.0.0.1, so its Go server answers
/// without chunks and the watch stream comes as plain lines (checked with
/// curl --http1.0, 2026-11-16); or, without a LocalAPI, the CLI. Blocking
/// calls with a deadline, made off the main thread by the controller.
enum LocalAPI {
    static let timeout: TimeInterval = 3

    /// The body of a 2xx answer to `GET`/`POST path`; nil on anything else.
    static func call(_ endpoint: TailscaleEndpoint, _ method: String, _ path: String) -> Data? {
        guard let fd = open(endpoint) else { return nil }
        defer { close(fd) }
        guard send(fd, request(endpoint, method, path)) else { return nil }
        var raw = Data()
        var chunk = [UInt8](repeating: 0, count: 16384)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            raw.append(contentsOf: chunk[0..<count])
            if raw.count > 32 << 20 { return nil }  // a status is ~1 KB a machine; this is not one
        }
        return body(raw)
    }

    /// The status line's code and the body, for a whole answer.
    static func body(_ raw: Data) -> Data? {
        guard let split = raw.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: raw[..<split.lowerBound], encoding: .utf8),
              let code = head.split(separator: " ").dropFirst().first.flatMap({ Int($0) }),
              (200..<300).contains(code) else { return nil }
        return Data(raw[split.upperBound...])
    }

    static func request(_ endpoint: TailscaleEndpoint, _ method: String, _ path: String) -> String {
        var lines = ["\(method) \(path) HTTP/1.0", "Host: local-tailscaled.sock", "Sec-Tailscale: localapi", "Content-Length: 0"]
        if case .local(_, let token) = endpoint {
            lines.append("Authorization: Basic " + Data(":\(token)".utf8).base64EncodedString())
        }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    /// The watch stream (`watch-ipn-bus`): `line` gets each JSON line until
    /// the connection ends or `stop` closes it. Returns false when it could
    /// not start (no LocalAPI, refused): the controller reads every 30 s.
    static func watch(_ endpoint: TailscaleEndpoint, stop: WatchHandle, line: (Data) -> Void) -> Bool {
        guard let fd = open(endpoint, readTimeout: 0) else { return false }
        guard stop.attach(fd) else { close(fd); return false }
        defer { stop.detach() }
        guard send(fd, request(endpoint, "GET", "/localapi/v0/watch-ipn-bus?mask=0")) else { return false }
        var pending = Data()
        var started = false
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { return started }
            pending.append(contentsOf: chunk[0..<count])
            if !started {
                guard let split = pending.range(of: Data("\r\n\r\n".utf8)) else { continue }
                guard body(Data(pending[..<split.upperBound])) != nil else { return false }
                pending = Data(pending[split.upperBound...])
                started = true
            }
            while let newline = pending.firstIndex(of: 10) {
                let one = Data(pending[pending.startIndex..<newline])
                pending = Data(pending[(newline + 1)...])
                if !one.isEmpty { line(one) }
            }
        }
    }

    /// `tailscale <args>` for the CLI endpoint: its standard output, or nil
    /// when it failed or took over `timeout`.
    static func cli(_ path: String, beCLI: Bool, _ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if beCLI { process.environment = ProcessInfo.processInfo.environment.merging(["TAILSCALE_BE_CLI": "1"]) { $1 } }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global().asyncAfter(deadline: deadline) { if process.isRunning { process.terminate() } }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }

    private static func open(_ endpoint: TailscaleEndpoint, readTimeout: TimeInterval = timeout) -> Int32? {
        let fd: Int32
        switch endpoint {
        case .socket(let path):
            fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
            guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return nil }
            withUnsafeMutableBytes(of: &address.sun_path) { raw in
                for (i, byte) in bytes.enumerated() { raw[i] = byte }
            }
            let ok = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard ok == 0 else { close(fd); return nil }
        case .local(let port, _):
            fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { return nil }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(UInt16(port).bigEndian)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let ok = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard ok == 0 else { close(fd); return nil }
        case .cli:
            return nil
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var wait = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, socklen_t(MemoryLayout<timeval>.size))
        if readTimeout > 0 {
            var read = timeval(tv_sec: Int(readTimeout), tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &read, socklen_t(MemoryLayout<timeval>.size))
        }
        return fd
    }

    private static func send(_ fd: Int32, _ text: String) -> Bool {
        let bytes = Array(text.utf8)
        return bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == bytes.count
    }
}

/// Lets the main thread end a watch that blocks in `read` on another one:
/// shutting the socket down wakes the read.
final class WatchHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var stopped = false

    func attach(_ socket: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped else { return false }
        fd = socket
        return true
    }

    func detach() {
        lock.lock()
        defer { lock.unlock() }
        if fd >= 0 { close(fd) }
        fd = -1
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
    }

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }
}
