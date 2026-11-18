import AppKit
import StateGlyph
import UILooks
import Strings
import Tabs

/// One line of an automation's history (orchestration.show-automation-history,
/// plan 24 E): when it was due, started and ended, its cost and result, and
/// whether its session and transcript can be opened.
public struct AutomationLine: Equatable, Sendable {
    public let run: String
    public let text: String
    public let result: String
    public let hasSession: Bool
    public let hasTranscript: Bool
}

public enum AutomationLines {
    public static func make(_ runs: [AutomationRun]) -> [AutomationLine] {
        let time = { (date: Date?) in date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—" }
        return runs.sorted { $0.scheduledAt > $1.scheduledAt }.map { run in
            var parts = [T("due ", "prevista ") + time(run.scheduledAt)]
            if let start = run.startedAt { parts.append(T("started ", "começou ") + time(start)) }
            if let end = run.endedAt { parts.append(T("ended ", "terminou ") + time(end)) }
            parts.append(RaceColumns.costLabel(run.costUsd, remote: false))
            return AutomationLine(run: run.id, text: parts.joined(separator: " · "), result: label(run.result) + (run.reason.map { ": " + $0 } ?? ""),
                                  hasSession: run.session != nil, hasTranscript: run.session?.transcript != nil)
        }
    }

    public static func label(_ result: AutomationResult) -> String {
        switch result {
        case .running: return T("Running", "Rodando")
        case .done: return T("Done", "Concluída")
        case .failed: return T("Failed", "Falhou")
        case .hitTheCap: return T("Hit the cap", "Bateu no teto")
        case .stoppedWaiting: return T("Stopped waiting", "Parou esperando")
        case .skipped: return T("Skipped", "Pulada")
        }
    }
}

/// What the history's buttons do, given by the app (ADR 0005).
@MainActor
public struct AutomationHistoryActions {
    public var runNow: @MainActor () -> Void = {}
    public var toggle: @MainActor () -> Void = {}
    public var goToSession: (String) -> Void = { _ in }
    public var openTranscript: (String) -> Void = { _ in }
    public init() {}
}

/// An automation's history in a tab, in the new frame's face (plan 30 B): its name, when it
/// runs, where, on which agent and under which cap; Run now and its switch; then a card per run,
/// newest first, with Session and Transcript. A page (isPage); read when it opens and on refresh.
@MainActor
public final class AutomationHistoryDocument: TabDocument {
    public let automationID: String
    public var onChange: (() -> Void)?
    public var onClose: (() -> Void)?
    public private(set) var title = "Automation"
    private let book: AutomationBook
    private let page = OrchestrationPage()
    private let actions: AutomationHistoryActions

    public init(automationID: String, book: AutomationBook, actions: AutomationHistoryActions) {
        self.automationID = automationID
        self.book = book
        self.actions = actions
        refresh()
    }

    public static func identity(for automation: String) -> String { "automation:\(automation)" }
    public var identity: String { Self.identity(for: automationID) }
    public var view: NSView { page }
    public var hasUnsavedChanges: Bool { false }
    public var isPage: Bool { true }

    public func refresh() {
        guard let automation = try? book.automation(automationID) else { return }
        let place = AutomationLaunch.place(automation)
        let target = { () -> String in
            if case .newWorktree = automation.target { return T("a new worktree of ", "uma worktree nova de ") + (place as NSString).lastPathComponent }
            return (place as NSString).abbreviatingWithTildeInPath
        }()
        let meta = AutomationSchedule.label(automation.recurrence) + " · " + target + " · " + RaceColumns.agentLabel(automation.agent)
            + " · " + T("cap US$ \(String(format: "%.2f", automation.caps.budgetUsd)) and \(automation.caps.maxMinutes) min",
                        "teto US$ \(String(format: "%.2f", automation.caps.budgetUsd)) e \(automation.caps.maxMinutes) min")
        let actions = actions
        let buttons = [OrchestrationPage.button(automation.enabled ? T("Turn off", "Desligar") : T("Turn on…", "Ligar…")) { actions.toggle() },
                       OrchestrationPage.button(T("Run now", "Executar agora"), primary: true) { actions.runNow() }]
        var runs: [NSView] = [OrchestrationPage.section(T("RUNS", "EXECUÇÕES"))]
        let lines = AutomationLines.make((try? book.history(of: automationID)) ?? [])
        if lines.isEmpty {
            runs.append(boardLabel(T("No runs yet.", "Nenhuma execução ainda."), size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textMuted))
        }
        for line in lines {
            var row: [NSView] = []
            if line.hasSession { row.append(OrchestrationPage.button(T("Session", "Sessão")) { actions.goToSession(line.run) }) }
            if line.hasTranscript { row.append(OrchestrationPage.button(T("Transcript", "Transcrição")) { actions.openTranscript(line.run) }) }
            runs.append(OrchestrationPage.card(state: Self.glyph(line.result), title: line.result,
                                               lines: [(line.text, DesignTokens.Board.Card.Meta.color)], buttons: row))
        }
        let column = OrchestrationPage.stack(runs, gap: DesignTokens.Board.Column.gap)
        for view in runs.dropFirst() { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        let state = boardLabel(automation.enabled ? T("On", "Ligada") : T("Off", "Desligada"), size: DesignTokens.FontSize.body,
                               color: automation.enabled ? DesignTokens.Color.stateDone : DesignTokens.Color.textMuted)
        page.show([OrchestrationPage.head(automation.name, meta: meta, buttons: buttons), state, column])
        if title != automation.name {
            title = automation.name
            onChange?()
        }
    }

    /// A run's result as its card's glyph.
    static func glyph(_ result: String) -> GlyphState {
        switch result {
        case AutomationLines.label(.running): .working
        case AutomationLines.label(.done): .done
        case AutomationLines.label(.skipped): .idle
        default: .failed
        }
    }

    public func focus() { refresh() }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() { onClose?() }
}
