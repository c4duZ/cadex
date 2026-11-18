import Foundation
import StateGlyph
import Strings

/// What a project's page shows (docs/spec/projects.md, "A página do projeto"; the Project
/// mockup): the app gathers it, the page draws it. Pure, so the words are testable.
public struct ProjectPageState: Equatable {
    public struct Stat: Equatable {
        public var label: String
        public var value: String
        public var note: String
        public init(label: String, value: String, note: String) {
            self.label = label
            self.value = value
            self.note = note
        }
    }

    public struct Conversation: Equatable {
        public var id: String
        public var state: GlyphState
        public var title: String
        /// "orchestration-e · Claude · bkdg".
        public var detail: String
        public var when: String
        public init(id: String, state: GlyphState, title: String, detail: String, when: String) {
            self.id = id
            self.state = state
            self.title = title
            self.detail = detail
            self.when = when
        }
    }

    public struct Automation: Equatable {
        public var id: String
        public var name: String
        /// "every day 03:00 · last ok", "off".
        public var detail: String
        public var on: Bool
        public init(id: String, name: String, detail: String, on: Bool) {
            self.id = id
            self.name = name
            self.detail = detail
            self.on = on
        }
    }

    public struct Account: Equatable {
        /// "Claude bkdg".
        public var name: String
        /// 0…100, nil unknown.
        public var percent: Int?
        public init(name: String, percent: Int?) {
            self.name = name
            self.percent = percent
        }
    }

    public var name: String
    /// "~/Cadu/Trabalho/cadu/cadex · main ↑3 · github.com/c4duZ/cadex".
    public var place: String
    public var stats: [Stat]
    public var conversations: [Conversation]
    public var automations: [Automation]
    public var accounts: [Account]

    public init(name: String, place: String, stats: [Stat] = [], conversations: [Conversation] = [], automations: [Automation] = [],
                accounts: [Account] = []) {
        self.name = name
        self.place = place
        self.stats = stats
        self.conversations = conversations
        self.automations = automations
        self.accounts = accounts
    }
}

public enum ProjectPageWords {
    /// A conversation's dot: live and working, live and asking (needs you), live and quiet or
    /// ended in the last two days (finished), older (gray).
    public static func state(live: Bool, working: Bool, asking: Bool, updated: Date?, now: Date = Date()) -> GlyphState {
        if live { return working ? .working : asking ? .needs : .done }
        guard let updated else { return .idle }
        return now.timeIntervalSince(updated) < 2 * 86400 ? .done : .idle
    }

    /// "now", "4m", "1h", "yesterday", "2d".
    public static func when(_ date: Date?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let minutes = max(0, Int(now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return T("now", "agora") }
        if minutes < 60 { return "\(minutes)m" }
        if calendar.isDateInToday(date) { return "\(minutes / 60)h" }
        if calendar.isDateInYesterday(date) { return T("yesterday", "ontem") }
        return "\(max(1, minutes / 1440))d"
    }

    /// "US$ 6.40".
    public static func usd(_ value: Double) -> String { "US$ " + String(format: "%.2f", value) }

    /// "1 working · 1 needs you", or "none open".
    public static func tasksNote(working: Int, needYou: Int) -> String {
        var parts: [String] = []
        if working > 0 { parts.append(T("\(working) working", "\(working) trabalhando")) }
        if needYou > 0 { parts.append(needYou == 1 ? T("1 needs you", "1 precisa de você") : T("\(needYou) need you", "\(needYou) precisam de você")) }
        return parts.joined(separator: " · ")
    }

    /// The merges' subjects: "Merge pull request #41 from c4duZ/bell-cards" is "bell-cards"; a
    /// plain "Merge branch 'x'" is "x".
    public static func mergedName(_ subject: String) -> String {
        if let from = subject.range(of: " from ") {
            let rest = subject[from.upperBound...]
            return String(rest.split(separator: "/").last ?? rest[...]).trimmingCharacters(in: .whitespaces)
        }
        if let open = subject.firstIndex(of: "'"), let close = subject[subject.index(after: open)...].firstIndex(of: "'") {
            return String(subject[subject.index(after: open)..<close])
        }
        return subject
    }

    /// "github.com/c4duZ/cadex" from an origin (https or ssh).
    public static func remote(_ origin: String) -> String {
        var text = origin.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "ssh://", "git@"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasSuffix(".git") { text.removeLast(4) }
        return text.replacingOccurrences(of: ":", with: "/")
    }
}
