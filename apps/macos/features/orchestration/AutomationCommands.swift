import AppKit
import CommandPalette
import Icons
import Strings

/// What the automations' commands ask of the app (the sheets, the launch,
/// the LaunchAgent are the app's).
public struct AutomationCommandActions {
    public var toggleAll: () -> Void = {}
    public var new: () -> Void = {}
    public var toggle: (Automation) -> Void = { _ in }
    public var runNow: (Automation) -> Void = { _ in }
    public var showHistory: (Automation) -> Void = { _ in }
    public init() {}
}

/// The automations' commands (docs/spec/orchestration.md "Automações"; plan
/// 24 E; ADR 0005), each with its list in ⌘K. Off, only the one that turns
/// them on shows.
@MainActor
public enum AutomationCommands {
    public static func all(palette: CommandPaletteController, actions: AutomationCommandActions) -> [Command] {
        let off: @MainActor () -> String? = {
            OrchestrationController.shared.automationsEnabled ? nil : T("Automations are off (Settings › Many Agents)", "Automações estão desligadas (Configurações › Muitos agentes)")
        }
        let keywords = ["automation", "automação", "schedule", "agenda", "cron", "every", "horário", "orchestration"]
        func list(_ kind: AutomationSource.Kind, _ id: String, _ title: String, _ more: [String]) -> Command {
            Command(id: id, title: title, keywords: keywords + more, category: .view,
                    action: .run { palette.open(AutomationSource(kind: kind, actions: actions)) }, unavailableReason: off)
        }
        return [
            Command(id: "orchestration.toggle-automations", title: T("Turn Automations On or Off", "Ligar ou desligar as automações"),
                    keywords: keywords + ["enable", "ligar", "desligar"], category: .app, action: .run { actions.toggleAll() }),
            Command(id: "orchestration.new-automation", title: T("New Automation: a Prompt on a Schedule", "Nova automação: um prompt num horário"),
                    keywords: keywords + ["new", "nova"], category: .view, action: .run { actions.new() }, unavailableReason: off),
            list(.toggle, "orchestration.toggle-automation", T("Turn an Automation On or Off", "Ligar ou desligar uma automação"), ["toggle", "ligar"]),
            list(.runNow, "orchestration.run-automation-now", T("Run an Automation Now", "Executar uma automação agora"), ["run", "now", "agora"]),
            list(.history, "orchestration.show-automation-history", T("Show an Automation's History", "Mostrar o histórico de uma automação"),
                 ["history", "histórico", "runs"]),
        ]
    }
}

@MainActor
final class AutomationSource: PaletteSource {
    enum Kind { case toggle, runNow, history }
    private let kind: Kind
    private let actions: AutomationCommandActions

    init(kind: Kind, actions: AutomationCommandActions) {
        self.kind = kind
        self.actions = actions
    }

    var placeholder: String {
        switch kind {
        case .toggle: T("The automation to turn on or off", "A automação para ligar ou desligar")
        case .runNow: T("The automation to run now", "A automação para executar agora")
        case .history: T("The automation whose history to show", "A automação cujo histórico mostrar")
        }
    }
    var emptyText: String { T("No automations yet: New Automation (orchestration.new-automation)", "Nenhuma automação ainda: Nova automação (orchestration.new-automation)") }
    var icon: Icon { .gitBranch }

    func items() -> [Automation] {
        ((try? OrchestrationController.shared.automations()?.automations()) ?? []).sorted { $0.name < $1.name }
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let match = { (text: String) in query.isEmpty || text.localizedCaseInsensitiveContains(query) }
        show(items().filter { match($0.name) }.map { automation in
            PaletteItem(id: automation.id, title: automation.name,
                        detail: (automation.enabled ? T("on", "ligada") : T("off", "desligada")) + " · " + AutomationSchedule.label(automation.recurrence),
                        icon: .gitBranch)
        }, nil)
    }

    func choose(_ item: PaletteItem) {
        guard let automation = items().first(where: { $0.id == item.id }) else { return }
        let actions = self.actions
        let kind = self.kind
        DispatchQueue.main.async {
            switch kind {
            case .toggle: actions.toggle(automation)
            case .runNow: actions.runNow(automation)
            case .history: actions.showHistory(automation)
            }
        }
    }

    func stop() {}
}
