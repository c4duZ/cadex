import AppKit
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
public struct AutomationHistoryActions {
    public var runNow: () -> Void = {}
    public var toggle: () -> Void = {}
    public var goToSession: (String) -> Void = { _ in }
    public var openTranscript: (String) -> Void = { _ in }
    public init() {}
}

/// An automation's history in a tab: what it runs and when, then one line
/// per run, newest first; read when it opens and on `refresh`.
@MainActor
public final class AutomationHistoryDocument: TabDocument {
    public let automationID: String
    public var onChange: (() -> Void)?
    public var onClose: (() -> Void)?
    public private(set) var title = "Automation"
    private let book: AutomationBook
    private let page = FlippedView()
    private let stack = NSStackView()
    private let colors: RaceBoardColors
    private let actions: AutomationHistoryActions

    public init(automationID: String, book: AutomationBook, colors: RaceBoardColors, actions: AutomationHistoryActions) {
        self.automationID = automationID
        self.book = book
        self.colors = colors
        self.actions = actions
        page.wantsLayer = true
        page.layer?.backgroundColor = colors.background.cgColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: page.leadingAnchor), stack.topAnchor.constraint(equalTo: page.topAnchor),
                                     stack.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor)])
        refresh()
    }

    public static func identity(for automation: String) -> String { "automation:\(automation)" }
    public var identity: String { Self.identity(for: automationID) }
    public var view: NSView { page }
    public var hasUnsavedChanges: Bool { false }

    public func refresh() {
        guard let automation = try? book.automation(automationID) else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        stack.addArrangedSubview(label(automation.name, 18, .semibold, colors.text))
        let place = AutomationLaunch.place(automation)
        let target = { () -> String in
            if case .newWorktree = automation.target { return T("a new worktree of ", "uma worktree nova de ") + (place as NSString).lastPathComponent }
            return (place as NSString).abbreviatingWithTildeInPath
        }()
        stack.addArrangedSubview(label(AutomationSchedule.label(automation.recurrence) + " · " + target + " · " + RaceColumns.agentLabel(automation.agent)
                                       + " · " + T("cap US$ \(String(format: "%.2f", automation.caps.budgetUsd)) and \(automation.caps.maxMinutes) min",
                                                   "teto US$ \(String(format: "%.2f", automation.caps.budgetUsd)) e \(automation.caps.maxMinutes) min"),
                                       12, .regular, colors.secondary))
        stack.addArrangedSubview(label(automation.enabled ? T("On", "Ligada") : T("Off", "Desligada"), 12, .regular, automation.enabled ? colors.accent : colors.secondary))
        stack.addArrangedSubview(NSStackView(views: [
            button(T("Run Now", "Executar agora"), actions.runNow),
            button(automation.enabled ? T("Turn Off", "Desligar") : T("Turn On…", "Ligar…"), actions.toggle),
        ]))
        let lines = AutomationLines.make((try? book.history(of: automationID)) ?? [])
        if lines.isEmpty { stack.addArrangedSubview(label(T("No runs yet.", "Nenhuma execução ainda."), 12, .regular, colors.secondary)) }
        for line in lines {
            var row: [NSView] = [label(line.result, 12, .semibold, colors.text), label(line.text, 12, .regular, colors.secondary)]
            let go = actions.goToSession, open = actions.openTranscript
            if line.hasSession { row.append(button(T("Session", "Sessão")) { go(line.run) }) }
            if line.hasTranscript { row.append(button(T("Transcript", "Transcrição")) { open(line.run) }) }
            stack.addArrangedSubview(NSStackView(views: row))
        }
        if title != automation.name {
            title = automation.name
            onChange?()
        }
    }

    private func label(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(title: title, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    public func focus() { page.window?.makeFirstResponder(page) }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() { onClose?() }
}
