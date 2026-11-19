import Foundation

/// The files shared to the owner's phone by `cadex share` (plan 39 E,
/// docs/plans/39-terminals-from-the-phone.md): each one by a random token in
/// its link, for an hour. An HTML file shares its folder too, for what the
/// page loads (CSS, scripts, images beside it); never anything above it.
public final class FileShareStore: @unchecked Sendable {
    public struct Share: Sendable, Equatable {
        public let token: String
        /// The file, absolute and resolved.
        public let path: String
        public let expires: Date
        public var name: String { (path as NSString).lastPathComponent }
        /// The folder the page may load from (HTML), else just the file.
        public var root: String { (path as NSString).deletingLastPathComponent }
    }

    public static let lifetime: TimeInterval = 60 * 60
    private let lock = NSLock()
    private var shares: [String: Share] = [:]
    var now: @Sendable () -> Date = { Date() }

    public init() {}

    /// Shares `path` (a regular file); the same file again gets a new hour and the same link.
    public func add(_ path: String) -> Share? {
        let resolved = (path as NSString).resolvingSymlinksInPath
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isFolder), !isFolder.boolValue else { return nil }
        lock.lock()
        defer { lock.unlock() }
        sweep()
        let token = shares.values.first { $0.path == resolved }?.token ?? Self.token()
        let share = Share(token: token, path: resolved, expires: now().addingTimeInterval(Self.lifetime))
        shares[token] = share
        return share
    }

    /// The shares still valid, the newest last.
    public func list() -> [Share] {
        lock.lock()
        defer { lock.unlock() }
        sweep()
        return shares.values.sorted { $0.expires < $1.expires }
    }

    public func share(_ token: String) -> Share? {
        lock.lock()
        defer { lock.unlock() }
        sweep()
        return shares[token]
    }

    /// The file a request names inside a share: the shared file itself, or for
    /// an HTML page one under its folder; nil for anything outside it (`..`, a
    /// link out) or missing.
    public func file(_ share: Share, relative: String) -> String? {
        let clean = relative.removingPercentEncoding ?? relative
        if clean.isEmpty || clean == share.name { return share.path }
        guard FileSharePage.kind(of: share.path) == .html, !clean.hasPrefix("/") else { return nil }
        let wanted = ((share.root as NSString).appendingPathComponent(clean) as NSString).standardizingPath
        let resolved = (wanted as NSString).resolvingSymlinksInPath
        guard resolved.hasPrefix(share.root + "/") else { return nil }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isFolder), !isFolder.boolValue else { return nil }
        return resolved
    }

    private func sweep() {
        let at = now()
        shares = shares.filter { $0.value.expires > at }
    }

    private static func token() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
