import Foundation

/// Answering an agent's question from the bell (docs/adr/0036-owner-words-reach-the-agent.md, plan
/// 26 phase D2). Claude Code reports a question as "Which color? (Red · Blue)" (OSC 7501, kind
/// question) and shows it as a menu: 1. Red, 2. Blue, 3. Type something. Tested on 2026-11-17 with
/// Claude Code 2.1.326 (haiku): the option's number picks it at once, no Enter; the number after
/// the options opens the text field, then the text and Enter send it.
///
/// The options come from the PreToolUse hook of AskUserQuestion, never from the report: the report
/// joins the labels with " · " unescaped ("Red · dark" and "Blue" arrive as "(Red · dark · Blue)")
/// and shows only the first question of a form (tested 2026-11-17). Without the hook, or for a form
/// or a multiple choice (a digit there ticks a box), the card offers no answer: Go to tab.
public enum AgentAnswer {
    /// One question as the hook gave it.
    public struct Asked: Equatable, Sendable {
        public let question: String
        public let options: [String]
        public let multiSelect: Bool
        public init(question: String, options: [String], multiSelect: Bool) {
            self.question = question
            self.options = options
            self.multiSelect = multiSelect
        }
    }

    /// The options to offer for a reported question: the hook's, when the agent asked exactly one
    /// single-choice question and it is the one reported; otherwise none.
    public static func options(reported: String, asked: [Asked]?) -> [String] {
        guard let asked, asked.count == 1, let only = asked.first, !only.multiSelect,
              (2..<maxOptions).contains(only.options.count),
              // The report word for word as this question would make it: an older question with
              // the same text and other options (its hook lost) does not pass (review, 2026-11-17).
              reported == only.question + " (" + only.options.joined(separator: " · ") + ")" else { return [] }
        return only.options
    }

    /// What the owner picked: an option by its position, or words of their own.
    public enum Reply: Equatable, Sendable {
        case option(Int)
        case text(String)
    }

    /// Past nine options a digit would no longer pick one (the menu takes 1 to 9): such a question
    /// is answered in its tab.
    public static let maxOptions = 9
    /// The longest answer typed: a menu's text field, not a document.
    public static let maxText = 2000

    /// The question and the labels as the report joins them; only the question is trusted (the
    /// card's title): a label with " · " in it splits.
    public static func parse(_ text: String) -> (question: String, options: [String]) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")"), let open = trimmed.range(of: " (", options: .backwards) else { return (trimmed, []) }
        let inside = trimmed[open.upperBound..<trimmed.index(before: trimmed.endIndex)]
        let options = inside.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard options.count >= 2 else { return (trimmed, []) }
        return (String(trimmed[..<open.lowerBound]), options)
    }

    /// The keys that answer, each sent after the menu has taken the one before: an option's
    /// number; or the "type something" number, the words on one line, and Enter. Nil when the reply
    /// cannot be sent (an option out of range, no words, a question without its options).
    public static func keys(_ reply: Reply, options: Int) -> [String]? {
        guard options > 0 else { return nil }
        switch reply {
        case .option(let index):
            guard options < maxOptions, (0..<options).contains(index) else { return nil }
            return ["\(index + 1)"]
        case .text(let words):
            // One line, no control characters: a newline would send it early, an escape would
            // reach the terminal as a key.
            let line = words.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
                .trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, options < maxOptions else { return nil }
            return ["\(options + 1)", String(line.prefix(maxText)), "\r"]
        }
    }
}
