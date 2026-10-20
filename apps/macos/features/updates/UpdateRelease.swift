import Foundation

/// A published version, as latest.json describes it (made by
/// packaging/sign-update.swift at each release, docs/adr/0016-in-app-updates.md).
public struct UpdateRelease: Decodable, Equatable, Sendable {
    public let version: String
    public let notes: String
    /// The zip of this version, not of "latest": the file signed is the one
    /// downloaded even if a release comes out in between.
    public let url: URL
    public let sha256: String
    /// Ed25519 over the zip's bytes, base64.
    public let signature: String
}

public enum UpdateVersion {
    /// Whether `remote` comes after `current`, number by number: "1.10.0"
    /// after "1.9.2". A "v" in front and a "-beta" after are ignored.
    public static func isNewer(_ remote: String, than current: String) -> Bool {
        let a = numbers(remote), b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func numbers(_ version: String) -> [Int] {
        var text = Substring(version.trimmingCharacters(in: .whitespaces))
        if text.hasPrefix("v") { text = text.dropFirst() }
        let core = text.split(separator: "-", maxSplits: 1).first ?? ""
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}
