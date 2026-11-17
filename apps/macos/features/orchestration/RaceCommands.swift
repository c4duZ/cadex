import AppKit
import CommandPalette
import Icons
import Strings

/// What the race's commands ask of the app: the form and the tabs are
/// the app's (it joins worktrees, agents and tabs).
public struct RaceCommandActions {
    public var toggle: () -> Void = {}
    public var newRace: () -> Void = {}
    public var show: (Race) -> Void = { _ in }
    public var pickWinner: (Race, Contender) -> Void = { _, _ in }
    public var discard: (Race) -> Void = { _ in }
    public var deleteBranches: (Race) -> Void = { _ in }
    public init() {}
}

/// The race's commands (docs/spec/orchestration.md, ADR 0005), each with
/// its list in ⌘K. Off, only the one that turns the feature on shows.
@MainActor
public enum RaceCommands {
    public static func all(palette: CommandPaletteController, actions: RaceCommandActions) -> [Command] {
        let controller = OrchestrationController.shared
        let off: @MainActor () -> String? = {
            controller.isEnabled ? nil : T("Races and runs are off (Settings › Many Agents)", "Corridas e execuções estão desligadas (Configurações › Muitos agentes)")
        }
        let keywords = ["race", "agents", "corrida", "agentes", "compare", "comparar", "orchestration"]
        func list(_ kind: RaceSource.Kind, _ id: String, _ title: String, _ more: [String]) -> Command {
            Command(id: id, title: title, keywords: keywords + more, category: .view,
                    action: .run { palette.open(RaceSource(kind: kind, palette: palette, actions: actions)) }, unavailableReason: off)
        }
        return [
            // One title for both ways: commands are registered once per window.
            Command(id: "orchestration.toggle", title: T("Turn Races and Runs On or Off", "Ligar ou desligar corridas e execuções"),
                    keywords: keywords + ["enable", "ligar", "desligar", "many agents", "muitos agentes"], category: .app,
                    action: .run { actions.toggle() }),
            Command(id: "orchestration.new-race", title: T("New Race: the Same Task in Several Agents", "Nova corrida: a mesma tarefa em vários agentes"),
                    keywords: keywords + ["new", "nova", "worktree", "task", "tarefa"], category: .view,
                    // Off is said by the New Task sheet, whose Start turns races on (plan 29).
                    action: .run { actions.newRace() }),
            list(.show, "orchestration.show-race", T("Show a Race", "Mostrar uma corrida"), ["board", "quadro", "show", "mostrar"]),
            list(.pickWinner, "orchestration.pick-winner", T("Pick a Race's Winner", "Escolher o vencedor de uma corrida"), ["winner", "vencedor", "pick"]),
            list(.discard, "orchestration.discard-race", T("Discard a Race's Other Worktrees", "Descartar as outras worktrees de uma corrida"),
                 ["discard", "descartar", "delete", "apagar"]),
            list(.deleteBranches, "orchestration.delete-race-branches", T("Delete a Race's Discarded Branches", "Apagar as branches descartadas de uma corrida"),
                 ["delete", "apagar", "branches"]),
        ]
    }
}

/// ⌘K's list of races (and, to pick a winner, then of contenders).
@MainActor
final class RaceSource: PaletteSource {
    enum Kind { case show, pickWinner, discard, deleteBranches, contenders(Race) }
    private let kind: Kind
    private weak var palette: CommandPaletteController?
    private let actions: RaceCommandActions

    init(kind: Kind, palette: CommandPaletteController, actions: RaceCommandActions) {
        self.kind = kind
        self.palette = palette
        self.actions = actions
    }

    var placeholder: String {
        switch kind {
        case .show: T("Show a race", "Mostrar uma corrida")
        case .pickWinner: T("The race to pick a winner in", "A corrida em que escolher o vencedor")
        case .discard: T("The race whose other worktrees to delete", "A corrida cujas outras worktrees apagar")
        case .deleteBranches: T("The race whose discarded branches to delete", "A corrida cujas branches descartadas apagar")
        case .contenders(let race): T("The winner of \(race.name)", "O vencedor de \(race.name)")
        }
    }
    var emptyText: String { T("No race fits", "Nenhuma corrida serve") }
    var icon: Icon { .gitBranch }

    /// The races this command acts on, newest first.
    static func races(for kind: Kind) -> [Race] {
        let all = ((try? OrchestrationController.shared.races()?.races()) ?? []).sorted { $0.createdAt > $1.createdAt }
        switch kind {
        case .show, .contenders: return all
        case .pickWinner: return all.filter { $0.winner == nil }
        case .discard: return all.filter { $0.winner != nil && !$0.discarded }
        case .deleteBranches:
            let book = OrchestrationController.shared.races()
            return all.filter { $0.discarded && !((try? book?.branchesLeft(race: $0.id)) ?? []).isEmpty }
        }
    }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        let match = { (text: String) in query.isEmpty || text.localizedCaseInsensitiveContains(query) }
        if case .contenders(let race) = kind {
            let contenders = (try? OrchestrationController.shared.races()?.contenders(of: race.id)) ?? []
            return show(contenders.filter { $0.state != .discarded && match($0.worktree) }.map { contender in
                PaletteItem(id: contender.id, title: "#\(contender.index) · " + (contender.worktree as NSString).lastPathComponent,
                            detail: RaceColumns.agentLabel(contender.agent), icon: .gitBranch)
            }, nil)
        }
        show(Self.races(for: kind).filter { match($0.name) }.map { race in
            PaletteItem(id: race.id, title: race.name, detail: race.prompt.split(separator: "\n").first.map(String.init), icon: .gitBranch)
        }, nil)
    }

    func choose(_ item: PaletteItem) {
        if case .contenders(let race) = kind {
            let contenders = (try? OrchestrationController.shared.races()?.contenders(of: race.id)) ?? []
            guard let contender = contenders.first(where: { $0.id == item.id }) else { return }
            return actions.pickWinner(race, contender)
        }
        guard let race = Self.races(for: kind).first(where: { $0.id == item.id }) else { return }
        switch kind {
        case .show: actions.show(race)
        case .discard: actions.discard(race)
        case .deleteBranches: actions.deleteBranches(race)
        case .pickWinner:
            // The palette just closed: the second list opens on the next turn.
            guard let palette else { return }
            let next = RaceSource(kind: .contenders(race), palette: palette, actions: actions)
            DispatchQueue.main.async { MainActor.assumeIsolated { palette.open(next) } }
        case .contenders: break
        }
    }

    func stop() {}
}
