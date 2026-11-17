import Foundation
import Strings

/// What the home screen shows (docs/spec/home.md; the Home mockup), worked out by the app and
/// drawn by HomeView. Pure, so the words and the order are testable.
public struct HomeState: Equatable {
    /// The project the prompt is about; nil with none ("What do you want to do?").
    public var project: String?
    /// "Claude · bkdg": the agent and account the prompt opens; nil without any account.
    public var agent: String?
    /// The prompt runs in a separate copy (a task) instead of the project's folder.
    public var separateCopy = false
    public var recents: [HomeRecent] = []

    public init(project: String?, agent: String?, separateCopy: Bool = false, recents: [HomeRecent] = []) {
        self.project = project
        self.agent = agent
        self.separateCopy = separateCopy
        self.recents = recents
    }
}

/// One row of RECENT PROJECTS.
public struct HomeRecent: Equatable {
    public enum State: Equatable {
        /// Something needs the owner: amber ("2 terminals open · 1 needs you").
        case needsYou(String)
        /// An agent finished: green ("Claude finished").
        case finished(String)
        /// Open, nothing to say: gray ("2 terminals open").
        case open(String)
        /// Not open: gray "nothing open".
        case closed
        /// The folder is gone: gray "Folder not found", with Remove.
        case missing
    }

    public var name: String
    public var folder: String
    public var state: State
    public var usedAt: Date

    public init(name: String, folder: String, state: State, usedAt: Date) {
        self.name = name
        self.folder = folder
        self.state = state
        self.usedAt = usedAt
    }

    public var stateText: String {
        switch self.state {
        case .needsYou(let text), .finished(let text), .open(let text): text
        case .closed: T("nothing open", "nada aberto")
        case .missing: T("Folder not found", "Pasta não encontrada")
        }
    }
}

public enum HomeWords {
    /// "Good morning" from 5 to 12, "Good afternoon" to 18, "Good evening" after.
    public static func greeting(hour: Int) -> String {
        switch hour {
        case 5..<12: T("Good morning", "Bom dia")
        case 12..<18: T("Good afternoon", "Boa tarde")
        default: T("Good evening", "Boa noite")
        }
    }

    /// "now", "4m", "1h", "3d": the mockup's right column.
    public static func when(_ date: Date, now: Date = Date()) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return T("now", "agora") }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h" }
        return "\(minutes / (24 * 60))d"
    }

    /// The open project's state from what its terminals say (the tree knows it): what needs the
    /// owner wins, then a finished agent, then the count of terminals.
    public static func state(terminals: Int, needYou: Int, finished: String?) -> HomeRecent.State {
        let open = terminals == 1 ? T("1 terminal open", "1 terminal aberto") : T("\(terminals) terminals open", "\(terminals) terminais abertos")
        if needYou > 0 { return .needsYou(open + " · " + (needYou == 1 ? T("1 needs you", "1 precisa de você") : T("\(needYou) need you", "\(needYou) precisam de você"))) }
        if let finished { return .finished(T("\(finished) finished", "\(finished) terminou")) }
        return terminals > 0 ? .open(open) : .closed
    }

    /// "~/Cadu/Trabalho/cadex": the home folder as ~.
    public static func shortPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
