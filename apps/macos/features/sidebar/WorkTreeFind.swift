import CommandPalette
import Icons
import Strings

/// sidebar.find (plan 27 phase B; the tree left the screen with ADR 0038 and its view went in plan
/// 36): every project, task and terminal of the work's model in ⌘K, found by name; picked, the app
/// shows it as a click on its row did (`pick`).
@MainActor
public final class WorkTreeFindSource: PaletteSource {
    private let projects: [WorkTreeProject]
    private let pick: (WorkTreePick) -> Void

    public init(projects: [WorkTreeProject], pick: @escaping (WorkTreePick) -> Void) {
        self.projects = projects
        self.pick = pick
    }

    public var placeholder: String { T("Find a project, task or terminal", "Achar um projeto, tarefa ou terminal") }
    public var emptyText: String { T("Nothing by that name", "Nada com esse nome") }
    public var icon: Icon { .magnifyingGlass }

    public func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        show(items(query), nil)
    }

    func items(_ query: String) -> [PaletteItem] {
        var items: [PaletteItem] = []
        for project in projects {
            items.append(PaletteItem(id: "p\u{1}" + project.id, title: project.name, detail: project.branch, icon: .folder))
            for task in project.tasks {
                items.append(PaletteItem(id: "k\u{1}" + task.id, title: task.name, detail: project.name, icon: .stack))
                items += task.terminals.map { PaletteItem(id: "t\u{1}" + $0.id, title: $0.title, detail: project.name + " › " + task.name, icon: .terminalWindow) }
            }
            items += project.terminals.map { PaletteItem(id: "t\u{1}" + $0.id, title: $0.title, detail: project.name, icon: .terminalWindow) }
        }
        let words = query.lowercased().split(separator: " ").map(String.init)
        return items.filter { item in words.allSatisfy { (item.title + " " + (item.detail ?? "")).lowercased().contains($0) } }
    }

    public func choose(_ item: PaletteItem) {
        let parts = item.id.split(separator: "\u{1}", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "p": pick(.project(parts[1]))
        case "k": pick(.task(parts[1]))
        default: pick(.terminal(parts[1]))
        }
    }

    public func stop() {}
}
