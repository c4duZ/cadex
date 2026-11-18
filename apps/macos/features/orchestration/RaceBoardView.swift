import AppKit
import StateGlyph
import Strings
import UILooks

/// What the board's buttons do; each runs a command of the feature by its id
/// or a feature's entry point, given by the app (ADR 0005).
@MainActor
public struct RaceBoardActions {
    public var goToTerminal: (Contender) -> Void = { _ in }
    public var review: (Contender) -> Void = { _ in }
    public var pickWinner: (Contender) -> Void = { _ in }
    public var compare: () -> Void = {}
    public var discard: () -> Void = {}
    public init() {}
}

/// A race whose contenders have no terminal here (on another machine, or closed), in the new
/// frame's face (plan 30 D; docs/spec/orchestration.md, "Corrida"): the name, the prompt's first
/// line, where it started and its cap, Compare and Discard the Others; a card per contender with
/// its state, model · account · machine, cost and diff, and Go to Terminal, Review, Pick Winner.
/// The race with lanes here shows them instead (RaceLaneViews).
@MainActor
enum RaceBoardView {
    static func sections(race: Race, columns cols: [RaceColumn], contenders: [Contender], actions: RaceBoardActions) -> [NSView] {
        let firstLine = race.prompt.split(separator: "\n").first.map(String.init) ?? ""
        let meta = T("From \(race.base) · cap US$ \(String(format: "%.2f", race.caps.budgetUsd)) and \(race.caps.maxMinutes) min each",
                     "De \(race.base) · teto US$ \(String(format: "%.2f", race.caps.budgetUsd)) e \(race.caps.maxMinutes) min cada")
        var buttons = [OrchestrationPage.button(T("Compare…", "Comparar…")) { actions.compare() }]
        if race.winner != nil && !race.discarded {
            buttons.insert(OrchestrationPage.button(T("Discard the Others", "Descartar os outros")) { actions.discard() }, at: 0)
        }
        let byId = Dictionary(contenders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var cards: [NSView] = [OrchestrationPage.section(T("CONTENDERS", "CONCORRENTES"))]
        for column in cols {
            guard let contender = byId[column.contender] else { continue }
            cards.append(card(column, contender: contender, race: race, actions: actions))
        }
        let list = OrchestrationPage.stack(cards, gap: DesignTokens.Board.Column.gap)
        for view in cards.dropFirst() { view.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true }
        return [OrchestrationPage.head(race.name, meta: meta, buttons: buttons),
                boardLabel(firstLine, size: DesignTokens.FontSize.body, color: DesignTokens.Color.textBody), list]
    }

    private static func card(_ column: RaceColumn, contender: Contender, race: Race, actions: RaceBoardActions) -> NSView {
        typealias C = DesignTokens.Board.Card
        let state = column.elapsed.isEmpty ? column.state : column.state + " · " + column.elapsed
        let lines: [(String, NSColor)] = [(column.subtitle, C.Meta.color), (state, C.Text.color),
                                          ([column.cost, column.diff].filter { !$0.isEmpty && $0 != "—" }.joined(separator: " · "), C.Meta.color)]
        var buttons: [NSView] = []
        if !column.isDiscarded {
            buttons.append(OrchestrationPage.button(T("Go to Terminal", "Ir ao terminal")) { actions.goToTerminal(contender) })
            if column.canCompare { buttons.append(OrchestrationPage.button(T("Review", "Revisar")) { actions.review(contender) }) }
            if race.winner == nil {
                buttons.append(OrchestrationPage.button(T("Pick Winner", "Escolher vencedor"), primary: true) { actions.pickWinner(contender) })
            }
        }
        let glyph: GlyphState = column.isWinner ? .done : column.isDiscarded ? .idle : glyph(contender)
        return OrchestrationPage.card(state: glyph, title: column.isWinner ? "★ " + column.title : column.title,
                                      trailing: column.isWinner ? T("Winner", "Vencedor") : "", lines: lines, buttons: buttons)
    }

    private static func glyph(_ contender: Contender) -> GlyphState {
        switch contender.state {
        case .working, .starting: .working
        case .waiting: .needs
        case .finished: .done
        case .failed: .failed
        case .exited, .discarded: .idle
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
