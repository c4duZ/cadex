import AppKit
import Agents
import CommandPalette
import Icons
import Sidebar
import StateGlyph
import Strings
import UILooks

/// ⌘J (plan 29 phase C; the Switcher mockup): jump to the work by what it needs from you. The
/// tasks and the agents' terminals of every project in this window, in three groups (NEEDS YOU,
/// FINISHED, WORKING), each with its state, its name, "project · what it waits for or does" and
/// ⌘1…⌘9; typing filters them, and words that find nothing become New Task's request.
extension WindowSession {
    func jumpCommands(palette: CommandPaletteController) -> [Command] {
        [Command(id: "view.jump", title: T("Jump to a Task…", "Ir para uma tarefa…"),
                 keywords: ["jump", "switch", "task", "agent", "needs", "working", "finished", "ir", "trocar", "tarefa", "agente"],
                 category: .view, defaultShortcut: "cmd+j",
                 action: .run { [weak self] in
                     guard let self else { return }
                     palette.open(JumpSource(window: self))
                 })]
    }
}

@MainActor
final class JumpSource: PaletteSource {
    private weak var window: WindowSession?
    private var rows: [JumpRow] = []
    private var query = ""
    static let newTaskID = "jump.new-task"

    /// The sessions read while ⌘J is open (the status bar's item may be hidden).
    private var sessionsWatch: UUID?

    init(window: WindowSession) {
        self.window = window
        sessionsWatch = AgentsController.shared.watch {}
    }

    var placeholder: String { T("Jump to a task, or type to start one", "Ir para uma tarefa, ou escreva para começar uma") }
    var emptyText: String { "" }
    var icon: Icon { .magnifyingGlass }
    var width: CGFloat? { UILooks.pt(DesignTokens.Sheet.switcherWidth) }
    var showsFooter: Bool { false }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        self.query = query.trimmingCharacters(in: .whitespaces)
        let all = JumpRow.ordered(JumpRow.rows(window?.treeModel() ?? []) + outside())
        rows = self.query.isEmpty ? all : all.filter { $0.matches(self.query) }
        var items = rows.enumerated().map { index, row in
            var item = PaletteItem(id: "\(index)", title: row.name, detail: row.detail, shortcut: index < 9 ? "⌘\(index + 1)" : nil,
                                   section: JumpRow.groups[row.group ?? 0], image: Self.glyph(row.state))
            item.look = .jump
            return item
        }
        let project = window?.projects?.activeName ?? ""
        let title = self.query.isEmpty || !rows.isEmpty
            ? T("New task in \(project)…", "Nova tarefa em \(project)…")
            : T("New task in \(project): “\(self.query)”", "Nova tarefa em \(project): “\(self.query)”")
        var action = PaletteItem(id: Self.newTaskID, title: title, bold: title.range(of: project).map { [$0] } ?? [],
                                 shortcut: window?.app.keymapLabel("worktrees.new-task"), section: " ", icon: .plus)
        action.look = .jumpAction
        items.append(action)
        // "⌘J" on the field's right, as the mockup (the palette's status place).
        show(items, window?.app.keymapLabel("view.jump"))
    }

    func choose(_ item: PaletteItem) {
        guard let window else { return }
        if item.id == Self.newTaskID { return window.showNewTask(prompt: rows.isEmpty ? query : "") }
        guard let index = Int(item.id), rows.indices.contains(index) else { return }
        if let pick = rows[index].pick { return window.pickInTree(pick) }
        if let id = rows[index].session, let session = AgentsController.shared.sessions.first(where: { $0.id == id }) { window.openAgent(session) }
    }

    /// The sessions running outside Cadex's terminals (another terminal app, `claude --bg`):
    /// working, waiting for a permission (needs you) or for the next message (finished).
    private func outside() -> [JumpRow] {
        guard let window else { return [] }
        let windows = window.app.sessions
        return AgentsController.shared.sessions.filter { session in session.machine == nil && windows.allSatisfy { $0.terminal(of: session) == nil } }
            .compactMap { session -> JumpRow? in
                let state: GlyphState
                switch session.status {
                case .working: state = .working
                case .waiting: state = session.waitingFor == nil ? .done : .needs
                case .other: return nil
                }
                let project = AgentProject.of(session.cwd).root
                let doing = [(project as NSString).lastPathComponent, session.waitingFor ?? "", T("outside Cadex", "fora do Cadex")].filter { !$0.isEmpty }
                return JumpRow(session: session.id, state: state, name: session.name, detail: doing.joined(separator: " · "))
            }
    }

    func stop() {
        if let sessionsWatch { AgentsController.shared.stop(sessionsWatch) }
        sessionsWatch = nil
    }

    /// The state's glyph as the row's image (the tree's, not spinning).
    static func glyph(_ state: GlyphState) -> NSImage {
        let side = UILooks.pt(DesignTokens.Pane.Header.glyph)
        let margin = StateGlyphLook.margin(size: side)
        let size = NSSize(width: side + 2 * margin, height: side + 2 * margin)
        // Drawn now, on the main thread (the look reads the tokens there).
        let image = NSImage(size: size)
        image.lockFocus()
        StateGlyphLook.draw(state, in: NSRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin))
        image.unlockFocus()
        return image
    }
}
