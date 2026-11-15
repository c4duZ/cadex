import Foundation
import SessionKit

/// The tokens of the sessions Cadex opened: the kit writes one file per
/// session (`…/Cadex/sessions/<key>.token`, 0600), so a session keeps
/// talking to the app after the app restarts or the session hibernates. A
/// token not seen yet makes the folder be read again (a session just opened).
final class AgentSessionTokens: @unchecked Sendable {
    let folder: String
    private var known: Set<String> = []
    private let lock = NSLock()

    init(folder: String = SessionKit.tokensFolder) {
        self.folder = folder
    }

    func isValid(_ token: String) -> Bool {
        guard token.count >= 32 else { return false }
        lock.lock()
        defer { lock.unlock() }
        if known.contains(token) { return true }
        known = Self.read(folder)
        return known.contains(token)
    }

    static func read(_ folder: String) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return Set(names.filter { $0.hasSuffix(".token") }.compactMap { name in
            (try? String(contentsOfFile: folder + "/" + name, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        })
    }
}
