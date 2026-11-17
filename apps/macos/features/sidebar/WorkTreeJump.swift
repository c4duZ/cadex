import Foundation
import StateGlyph
import Strings

/// One row of ⌘J, from the tree's model (plan 29 phase C; the Switcher mockup): the app turns the
/// rows into the palette's items (JumpWiring.swift). Pure, so the groups are testable.
public struct JumpRow: Equatable, Sendable {
    /// Where a choice goes: a task or terminal of the tree, or a session outside Cadex (its id).
    public var pick: WorkTreePick?
    public var session: String?
    public var state: GlyphState
    public var name: String
    public var detail: String

    /// The group it shows in; nil for the work with nothing to say (idle).
    public var group: Int? {
        switch state {
        case .needs, .failed: 0
        case .done, .review: 1
        case .working: 2
        case .idle: nil
        }
    }

    public static let groups = [T("NEEDS YOU", "PRECISA DE VOCÊ"), T("FINISHED", "TERMINOU"), T("WORKING", "TRABALHANDO")]

    /// From the tree's model: each task, and each terminal of a project where an agent runs.
    public static func rows(_ projects: [WorkTreeProject]) -> [JumpRow] {
        var rows: [JumpRow] = []
        for project in projects {
            for task in project.tasks {
                let doing = task.waiting.isEmpty ? (task.comment.isEmpty ? task.terminals.first(where: { !$0.note.isEmpty })?.note ?? "" : task.comment) : task.waiting
                rows.append(JumpRow(pick: .task(task.id), state: task.state, name: task.name,
                                    detail: [project.name, doing].filter { !$0.isEmpty }.joined(separator: " · ")))
            }
            for terminal in project.terminals {
                guard let state = terminal.state else { continue }
                let doing = terminal.waiting.isEmpty ? terminal.note : terminal.waiting
                rows.append(JumpRow(pick: .terminal(terminal.id), state: state, name: terminal.title,
                                    detail: [project.name, doing].filter { !$0.isEmpty }.joined(separator: " · ")))
            }
        }
        return ordered(rows)
    }

    /// In the groups' order, the given order inside each; idle rows left out.
    public static func ordered(_ rows: [JumpRow]) -> [JumpRow] {
        rows.filter { $0.group != nil }.enumerated().sorted { ($0.element.group!, $0.offset) < ($1.element.group!, $1.offset) }.map(\.element)
    }

    /// A session outside Cadex (no terminal of it here; the spec: they show in ⌘J too).
    public init(session: String, state: GlyphState, name: String, detail: String) {
        self.session = session
        self.state = state
        self.name = name
        self.detail = detail
    }

    public init(pick: WorkTreePick, state: GlyphState, name: String, detail: String) {
        self.pick = pick
        self.state = state
        self.name = name
        self.detail = detail
    }

    /// Words in any order found in the name or the detail.
    public func matches(_ query: String) -> Bool {
        let text = (name + " " + detail).lowercased()
        return query.lowercased().split(separator: " ").allSatisfy { text.contains($0) }
    }
}

