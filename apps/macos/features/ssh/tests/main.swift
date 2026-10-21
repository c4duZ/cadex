import Checks
import Foundation
@testable import SSH

// Tests of the ssh feature. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

nonisolated(unsafe) let fm = FileManager.default

func write(_ path: String, _ text: String) {
    try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    fm.createFile(atPath: path, contents: Data(text.utf8))
}

func fakeHome() -> String {
    let home = NSTemporaryDirectory() + "cadex-ssh-\(UUID().uuidString)"
    write(home + "/.ssh/config", """
    # servers
    Host vps-a vps-b
        HostName 10.0.0.1
        User root
    Host *.internal !skip
        User me
    Host db
        HostName=db.example.com
        Port 2222
    Host inner
        ProxyJump bastion
    Include conf.d/*.conf
    Match host foo
        User x
    Host alias-%h
        HostName %h.example.com
    """)
    write(home + "/.ssh/conf.d/work.conf", "Host work\n  HostName work.example.com\n")
    write(home + "/.ssh/conf.d/loop.conf", "Include ~/.ssh/config\n")
    return home
}

let exitCode = await Checks.run([
    ("hosts with a fixed name, their address and port; patterns and Match are rules", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let hosts = SSHConfig.hosts(at: home + "/.ssh/config", home: home)
        expect(hosts.map(\.alias) == ["vps-a", "vps-b", "db", "inner", "work", "alias-%h"], "\(hosts.map(\.alias))")
        expect(hosts[0].hostName == "10.0.0.1" && hosts[0].port == 22)
        expect(hosts[2].hostName == "db.example.com" && hosts[2].port == 2222, "Key=value works")
        expect(hosts[3].proxy == "bastion", "through a proxy")
        expect(hosts[4].hostName == "work.example.com", "an Include from ~/.ssh, and a loop read once")
        expect(hosts[5].hostName == "alias-%h.example.com", "%h is the alias")
    }),
    ("nobody watching: no test and no file watched; a test reaches each direct host", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let controller = SSHController.shared
        controller.home = home
        var probed: [String] = []
        controller.probe = { host in
            probed.append(host.alias)
            return host.alias == "db" ? .down : .up(20)
        }
        expect(!controller.isRunning)
        let token = controller.watch {}
        let done = await eventually { probed.count == 5 && controller.counts.tested == 5 }
        expect(done, "\(probed) \(controller.reach)")
        expect(!probed.contains("inner") && controller.reach["inner"] == .proxied, "a proxied host is not tested")
        expect(controller.counts.up == 4)
        controller.pings = false
        probed = []
        controller.testNow()
        expect(probed.isEmpty, "ssh.ping off: nothing goes out")
        controller.pings = true
        controller.stop(token)
        expect(!controller.isRunning)
    }),
    ("the config changing is read again", {
        let home = fakeHome()
        defer { try? fm.removeItem(atPath: home) }
        let controller = SSHController.shared
        controller.home = home
        controller.probe = { _ in .up(1) }
        let token = controller.watch {}
        write(home + "/.ssh/config", "Host only\n  HostName 1.2.3.4\n")
        let seen = await eventually { controller.hosts.map(\.alias) == ["only"] }
        expect(seen, "\(controller.hosts.map(\.alias))")
        controller.stop(token)
    }),
    ("a real refused connection is down, fast", {
        let reach = await SSHController.connect(SSHHost(alias: "x", hostName: "127.0.0.1", port: 1, proxy: nil))
        expect(reach == .down, "\(reach)")
    }),
])

@MainActor func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<60 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return condition()
}
exit(exitCode)
