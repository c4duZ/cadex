import Foundation

/// A fake LocalAPI on 127.0.0.1: answers each connection with `answer` (a
/// whole HTTP/1.0 response, sent in pieces when `pieces` splits it) and
/// keeps the requests it got. Closes after `connections`.
final class FakeDaemon: @unchecked Sendable {
    let port: Int
    private let fd: Int32
    private let lock = NSLock()
    private var got: [String] = []

    var requests: [String] {
        lock.lock()
        defer { lock.unlock() }
        return got
    }

    init(answer: [String], connections: Int = 1) {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        var on: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(listener, 4)
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &length) } }
        port = Int(UInt16(bigEndian: bound.sin_port))
        fd = listener
        Thread.detachNewThread { [self] in
            for _ in 0..<connections {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                var request = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while request.range(of: Data("\r\n\r\n".utf8)) == nil {
                    let count = read(client, &buffer, buffer.count)
                    if count <= 0 { break }
                    request.append(contentsOf: buffer[0..<count])
                }
                lock.lock()
                got.append(String(decoding: request, as: UTF8.self))
                lock.unlock()
                for piece in answer {
                    let bytes = Array(piece.utf8)
                    _ = bytes.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
                    usleep(20_000)
                }
                close(client)
            }
            close(listener)
        }
    }

    static func ok(_ body: String) -> String {
        "HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n" + body
    }
}
