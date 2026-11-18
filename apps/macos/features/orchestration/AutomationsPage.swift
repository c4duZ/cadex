import AppKit
import Icons
import Menus
import StateGlyph
import Strings
import Tabs
import UILooks

/// One automation's line on the Automations page (plan 34 F; docs/design/projects/proposta.html).
public struct AutomationsLine: Equatable {
    public var id: String
    public var name: String
    /// "Weekdays 09:00".
    public var when: String
    public var project: String
    public var account: String
    /// "done today", "never"; its state's dot when it ran.
    public var last: String
    public var lastState: GlyphState?
    /// "tomorrow 09:00", "—".
    public var next: String
    public var on: Bool

    public init(id: String, name: String, when: String, project: String, account: String, last: String, lastState: GlyphState?, next: String, on: Bool) {
        self.id = id
        self.name = name
        self.when = when
        self.project = project
        self.account = account
        self.last = last
        self.lastState = lastState
        self.next = next
        self.on = on
    }
}

/// What the Automations page asks the app; each one is a command's work (ADR 0005).
@MainActor
public struct AutomationsPageActions {
    public var create: () -> Void = {}
    public var open: (String) -> Void = { _ in }
    public var toggle: (String) -> Void = { _ in }
    public var runNow: (String) -> Void = { _ in }
    public var delete: (String) -> Void = { _ in }
    /// The lines and whether automations are on.
    public var load: () -> (lines: [AutomationsLine], enabled: Bool) = { ([], false) }
    public init() {}
}

/// The Automations page: it always opens. Empty, the whole area says what an automation is and
/// puts Create automation in the middle (the owner's adjustment to the proposal, 2026-11-18); off,
/// a note that creating the first turns them on. With some, a table: the switch, name, when,
/// project, account, the last and the next run; a click opens its runs, the right click has Run
/// Now, Turn On or Off and Delete. A page: under the bar, never in it.
@MainActor
public final class AutomationsPageDocument: TabDocument {
    public static let identity = "automation:all"
    private let actions: AutomationsPageActions
    private let page = OrchestrationPage()
    public var view: NSView { page }
    public var title: String { T("Automations", "Automações") }
    public var identity: String { Self.identity }
    public var hasUnsavedChanges: Bool { false }
    public var onChange: (() -> Void)?
    public var isPage: Bool { true }

    public init(actions: AutomationsPageActions) {
        self.actions = actions
        refresh()
    }

    public func focus() { refresh() }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    public func refresh() {
        let (lines, enabled) = actions.load()
        let create = OrchestrationPage.button("+  " + T("Create automation", "Criar automação"), primary: true) { [weak self] in self?.actions.create() }
        guard !lines.isEmpty else {
            let head = OrchestrationPage.head(title, meta: T("A prompt that runs by itself on a schedule, in an account and a project",
                                                            "Um prompt que roda sozinho num horário, numa conta e num projeto"), buttons: [])
            let empty = AutomationsEmpty(create: { [weak self] in self?.actions.create() }, off: !enabled)
            page.show([head, empty])
            empty.heightAnchor.constraint(greaterThanOrEqualTo: page.heightAnchor, multiplier: 1, constant: -UILooks.pt(AutomationsEmpty.chrome)).isActive = true
            return
        }
        let on = lines.filter(\.on).count
        var meta = T("\(lines.count) automations · \(on) on", "\(lines.count) automações · \(on) ligada" + (on == 1 ? "" : "s"))
        if let next = lines.first(where: { $0.on && $0.next != "—" })?.next { meta += T(" · the next runs ", " · a próxima roda ") + next }
        page.show([OrchestrationPage.head(title, meta: meta, buttons: [create]), table(lines),
                   boardLabel(T("Click a line for its runs and to edit it; the right click has Run Now, Turn On or Off and Delete.",
                                "Clique numa linha para ver as rodadas e editar; o botão direito tem Executar agora, Ligar ou desligar e Apagar."),
                              size: DesignTokens.FontSize.meta, color: DesignTokens.Color.textTertiary)])
    }

    private func table(_ lines: [AutomationsLine]) -> NSView {
        let rows: [NSView] = [AutomationTableRow.header()] + lines.map { line in
            let row = AutomationTableRow(line)
            row.onPress = { [weak self] in self?.actions.open(line.id) }
            row.onToggle = { [weak self] in self?.actions.toggle(line.id) }
            row.entries = { [weak self] in
                guard let self else { return [] }
                return [MenuEntry(T("Run Now", "Executar agora"), icon: .play) { self.actions.runNow(line.id) },
                        MenuEntry(line.on ? T("Turn Off", "Desligar") : T("Turn On", "Ligar"), icon: .clock) { self.actions.toggle(line.id) },
                        .separator,
                        MenuEntry(T("Delete…", "Apagar…"), icon: .trash) { self.actions.delete(line.id) }]
            }
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.wantsLayer = true
        stack.layer?.borderColor = DesignTokens.Color.lineDefault.cgColor
        stack.layer?.borderWidth = DesignTokens.Stroke.hairline
        stack.layer?.cornerRadius = UILooks.pt(DesignTokens.Radius.card)
        stack.layer?.backgroundColor = DesignTokens.Color.bgSidebar.cgColor
        stack.layer?.masksToBounds = true
        for row in rows { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return stack
    }
}
