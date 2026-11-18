import AppKit
import Agents
import CommandPalette
import Inspector
import Projects
import Strings

/// The side column's Sessions (plan 36 phase C; docs/adr/0038-rail-and-side-column.md): the chosen
/// project's conversations, grouped by when; the click opens the project page's Sessions on it. The
/// history is read only while the page shows (the column's rule), and let go when it goes.
extension WindowSession {
    func makeSessionsColumn() -> SessionsColumnView {
        let view = SessionsColumnView()
        view.onPick = { [weak self] id in
            guard let self, let folder = self.projects?.activeFolder else { return }
            self.openProjectPage(folder, section: .sessions, item: id)
        }
        return view
    }

    func sessionsColumnCommands() -> [Command] {
        [Command(id: "project.sessions-column", title: T("Show Sessions in the Side Column", "Mostrar as sessões na coluna lateral"),
                 keywords: ["sessions", "conversations", "history", "resume", "sessões", "conversas", "histórico", "retomar"],
                 category: .view, action: .run { [weak self] in self?.workspace?.showInspector("sessions") })]
    }

    private var sessionsColumn: SessionsColumnView? {
        workspace?.inspector.pages.first { $0.id == "sessions" }?.view as? SessionsColumnView
    }

    /// The page came into view: read the history while it shows; the column closing or another page
    /// lets it go.
    func showSessionsColumn() {
        workspace?.onColumnPage = { [weak self] page in if page != "sessions" { self?.stopSessionsColumn() } }
        if sessionsColumnHistory == nil {
            sessionsColumnRead = false
            sessionsColumnHistory = AgentHistoryController.shared.watch { [weak self] in
                self?.sessionsColumnRead = true
                self?.fillSessionsColumn()
            }
        }
        fillSessionsColumn()
    }

    func stopSessionsColumn() {
        guard let id = sessionsColumnHistory else { return }
        AgentHistoryController.shared.stop(id)
        sessionsColumnHistory = nil
    }

    private func fillSessionsColumn() {
        guard let view = sessionsColumn, let folder = projects?.activeFolder else { return }
        let now = Date()
        let calendar = Calendar.current
        var today: [PageListItem] = [], week: [PageListItem] = [], earlier: [PageListItem] = []
        for entry in projectSessions(folder).prefix(120) {
            let note = [Self.accountName(entry.account), ProjectPageWords.when(entry.updated, now: now)].filter { !$0.isEmpty }.joined(separator: " · ")
            let item = PageListItem(id: entry.id, title: entry.title, note: note)
            let when = entry.updated ?? .distantPast
            if calendar.isDate(when, inSameDayAs: now) { today.append(item) }
            else if now.timeIntervalSince(when) < 7 * 86400 { week.append(item) }
            else { earlier.append(item) }
        }
        // Until the history answers once, an empty list is "reading", not "none".
        let reading = AgentHistoryController.shared.progress.map { T("Reading the history… \($0.done) of \($0.total)", "Lendo o histórico… \($0.done) de \($0.total)") }
            ?? (sessionsColumnRead ? nil : T("Reading the history…", "Lendo o histórico…"))
        view.show([(T("Today", "Hoje"), today), (T("This week", "Esta semana"), week), (T("Earlier", "Antes"), earlier)], loading: reading)
    }
}
