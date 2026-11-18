import Foundation
import StateGlyph
import Strings

/// The board (docs/spec/orchestration.md, "O quadro"; the Board mockup): every task of the
/// window's projects in four columns by state, each card with what it does or waits for and the
/// race, run or automation it belongs to. The app gathers the cards; this sorts and filters them.
public struct BoardCard: Equatable, Sendable {
    public var id: String
    public var state: GlyphState
    public var name: String
    public var age: String
    public var text: String
    public var project: String
    public var agent: String
    public var added: Int?
    public var removed: Int?
    /// "Race: kite #1", "Run: release-2.4", "Automation: nightly-check"; nil alone.
    public var group: String?
    /// The filter it belongs to: "Race: kite", "Run: release-2.4", "Automations".
    public var filter: String?

    public init(id: String, state: GlyphState, name: String, age: String = "", text: String = "", project: String, agent: String = "",
                added: Int? = nil, removed: Int? = nil, group: String? = nil, filter: String? = nil) {
        self.id = id
        self.state = state
        self.name = name
        self.age = age
        self.text = text
        self.project = project
        self.agent = agent
        self.added = added
        self.removed = removed
        self.group = group
        self.filter = filter
    }
}

public enum BoardColumns {
    public enum Column: CaseIterable, Sendable {
        case needsYou, working, inReview, done

        public var title: String {
            switch self {
            case .needsYou: T("Needs you", "Precisa de você")
            case .working: T("Working", "Trabalhando")
            case .inReview: T("In review", "Em revisão")
            case .done: T("Done", "Pronto")
            }
        }

        /// The glyph of the column's header.
        public var state: GlyphState {
            switch self {
            case .needsYou: .needs
            case .working: .working
            case .inReview: .review
            case .done: .done
            }
        }
    }

    /// The column a card goes in; nil for a task with nothing going on (idle).
    public static func column(of state: GlyphState) -> Column? {
        switch state {
        case .needs, .failed: .needsYou
        case .working: .working
        case .review: .inReview
        case .done: .done
        case .idle: nil
        }
    }

    /// The cards of each column, in their order, with the filter applied (nil: all).
    public static func sort(_ cards: [BoardCard], filter: String?) -> [(Column, [BoardCard])] {
        let shown = filter.map { wanted in cards.filter { $0.filter == wanted } } ?? cards
        return Column.allCases.map { column in (column, shown.filter { Self.column(of: $0.state) == column }) }
    }

    /// The filters' pills after "All": each race and run with how many cards, then Automations.
    public static func filters(_ cards: [BoardCard]) -> [(name: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for card in cards {
            guard let filter = card.filter else { continue }
            if counts[filter] == nil { order.append(filter) }
            counts[filter, default: 0] += 1
        }
        let automations = T("Automations", "Automações")
        return order.sorted { ($0 == automations ? 1 : 0) < ($1 == automations ? 1 : 0) }.map { ($0, counts[$0] ?? 0) }
    }
}
