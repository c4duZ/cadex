import Checks
import Darwin
import Foundation
@testable import Machines

// The port other machines reach Cadex on (plan 23, phase F): bound to the
// address given (here 127.0.0.1, standing for the 100.x one), a connection
// passes only when WhoIs says it is the same owner's device.

func connectTCP(_ ip: String, _ port: UInt16) -> Int32? {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    inet_pton(AF_INET, ip, &address.sin_addr)
    let ok = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    if ok != 0 { close(fd); return nil }
    return fd
}

/// What reading the connection gets within 1 s: the accepted side writes
/// "hi"; a refused one is closed (0 bytes).
func readsHi(_ fd: Int32) -> Bool {
    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var buffer = [UInt8](repeating: 0, count: 8)
    return read(fd, &buffer, buffer.count) == 2
}

final class Answer: @unchecked Sendable { var owner = "1" }

let listenerTests: [(name: String, body: Checks.Body)] = [
    ("only the same owner's device passes WhoIs; another's is closed unheard; stopped, nothing listens", {
        let listener = TailnetListener()
        let answer = Answer()
        listener.whois = { _ in answer.owner }
        listener.onAccepted = { fd in
            _ = Array("hi".utf8).withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            close(fd)
        }
        // A port of its own: copies of the suite run side by side.
        let port = UInt16(40_000 + Int(getpid()) % 20_000)
        expect(listener.start(ip: "127.0.0.1", owner: "1", port: port) && listener.isListening && listener.address == "127.0.0.1")
        let mine = connectTCP("127.0.0.1", port)!
        let passed = await Task.detached { readsHi(mine) }.value
        close(mine)
        expect(passed, "the owner's device")
        answer.owner = "2"
        let theirs = connectTCP("127.0.0.1", port)!
        let refused = await Task.detached { readsHi(theirs) }.value
        close(theirs)
        expect(!refused, "a node shared by another user")
        expect(!listener.start(ip: "", owner: "1") && !listener.isListening, "no address: no listening")
        expect(connectTCP("127.0.0.1", port) == nil)
        expect(!listener.start(ip: "fd7a::1", owner: "1"), "IPv4 only, as Tailscale's 100.x")
    }),
    ("machines.acceptRemote: off nothing listens; on, this Mac's tailnet address and owner; off again it stops", {
        let fake = Fake(statusRunning.replacingOccurrences(of: #""TailscaleIPs":["100.64.0.1","fd7a:115c:a1e0::1"]"#, with: #""TailscaleIPs":["127.0.0.1"]"#))
        defer { try? fm.removeItem(atPath: fake.dir) }
        let listener = TailnetListener()
        listener.whois = { _ in "1" }
        fake.controller.listener = listener
        fake.controller.listenPort = UInt16(40_000 + (Int(getpid()) + 7) % 20_000)
        fake.controller.refresh()
        expect(await eventually { fake.controller.status != nil })
        expect(!listener.isListening, "off by default")
        fake.controller.acceptRemote = true
        expect(listener.isListening && listener.address == "127.0.0.1", "\(listener.address)")
        fake.controller.isEnabled = false
        expect(!listener.isListening, "machines.tailscale off stops it too")
        fake.controller.isEnabled = true
        expect(await eventually { listener.isListening })
        fake.controller.acceptRemote = false
        expect(!listener.isListening)
    }),
    ("whois: the owner's id in UserProfile", {
        expect(Tailnet.whoisOwner(Data(#"{"Node":{"ID":5},"UserProfile":{"ID":4493171228762822,"LoginName":"o@x"},"CapMap":{}}"#.utf8)) == "4493171228762822")
        expect(Tailnet.whoisOwner(Data("{}".utf8)) == nil)
        let me = Tailnet.status(Data(statusRunning.utf8))!.machines[0]
        expect(me.ownerID == "1")
    }),
]
