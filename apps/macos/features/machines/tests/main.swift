import AppKit
import Checks
import Foundation
@testable import Machines

// Tests of the machines feature (docs/spec/machines.md). Run with `make
// macos-test` (see shared/checks/Checks.swift for why this is an executable).
// Recorded answers in Fixtures.swift; a fake LocalAPI in FakeDaemon.swift.

nonisolated(unsafe) let fm = FileManager.default

func data(_ text: String) -> Data { Data(text.utf8) }

func tempDir() -> String {
    let dir = NSTemporaryDirectory() + "cadex-machines-\(UUID().uuidString)"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

/// A daemon finder that sees only a Standalone app in `dir` (port 51403).
func standaloneOnly(_ dir: String) -> TailscaleDaemon {
    var daemon = TailscaleDaemon()
    daemon.socketPath = dir + "/none.socket"
    daemon.standaloneDir = dir + "/Tailscale"
    daemon.groupContainers = dir + "/Groups"
    daemon.cliPaths = []
    daemon.appBinary = dir + "/none"
    try? fm.createDirectory(atPath: dir + "/Tailscale", withIntermediateDirectories: true)
    try? fm.createSymbolicLink(atPath: dir + "/Tailscale/ipnport", withDestinationPath: "51403")
    fm.createFile(atPath: dir + "/Tailscale/sameuserproof-51403", contents: data("secret\n"))
    return daemon
}

/// A controller of its own, reading `status` and counting what it did.
@MainActor
final class Fake {
    let controller = MachinesController()
    let dir = tempDir()
    nonisolated(unsafe) var reads = 0
    nonisolated(unsafe) var pinged: [String] = []
    let lock = NSLock()

    init(_ status: String, streams: Bool = true) {
        controller.daemon = standaloneOnly(dir)
        controller.read = { [self] _ in lock.lock(); reads += 1; lock.unlock(); return Tailnet.status(data(status)) }
        controller.pinger = { [self] _, ip in lock.lock(); pinged.append(ip); lock.unlock(); return Tailnet.ping(data(pingDirect)) }
        controller.streamer = { _, handle, _ in
            guard streams else { return false }
            while !handle.isStopped { usleep(20_000) }
            return true
        }
    }
}

let machineTests: [(name: String, body: Checks.Body)] = [
    ("status: this Mac first, the others by name, with path, owner and last seen", {
        let status = Tailnet.status(data(statusRunning))!
        expect(status.isRunning && !status.partial, "\(status.state) \(status.partial)")
        expect(status.machines.map(\.name) == ["my-mac", "box", "old-laptop", "pc"], "\(status.machines.map(\.name))")
        let me = status.machines[0], box = status.machines[1], old = status.machines[2], pc = status.machines[3]
        expect(me.isSelf && me.online && me.ip == "100.64.0.1", "the IPv4 address, not the IPv6 one")
        expect(pc.path == .direct("192.168.0.9:41641") && pc.address == "pc.tail1234.ts.net" && pc.owner == "owner@example.com")
        expect(box.path == .relay("fra") && box.owner == "friend@example.com" && box.lastSeen != nil, "fractional seconds")
        expect(!old.online && old.path == .idle && old.os == "windows")
        expect(me.lastSeen == nil, "Go's zero time is never")
        expect(status.others.count == 3)
    }),
    ("an older Tailscale: what is there is read, and the reading says it is partial", {
        let status = Tailnet.status(data(statusOld))!
        expect(status.partial && status.machines.count == 2)
        expect(status.others[0].name == "pc" && status.others[0].address == "100.64.0.2", "no MagicDNS: the 100.x address")
    }),
    ("broken JSON is nothing; logged out and alone are states, not errors", {
        expect(Tailnet.status(data(statusBroken)) == nil)
        expect(Tailnet.status(data("")) == nil)
        let login = Tailnet.status(data(statusNeedsLogin))!
        expect(!login.isRunning && login.others.isEmpty && MachinesSection.stateText(login.state).contains("log in"))
        let alone = Tailnet.status(data(statusAlone))!
        expect(alone.isRunning && alone.others.isEmpty && MachinesSection.titleText(alone) == "Tailnet")
        expect(MachinesSection.titleText(Tailnet.status(data(statusRunning))!) == "Tailnet 2/3")
    }),
    ("pings: direct, through a relay, failed; and the CLI's pong lines", {
        expect(Tailnet.ping(data(pingDirect)) == MachinePing(ms: 12, path: .direct("192.168.0.9:41641"), error: nil))
        expect(Tailnet.ping(data(pingRelay)) == MachinePing(ms: 80, path: .relay("fra"), error: nil))
        expect(Tailnet.ping(data(pingFailed))?.error == "timeout")
        expect(Tailnet.cliPing("pong from pc (100.64.0.2) via DERP(sao) in 80ms\n") == MachinePing(ms: 80, path: .relay("sao"), error: nil))
        expect(Tailnet.cliPing("pong from pc (100.64.0.2) via 192.168.0.9:41641 in 3ms") == MachinePing(ms: 3, path: .direct("192.168.0.9:41641"), error: nil))
        expect(Tailnet.cliPing("ping \"pc\" timed out") == nil)
    }),
    ("the watch stream: the engine's counters alone do not matter; a state, or the live peers moving, does", {
        var live: Int?
        expect(!Tailnet.busLineMatters(data(busEngine), lastLive: &live), "the first counters only set the mark")
        expect(!Tailnet.busLineMatters(data(busEngine), lastLive: &live))
        expect(Tailnet.busLineMatters(data(busEngineMore), lastLive: &live), "one more live peer")
        expect(Tailnet.busLineMatters(data(busState), lastLive: &live))
        expect(!Tailnet.busLineMatters(data("not json"), lastLive: &live))
    }),
    ("the daemon found in the ADR's order: socket, Standalone, App Store, CLI, the app's binary", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        var daemon = TailscaleDaemon()
        // sun_path holds 104 bytes: the temporary folder's path is longer.
        daemon.socketPath = "/tmp/cxm-\(UUID().uuidString.prefix(8)).sock"
        defer { unlink(daemon.socketPath) }
        daemon.standaloneDir = dir + "/Tailscale"
        daemon.groupContainers = dir + "/Groups"
        daemon.cliPaths = [dir + "/bin/tailscale"]
        daemon.appBinary = dir + "/App/Tailscale"
        expect(daemon.find() == nil, "nothing installed")
        try? fm.createDirectory(atPath: dir + "/App", withIntermediateDirectories: true)
        fm.createFile(atPath: daemon.appBinary, contents: data("#!/bin/sh\n"), attributes: [.posixPermissions: 0o755])
        expect(daemon.find() == .cli(path: daemon.appBinary, beCLI: true))
        try? fm.createDirectory(atPath: dir + "/bin", withIntermediateDirectories: true)
        fm.createFile(atPath: dir + "/bin/tailscale", contents: data("#!/bin/sh\n"), attributes: [.posixPermissions: 0o755])
        expect(daemon.find() == .cli(path: dir + "/bin/tailscale", beCLI: false))
        try? fm.createDirectory(atPath: dir + "/Groups/W5364U7YZB.io.tailscale.ipn.macos", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: dir + "/Groups/group.other.app", withIntermediateDirectories: true)
        fm.createFile(atPath: dir + "/Groups/W5364U7YZB.io.tailscale.ipn.macos/sameuserproof-4321-abcdef", contents: Data())
        expect(daemon.find() == .local(port: 4321, token: "abcdef"), "\(String(describing: daemon.find()))")
        _ = standaloneOnly(dir)
        expect(daemon.find() == .local(port: 51403, token: "secret"), "the Standalone app before the App Store one")
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in for (i, b) in Array(daemon.socketPath.utf8).enumerated() { raw[i] = b } }
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        defer { close(listener) }
        expect(daemon.find() == .socket(daemon.socketPath), "the open tailscaled first")
        try? fm.removeItem(atPath: dir + "/Tailscale/sameuserproof-51403")
        try? fm.removeItem(atPath: daemon.socketPath)
        expect(daemon.find() == .local(port: 4321, token: "abcdef"), "a link without its proof is not the Standalone app")
    }),
    ("the LocalAPI over 127.0.0.1: the proof as the Basic password and the header; a 401 is nothing", {
        let daemon = FakeDaemon(answer: [FakeDaemon.ok(statusRunning)])
        let endpoint = TailscaleEndpoint.local(port: daemon.port, token: "secret")
        let body = await Task.detached { LocalAPI.call(endpoint, "GET", "/localapi/v0/status") }.value
        expect(body.flatMap(Tailnet.status)?.others.count == 3)
        let request = daemon.requests.first ?? ""
        expect(request.hasPrefix("GET /localapi/v0/status HTTP/1.0\r\n"), request)
        expect(request.contains("Authorization: Basic " + Data(":secret".utf8).base64EncodedString()) && request.contains("Sec-Tailscale: localapi"), request)
        let refused = FakeDaemon(answer: ["HTTP/1.0 401 Unauthorized\r\n\r\nno"])
        let none = await Task.detached { LocalAPI.call(.local(port: refused.port, token: "x"), "GET", "/localapi/v0/status") }.value
        expect(none == nil)
        let closed = await Task.detached { LocalAPI.call(.local(port: 1, token: "x"), "GET", "/") }.value
        expect(closed == nil, "nothing listening")
    }),
    ("the watch stream gives each line, split anywhere, until the daemon closes it", {
        let daemon = FakeDaemon(answer: ["HTTP/1.0 200 OK\r\n\r", "\n" + busEngine + "\n" + String(busState.prefix(10)), String(busState.dropFirst(10)) + "\n"])
        let endpoint = TailscaleEndpoint.local(port: daemon.port, token: "t")
        let (ok, lines) = await Task.detached { () -> (Bool, [String]) in
            var lines: [String] = []
            let ok = LocalAPI.watch(endpoint, stop: WatchHandle()) { lines.append(String(decoding: $0, as: UTF8.self)) }
            return (ok, lines)
        }.value
        expect(ok && lines == [busEngine, busState], "\(lines)")
        expect(daemon.requests.first?.hasPrefix("GET /localapi/v0/watch-ipn-bus?mask=0 HTTP/1.0") == true)
    }),
    ("nobody watching, nothing read; the card open reads, pings the online ones and follows; closed, it stops", {
        let fake = Fake(statusRunning)
        defer { try? fm.removeItem(atPath: fake.dir) }
        expect(!fake.controller.isRunning && fake.reads == 0)
        var told = 0
        let id = fake.controller.watch { told += 1 }
        expect(await eventually { fake.controller.status != nil && fake.pinged.count == 2 }, "\(fake.pinged)")
        expect(Set(fake.pinged) == ["100.64.0.2", "100.64.0.3"], "the offline laptop is not pinged")
        expect(fake.controller.isRunning && told > 0)
        expect(await eventually { fake.controller.pings["nPC"] != nil && fake.controller.pings["nPC"]! != nil })
        fake.controller.stop(id)
        expect(!fake.controller.isRunning, "closed: no stream, no timer")
        let reads = fake.reads
        try? await Task.sleep(nanoseconds: 200_000_000)
        expect(fake.reads == reads)
    }),
    ("the stream cannot start: read every 30 s instead, only while open", {
        let fake = Fake(statusRunning, streams: false)
        defer { try? fm.removeItem(atPath: fake.dir) }
        let id = fake.controller.watch {}
        expect(await eventually { fake.controller.status != nil })
        expect(await eventually { fake.controller.isRunning }, "the 30 s reading took over")
        fake.controller.stop(id)
        expect(!fake.controller.isRunning)
    }),
    ("machines.tailscale off: nothing read, nothing kept, the group gone; on again reads", {
        let fake = Fake(statusRunning)
        defer { try? fm.removeItem(atPath: fake.dir) }
        let id = fake.controller.watch {}
        expect(await eventually { fake.controller.status != nil })
        fake.controller.isEnabled = false
        expect(fake.controller.status == nil && !fake.controller.isRunning && fake.controller.pings.isEmpty)
        let reads = fake.reads
        fake.controller.refresh()
        try? await Task.sleep(nanoseconds: 200_000_000)
        expect(fake.reads == reads, "off: refresh reads nothing")
        fake.controller.isEnabled = true
        expect(await eventually { fake.controller.status != nil && fake.controller.isRunning })
        fake.controller.stop(id)
    }),
    ("no daemon: no reading, no stream, and the group is not shown", {
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        let controller = MachinesController()
        var daemon = standaloneOnly(dir)
        daemon.standaloneDir = dir + "/missing"
        controller.daemon = daemon
        let id = controller.watch {}
        expect(controller.status == nil && !controller.isRunning)
        controller.stop(id)
        expect(MachinesSection.make(width: 272, text: .white, secondary: .gray) { _ in } == nil, "nothing read: no group")
    }),
    ("a host is a machine by its short name, MagicDNS name or 100.x address; read once if needed; never when off", {
        let fake = Fake(statusRunning)
        defer { try? fm.removeItem(atPath: fake.dir) }
        var answers: [Bool] = []
        for host in ["ubuntu-dev", "PC", "box.tail1234.ts.net", "100.64.0.4", "my-mac"] { fake.controller.isMachine(host) { answers.append($0) } }
        expect(await eventually { answers.count == 5 })
        expect(answers == [false, true, true, true, false], "\(answers): this Mac is not offered as another machine")
        expect(fake.reads == 1, "read once for all of them")
        fake.controller.isEnabled = false
        var off: Bool?
        fake.controller.isMachine("pc") { off = $0 }
        expect(off == false && fake.reads == 1)
    }),
    ("the answers in the card: direct, relay, offline seen hours ago", {
        let status = Tailnet.status(data(statusRunning))!
        let pc = status.others.first { $0.name == "pc" }!, box = status.others.first { $0.name == "box" }!, old = status.others.first { $0.name == "old-laptop" }!
        expect(MachinesSection.describe(pc, ping: Tailnet.ping(data(pingDirect))) == "direct 12 ms")
        expect(MachinesSection.describe(box, ping: Tailnet.ping(data(pingRelay))) == "relay (fra) 80 ms")
        expect(MachinesSection.describe(box, ping: nil, pinging: true) == "pinging…")
        expect(MachinesSection.describe(old, ping: nil, now: old.lastSeen!.addingTimeInterval(3 * 3600)) == "offline, seen 3h ago")
        expect(MachinesSection.color(pc, ping: nil) == .systemGreen && MachinesSection.color(box, ping: nil) == .systemYellow
               && MachinesSection.color(old, ping: nil) == .systemRed)
    }),
    ("a picture of the Tailnet group, with CADEX_SNAPSHOT_DIR", {
        guard let out = ProcessInfo.processInfo.environment["CADEX_SNAPSHOT_DIR"] else { return }
        let dir = tempDir()
        defer { try? fm.removeItem(atPath: dir) }
        let controller = MachinesController.shared
        controller.daemon = standaloneOnly(dir)
        controller.read = { _ in Tailnet.status(data(statusRunning)) }
        controller.pinger = { _, ip in Tailnet.ping(data(ip == "100.64.0.2" ? pingDirect : pingRelay)) }
        controller.streamer = { _, handle, _ in while !handle.isStopped { usleep(20_000) }; return true }
        let id = controller.watch {}
        expect(await eventually { controller.pings.values.filter { $0 != nil }.count == 2 })
        let section = MachinesSection.make(width: 272, text: .white, secondary: NSColor(white: 0.62, alpha: 1)) { _ in }!
        controller.stop(id)
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        section.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(section)
        NSLayoutConstraint.activate([section.topAnchor.constraint(equalTo: view.topAnchor, constant: 14), section.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
                                     section.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), section.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)])
        view.layoutSubtreeIfNeeded()
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out + "/machines-card.png"))
        }
    }),
    ("the real Tailscale of this Mac, only with CADEX_MACHINES_REAL=1 (never in make check)", {
        guard ProcessInfo.processInfo.environment["CADEX_MACHINES_REAL"] == "1" else { return }
        let endpoint = TailscaleDaemon().find()
        print("    endpoint: \(endpoint.map { if case .local(let port, _) = $0 { return "local \(port)" } else { return "\($0)" } } ?? "none")")
        guard let endpoint else { return expect(false, "no daemon found") }
        let status = await Task.detached { MachinesController.readStatus(endpoint) }.value
        expect(status?.isRunning == true, "\(String(describing: status?.state))")
        print("    \(status?.machines.count ?? 0) machine(s), partial: \(status?.partial ?? true), others: \(status?.others.map(\.name) ?? [])")
        if let me = status?.machines.first {
            let ping = await Task.detached { MachinesController.pingMachine(endpoint, me.ip) }.value
            print("    ping of this Mac: \(String(describing: ping))")
        }
        let handle = WatchHandle()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { handle.stop() }
        let lines = await Task.detached { () -> Int in
            var count = 0
            _ = LocalAPI.watch(endpoint, stop: handle) { _ in count += 1 }
            return count
        }.value
        print("    watch stream: \(lines) line(s) in 3 s")
        expect(lines > 0)
    }),
]
let exitCode = await Checks.run(machineTests + dockerTests + listenerTests + shareTests)

@MainActor func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<60 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return await condition()
}
exit(exitCode)
