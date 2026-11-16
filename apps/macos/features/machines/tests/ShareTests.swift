import Checks
import Foundation
@testable import Machines

// Sharing a preview on the tailnet (plan 23, phase G), with a fake CLI:
// the real `tailscale serve` is never run by the tests (it would change the
// owner's Tailscale).

final class CLICalls: @unchecked Sendable {
    var calls: [[String]] = []
    var served = "{}"
    var fails = false
}

let shareTests: [(name: String, body: Checks.Body)] = [
    ("the pure part: ports in use, the free one, the arguments, the address, a local page's port", {
        let status = Data(#"{"TCP":{"443":{"HTTPS":true}},"Web":{"me.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8080"}}}}}"#.utf8)
        expect(TailscaleServe.usedPorts(status) == [443] && TailscaleServe.usedPorts(Data("{}".utf8)).isEmpty)
        expect(TailscaleServe.freePort(used: [443]) == 8443 && TailscaleServe.freePort(used: [443, 8443, 10000]) == nil)
        let share = TailnetShare(httpsPort: 8443, localPort: 5173, isPublic: false)
        expect(TailscaleServe.shareArguments(share) == ["serve", "--bg", "--yes", "--https=8443", "http://localhost:5173"])
        expect(TailscaleServe.stopArguments(TailnetShare(httpsPort: 443, localPort: 1, isPublic: true)) == ["funnel", "--https=443", "off"])
        expect(TailscaleServe.url(dnsName: "my-mac.tail1234.ts.net", httpsPort: 443) == "https://my-mac.tail1234.ts.net/")
        expect(TailscaleServe.url(dnsName: "my-mac.tail1234.ts.net", httpsPort: 8443) == "https://my-mac.tail1234.ts.net:8443/")
        expect(TailscaleServe.localPort(of: URL(string: "http://localhost:5173/app")) == 5173)
        expect(TailscaleServe.localPort(of: URL(string: "http://127.0.0.1/")) == 80)
        expect(TailscaleServe.localPort(of: URL(string: "https://example.com:8443/")) == nil, "only this Mac's servers")
        expect(!TailscaleServe.funnelAllowed(Data(statusRunning.utf8)))
        expect(TailscaleServe.funnelAllowed(Data(#"{"Self":{"CapMap":{"https://tailscale.com/cap/funnel-ports?ports=443,8443,10000":null}}}"#.utf8)))
    }),
    ("share: the first port the owner does not serve, kept as Cadex's; stop undoes only it; Funnel refused without the capability", {
        let fake = Fake(statusRunning)
        defer { try? fm.removeItem(atPath: fake.dir) }
        let bin = fake.dir + "/bin"
        try? fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
        fm.createFile(atPath: bin + "/tailscale", contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        fake.controller.daemon.cliPaths = [bin + "/tailscale"]
        let calls = CLICalls()
        calls.served = #"{"TCP":{"443":{"HTTPS":true}}}"#
        fake.controller.shareRunner = { _, args in
            calls.calls.append(args)
            if args.starts(with: ["serve", "status"]) { return Data(calls.served.utf8) }
            return calls.fails ? nil : Data()
        }
        fake.controller.shares = TailnetShares(path: fake.dir + "/shares.json")
        let result = await fake.controller.share(localPort: 5173, isPublic: false)
        expect(result == .success("https://my-mac.tail1234.ts.net:8443/"), "\(result): 443 is the owner's")
        expect(calls.calls.last == ["serve", "--bg", "--yes", "--https=8443", "http://localhost:5173"])
        expect(fake.controller.shares.all == [TailnetShare(httpsPort: 8443, localPort: 5173, isPublic: false)])
        expect(await fake.controller.stopSharing(fake.controller.shares.all[0]) == nil)
        expect(calls.calls.last == ["serve", "--https=8443", "off"] && fake.controller.shares.all.isEmpty, "never serve reset")
        let before = calls.calls.count
        let funnel = await fake.controller.share(localPort: 5173, isPublic: true)
        expect(funnel == .failure(.message("Your tailnet does not let this Mac use Funnel.")) && calls.calls.count == before, "nothing run")
        calls.fails = true
        let failed = await fake.controller.share(localPort: 3000, isPublic: false)
        expect(fake.controller.shares.all.isEmpty, "\(failed): a share that did not start is not kept")
        calls.served = #"{"TCP":{"443":{},"8443":{},"10000":{}}}"#
        calls.fails = false
        expect(await fake.controller.share(localPort: 3000, isPublic: false) == .failure(.message("Ports 443, 8443 and 10000 are all served already.")))
    }),
]
