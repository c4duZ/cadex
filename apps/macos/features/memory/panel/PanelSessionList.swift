import AppKit
import Menus
import Strings
import UILooks

/// What a session row can do; each is a command's work (ADR 0005).
@MainActor
struct PanelSessionActions {
    var open: (PanelSession) -> Void = { _ in }
    /// Nil: no Cadex project has this one's folder, so no "Abrir no Cadex".
    var openInCadex: ((PanelSession) -> Void)?
}

/// The sessions' table (MemoryAgent.dc.html, SESSÕES; the project's Sessões tab with the Agente
/// column): Sessão (the short id, ↗ opens the timeline), Estado, Início, Duração, Eventos, Tokens ·
/// entrada / saída. The row under the pointer or chosen shows "Abrir no Cadex", also in its right
/// click and by ⌘O; Enter opens the session; the arrows choose.
@MainActor
final class PanelSessionList: NSView {
    let sessions: [PanelSession]
    let table: PanelTable
    private let actions: PanelSessionActions

    init(_ sessions: [PanelSession], withAgent: Bool, now: Date, actions: PanelSessionActions) {
        self.sessions = sessions
        self.actions = actions
        var columns = [PanelColumn(title: T("Session", "Sessão"), share: 0.13)]
        if withAgent { columns.append(PanelColumn(title: T("Agent", "Agente"), share: 0.12)) }
        columns += [PanelColumn(title: T("State", "Estado"), share: 0.11), PanelColumn(title: T("Started", "Início"), share: 0.11),
                    PanelColumn(title: T("Duration", "Duração"), share: 0.09), PanelColumn(title: T("Events", "Eventos"), share: 0.08),
                    PanelColumn(title: T("Tokens · in / out", "Tokens · entrada / saída"), share: nil)]
        table = PanelTable(columns)
        super.init(frame: .zero)
        table.show(sessions.map { cells($0, withAgent: withAgent, now: now) })
        for (row, session) in zip(table.rows, sessions) {
            row.onPress = { actions.open(session) }
            row.entriesFor = { [weak self] in self?.entries(session) ?? [] }
            row.setAccessibilityLabel(T("Session ", "Sessão ") + PanelWords.shortID(session.id))
            if let open = actions.openInCadex, let last = row.cells {
                let link = PanelLink(T("Open in Cadex", "Abrir no Cadex"), size: MP.Table.Row.fontSize) { open(session) }
                last.addArrangedSubview(link)
                row.accessory = link
            }
        }
        table.translatesAutoresizingMaskIntoConstraints = false
        addSubview(table)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: topAnchor), table.bottomAnchor.constraint(equalTo: bottomAnchor),
            table.leadingAnchor.constraint(equalTo: leadingAnchor), table.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(T("Sessions", "Sessões"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PanelSessionList is created in code") }

    private func cells(_ s: PanelSession, withAgent: Bool, now: Date) -> [NSView] {
        typealias R = MP.Table.Row
        let id = PanelText.line((s.name.map { $0 + " · " } ?? "") + PanelWords.shortID(s.id) + " ↗", size: R.fontSize, color: MP.Link.color)
        id.font = UILooks.monospaced(R.fontSize)
        var out: [NSView] = [id]
        if withAgent { out.append(PanelText.line(PanelWords.agents([s.agent]), size: R.fontSize, color: R.color)) }
        out.append(PanelChip.cell(s.isOpen ? T("Open", "Aberta") : T("Ended", "Encerrada"), s.isOpen ? .open : .closed, dot: true))
        out.append(PanelText.line(s.started.map { PanelWords.ago($0, now: now) } ?? "—", size: R.fontSize, color: R.color))
        out.append(PanelText.line(PanelWords.duration(s.started, s.ended), size: R.fontSize, color: R.color))
        out.append(PanelText.line(PanelWords.number(s.events), size: R.fontSize, color: R.color))
        out.append(PanelText.line(PanelWords.inOut(s.usage), size: R.fontSize, color: R.color))
        return out
    }

    func entries(_ session: PanelSession) -> [MenuEntry] {
        var list = [MenuEntry(T("Open Timeline", "Abrir a linha do tempo"), icon: .arrowSquareOut) { [actions] in actions.open(session) }]
        if let open = actions.openInCadex {
            list.append(MenuEntry(T("Open in Cadex", "Abrir no Cadex"), icon: .folderOpen, shortcut: "⌘O") { open(session) })
        }
        return list
    }

    var chosenSession: PanelSession? { table.chosen.map { sessions[$0] } }

    // MARK: The keys

    override var acceptsFirstResponder: Bool { !sessions.isEmpty }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125: table.choose(by: 1)  // ↓
        case 126: table.choose(by: -1)  // ↑
        case 36, 76: if let s = chosenSession { actions.open(s) } else { super.keyDown(with: event) }  // Return, Enter
        default: super.keyDown(with: event)
        }
    }

    /// ⌘O with a row chosen: Abrir no Cadex, before the menu's ⌘O (open a folder).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              event.charactersIgnoringModifiers == "o", let s = chosenSession, let open = actions.openInCadex else {
            return super.performKeyEquivalent(with: event)
        }
        open(s)
        return true
    }

    /// For tests.
    func pressOpen(_ index: Int) { table.rows[index].onPress?() }
    var linksShown: Int { table.rows.filter { $0.accessory?.isHidden == false }.count }
}
