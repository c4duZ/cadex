import Foundation

/// One local server Cadex shared on the tailnet (`tailscale serve`) or,
/// with the owner's confirmation, on the internet (`tailscale funnel`).
public struct TailnetShare: Codable, Equatable, Sendable {
    /// The HTTPS port on this Mac's tailnet name (443, 8443, 10000).
    public var httpsPort: Int
    /// The local server's port.
    public var localPort: Int
    public var isPublic: Bool
}

/// Sharing a local server of this Mac (docs/spec/machines.md, "Compartilhar
/// um servidor deste Mac"; ADR 0030): through the owner's CLI, only on a
/// command, and undoing only what Cadex turned on, which it keeps in its
/// own file (`shares.json`), so a relaunch still knows. Never `serve reset`.
public enum TailscaleServe {
    /// The ports Funnel takes (Tailscale's docs); serve uses them too.
    public static let ports = [443, 8443, 10000]

    /// The HTTPS ports already served, from `tailscale serve status --json`
    /// (`{"TCP":{"443":{"HTTPS":true}}, "Web":…}`; `{}` when nothing).
    public static func usedPorts(_ status: Data) -> Set<Int> {
        guard let root = (try? JSONSerialization.jsonObject(with: status)) as? [String: Any],
              let tcp = root["TCP"] as? [String: Any] else { return [] }
        return Set(tcp.keys.compactMap(Int.init))
    }

    /// The first of the ports not served yet; nil when all are.
    public static func freePort(used: Set<Int>) -> Int? { ports.first { !used.contains($0) } }

    /// `serve` (or `funnel`) `--bg --yes --https=<port> http://localhost:<local>`.
    public static func shareArguments(_ share: TailnetShare) -> [String] {
        [share.isPublic ? "funnel" : "serve", "--bg", "--yes", "--https=\(share.httpsPort)", "http://localhost:\(share.localPort)"]
    }

    /// Turns off only that port's handler (`--https=<port> off`).
    public static func stopArguments(_ share: TailnetShare) -> [String] {
        [share.isPublic ? "funnel" : "serve", "--https=\(share.httpsPort)", "off"]
    }

    /// `https://<this-mac>.<tailnet>.ts.net[:port]/`.
    public static func url(dnsName: String, httpsPort: Int) -> String {
        "https://" + dnsName + (httpsPort == 443 ? "" : ":\(httpsPort)") + "/"
    }

    /// Whether the tailnet lets this Mac use Funnel: the node's capability
    /// (`funnel`, or the `…/cap/funnel-ports` one) in the status's Self.
    public static func funnelAllowed(_ status: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: status)) as? [String: Any],
              let me = root["Self"] as? [String: Any] else { return false }
        let caps = Array((me["CapMap"] as? [String: Any] ?? [:]).keys) + (me["Capabilities"] as? [String] ?? [])
        return caps.contains { $0 == "funnel" || $0.contains("/cap/funnel") }
    }

    /// The local port of `http://localhost:<port>/…` (or 127.0.0.1, [::1]);
    /// nil for anything else: only this Mac's servers are shared.
    public static func localPort(of url: URL?) -> Int? {
        guard let url, url.scheme == "http" || url.scheme == "https",
              let host = url.host, ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) else { return nil }
        return url.port ?? (url.scheme == "https" ? 443 : 80)
    }
}

/// What Cadex turned on, in its own file, so "Stop Sharing" undoes that
/// and nothing of the owner's.
public final class TailnetShares: @unchecked Sendable {
    public static let shared = TailnetShares()
    let path: String
    private let lock = NSLock()

    public init(path: String = NSHomeDirectory() + "/Library/Application Support/Cadex/shares.json") {
        self.path = path
    }

    public var all: [TailnetShare] {
        lock.lock()
        defer { lock.unlock() }
        guard let data = FileManager.default.contents(atPath: path) else { return [] }
        return (try? JSONDecoder().decode([TailnetShare].self, from: data)) ?? []
    }

    public func add(_ share: TailnetShare) { write(all.filter { $0.httpsPort != share.httpsPort } + [share]) }
    public func remove(_ share: TailnetShare) { write(all.filter { $0.httpsPort != share.httpsPort }) }

    private func write(_ shares: [TailnetShare]) {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? JSONEncoder().encode(shares).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
