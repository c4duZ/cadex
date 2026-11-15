import Foundation
import SessionKit

/// The tokens of the sessions Cadex opened: the kit writes one file per
/// session (`…/Cadex/sessions/<key>.token`, 0600), so a session keeps
/// talking to the app after the app restarts or the session hibernates. A
/// token not seen yet makes the folder be read again (a session just opened).
final class AgentSessionTokens: @unchecked Sendable {
    let folder: String
    /// Token → the kit session it was made for (the file's name).
    private var known: [String: String] = [:]
    private let lock = NSLock()

    init(folder: String = SessionKit.tokensFolder) {
        self.folder = folder
    }

    func isValid(_ token: String) -> Bool { kitSession(of: token) != nil }

    /// The kit session `token` belongs to, nil when it is no session's.
    func kitSession(of token: String) -> String? {
        guard token.count >= 32 else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let session = known[token] { return session }
        known = Self.read(folder)
        return known[token]
    }

    static func read(_ folder: String) -> [String: String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        var tokens: [String: String] = [:]
        for name in names where name.hasSuffix(".token") {
            guard let token = (try? String(contentsOfFile: folder + "/" + name, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            tokens[token] = String(name.dropLast(6))
        }
        return tokens
    }
}
