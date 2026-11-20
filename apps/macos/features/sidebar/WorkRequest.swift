import Foundation
import Strings

/// One open request (ADR 0039; plan 38 phase C): the app gathers it from the bell's requests for
/// the top bar's pill.
public struct WorkRequest: Equatable, Sendable {
    public var id: String
    /// Who asks: the task's or the session's name.
    public var who: String
    public var project: String
    /// What it asks, in a sentence ("wants to run npm install stripe").
    public var ask: String
    public var since: Date

    public init(id: String, who: String, project: String, ask: String, since: Date) {
        self.id = id
        self.who = who
        self.project = project
        self.ask = ask
        self.since = since
    }

    /// "now", "4 min", "2 h": how long it has waited.
    public static func waited(_ since: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(since))
        if seconds < 60 { return T("now", "agora") }
        if seconds < 3600 { return "\(seconds / 60) min" }
        return "\(seconds / 3600) h"
    }
}
