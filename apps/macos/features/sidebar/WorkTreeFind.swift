import CommandPalette
import Icons
import Strings

/// sidebar.find, the tree's filter button (plan 27 phase B): every project, task and terminal of the
/// tree in ⌘K, found by name; picked, it shows as a click on its row would.
@MainActor
final class WorkTreeFindSource: PaletteSource {
    private weak var tree: WorkTreeView?

    init(tree: WorkTreeView) { self.tree = tree }

    var placeholder: String { T("Find a project, task or terminal", "Achar um projeto, tarefa ou terminal") }
    var emptyText: String { T("Nothing by that name", "Nada com esse nome") }
    var icon: Icon { .magnifyingGlass }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let tree else { return show([], nil) }
        var items: [PaletteItem] = []
        for project in tree.projects {
            items.append(PaletteItem(id: "p\u{1}" + project.id, title: project.name, detail: project.branch, icon: .folder))
            for task in project.tasks {
                items.append(PaletteItem(id: "k\u{1}" + task.id, title: task.name, detail: project.name, icon: .stack))
                items += task.terminals.map { PaletteItem(id: "t\u{1}" + $0.id, title: $0.title, detail: project.name + " › " + task.name, icon: .terminalWindow) }
            }
            items += project.terminals.map { PaletteItem(id: "t\u{1}" + $0.id, title: $0.title, detail: project.name, icon: .terminalWindow) }
        }
        let words = query.lowercased().split(separator: " ").map(String.init)
        show(items.filter { item in words.allSatisfy { (item.title + " " + (item.detail ?? "")).lowercased().contains($0) } }, nil)
    }

    func choose(_ item: PaletteItem) {
        let parts = item.id.split(separator: "\u{1}", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        switch parts[0] {
        case "p": tree?.onPick?(.project(parts[1]))
        case "k": tree?.onPick?(.task(parts[1]))
        default: tree?.onPick?(.terminal(parts[1]))
        }
    }

    func stop() {}
}

extension WorkTreeView {
    /// sidebar.find's list, for the app to open in the palette.
    public func findSource() -> PaletteSource { WorkTreeFindSource(tree: self) }
}
