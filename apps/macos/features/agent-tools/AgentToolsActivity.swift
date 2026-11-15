import Foundation

/// The sessions that used the Cadex through `cadex` or `cadex mcp` and the
/// last thing each asked (agent-tools.show-sessions), kept while the app
/// runs. Nothing goes to disk.
@MainActor
public final class AgentToolsActivity {
    public static let shared = AgentToolsActivity()

    public struct Entry: Equatable, Sendable {
        public let kitSession: String
        public var session: String
        public var command: String
        public var ok: Bool
        public var at: Date
    }

    public private(set) var entries: [Entry] = []

    init() {}

    public func record(kitSession: String, session: String, command: String, ok: Bool, at: Date = Date()) {
        let entry = Entry(kitSession: kitSession, session: session, command: command, ok: ok, at: at)
        entries.removeAll { $0.kitSession == kitSession }
        entries.insert(entry, at: 0)
        if entries.count > 50 { entries.removeLast() }
    }
}
