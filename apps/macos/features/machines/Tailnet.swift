import Foundation

/// How the traffic to a machine goes (docs/spec/machines.md).
public enum MachinePath: Equatable, Sendable {
    /// Straight to it, at this address.
    case direct(String)
    /// Through a Tailscale relay (DERP), in this region ("sao").
    case relay(String)
    /// No connection open now: Tailscale opens one on the first packet.
    case idle
}

/// One machine of the tailnet, as the Tailscale daemon describes it.
public struct Machine: Equatable, Sendable {
    /// The daemon's stable id (or the MagicDNS name when it has none).
    public var id: String
    /// The short name: the first label of the MagicDNS name, else the host name.
    public var name: String
    /// `pc.tail1234.ts.net`, without the final dot; empty without MagicDNS.
    public var dnsName: String
    /// The first 100.x address.
    public var ip: String
    public var os: String
    /// The owner's login, when the daemon says.
    public var owner: String
    /// The owner's id on the tailnet ("" unknown): WhoIs compares it.
    public var ownerID: String = ""
    public var online: Bool
    public var lastSeen: Date?
    public var path: MachinePath
    public var isSelf: Bool

    /// Where ssh and the copy go: the MagicDNS name, else the 100.x address.
    public var address: String { dnsName.isEmpty ? ip : dnsName }
}

/// What one reading of the daemon gave.
public struct TailnetStatus: Equatable, Sendable {
    /// The daemon's BackendState: "Running", "NeedsLogin", "Stopped"...
    public var state: String
    /// This Mac first, then the others by name.
    public var machines: [Machine]
    /// Some field the Cadex reads was missing or of another type: a newer
    /// or older Tailscale (ADR 0030). What could be read is still there.
    public var partial: Bool
    /// The tailnet lets this Mac use Funnel (its node's capability).
    public var funnelAllowed = false

    public var isRunning: Bool { state == "Running" }
    public var others: [Machine] { machines.filter { !$0.isSelf } }
}

/// The answer of a ping to a machine.
public struct MachinePing: Equatable, Sendable {
    public var ms: Int?
    public var path: MachinePath
    public var error: String?
}

/// Reads the LocalAPI's (or `tailscale status --json`'s) answers. Pure, and
/// never throws: the LocalAPI promises no stability (ADR 0030), so a field
/// that is missing is skipped and marks the reading partial; an answer
/// that is not JSON is nil.
public enum Tailnet {
    public static func status(_ data: Data) -> TailnetStatus? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var partial = false
        let state = root["BackendState"] as? String ?? { partial = true; return "" }()
        let users = root["User"] as? [String: Any] ?? [:]
        var machines: [Machine] = []
        if let me = root["Self"] as? [String: Any] {
            machines.append(machine(me, isSelf: true, users: users, partial: &partial))
        } else if state == "Running" {
            partial = true
        }
        if let peers = root["Peer"] as? [String: Any] {
            let others = peers.values.compactMap { $0 as? [String: Any] }.map { machine($0, isSelf: false, users: users, partial: &partial) }
            machines += others.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } else if root["Peer"] != nil, !(root["Peer"] is NSNull) {
            partial = true
        }
        return TailnetStatus(state: state, machines: machines, partial: partial, funnelAllowed: TailscaleServe.funnelAllowed(data))
    }

    static func machine(_ node: [String: Any], isSelf: Bool, users: [String: Any], partial: inout Bool) -> Machine {
        func text(_ key: String) -> String? {
            guard let value = node[key] else { partial = true; return nil }
            return value as? String
        }
        let dnsName = (text("DNSName") ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let hostName = text("HostName") ?? ""
        let ips = node["TailscaleIPs"] as? [String] ?? { partial = true; return [] }()
        let online = node["Online"] as? Bool ?? { partial = true; return false }()
        let owner: String = {
            guard let id = node["UserID"] else { return "" }
            let profile = users[String(describing: id)] as? [String: Any]
            return profile?["LoginName"] as? String ?? profile?["DisplayName"] as? String ?? ""
        }()
        let curAddr = node["CurAddr"] as? String ?? ""
        let relay = node["Relay"] as? String ?? ""
        let active = node["Active"] as? Bool ?? false
        let path: MachinePath = isSelf || !online ? .idle
            : !curAddr.isEmpty ? .direct(curAddr)
            : active && !relay.isEmpty ? .relay(relay) : .idle
        let short = dnsName.split(separator: ".").first.map(String.init) ?? ""
        return Machine(id: node["ID"] as? String ?? dnsName,
                       name: short.isEmpty ? hostName : short,
                       dnsName: dnsName,
                       ip: ips.first { !$0.contains(":") } ?? ips.first ?? "",
                       os: text("OS") ?? "",
                       owner: owner,
                       ownerID: node["UserID"].map { String(describing: $0) } ?? "",
                       online: isSelf || online,
                       lastSeen: date(node["LastSeen"] as? String),
                       path: path,
                       isSelf: isSelf)
    }

    /// Go's zero time ("0001-01-01T00:00:00Z") means never: nil.
    static func date(_ text: String?) -> Date? {
        guard let text, !text.hasPrefix("0001-") else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// The owner's id in a LocalAPI `whois` answer (`UserProfile.ID`).
    public static func whoisOwner(_ data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let profile = root["UserProfile"] as? [String: Any], let id = profile["ID"] else { return nil }
        return String(describing: id)
    }

    /// The LocalAPI's `POST /localapi/v0/ping` answer (tested 2026-11-16,
    /// Tailscale 1.104.7): `LatencySeconds`, `Endpoint` when direct,
    /// `DERPRegionCode` when relayed, `Err` when it failed.
    public static func ping(_ data: Data) -> MachinePing? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let error = root["Err"] as? String, !error.isEmpty { return MachinePing(ms: nil, path: .idle, error: error) }
        let seconds = root["LatencySeconds"] as? Double
        let endpoint = root["Endpoint"] as? String ?? ""
        let region = root["DERPRegionCode"] as? String ?? ""
        let path: MachinePath = !endpoint.isEmpty ? .direct(endpoint) : !region.isEmpty ? .relay(region) : .idle
        return MachinePing(ms: seconds.map { Int(($0 * 1000).rounded()) }, path: path, error: nil)
    }

    /// `tailscale ping -c 1` (the CLI's way, without a LocalAPI):
    /// "pong from pc (100.64.0.2) via DERP(sao) in 80ms" or "… via
    /// 192.168.0.9:41641 in 3ms".
    public static func cliPing(_ output: String) -> MachinePing? {
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("pong from") }) else { return nil }
        let words = line.split(separator: " ")
        guard let via = words.firstIndex(of: "via"), via + 1 < words.count,
              let inIndex = words.lastIndex(of: "in"), inIndex + 1 < words.count else { return nil }
        let route = String(words[via + 1])
        let ms = Int(words[inIndex + 1].replacingOccurrences(of: "ms", with: "")).map { $0 }
            ?? Double(words[inIndex + 1].replacingOccurrences(of: "ms", with: "")).map { Int($0.rounded()) }
        let path: MachinePath = route.hasPrefix("DERP(") ? .relay(String(route.dropFirst(5).dropLast())) : .direct(route)
        return MachinePing(ms: ms, path: path, error: nil)
    }

    /// The watch stream's line (`watch-ipn-bus`, one JSON object a line):
    /// whether it may change the list. Only the engine's counters every
    /// 2 s (measured 2026-11-16) do not, unless the live peers' count moved.
    public static func busLineMatters(_ line: Data, lastLive: inout Int?) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { return false }
        let meaningful = root.filter { key, value in
            key != "Version" && key != "Engine" && !(value is NSNull)
                && !((value as? String)?.isEmpty ?? false) && !((value as? [Any])?.isEmpty ?? false)
        }
        if !meaningful.isEmpty { return true }
        let live = (root["Engine"] as? [String: Any])?["NumLive"] as? Int
        defer { if live != nil { lastLive = live } }
        return live != nil && lastLive != nil && live != lastLive
    }
}
