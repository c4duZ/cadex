import AppKit
import Menus
import Projects
import Sidebar
import Strings
import Themes

/// The place at the start of the top bar (ADR 0039, plan 38 phase E): "project › task ▾", from the
/// shown project and the group of its bar; the click opens the place's menu (the projects, this
/// project's main and tasks, its page). Review shows inside a task.
extension WindowSession {
    func showPlace() {
        guard let workspace else { return }
        let bar = workspace.titleBar
        guard let folder = projects?.activeFolder, !Self.isLoose(folder),
              let project = sidebarModel().first(where: { $0.id == folder }) else {
            bar.place.isHidden = true
            bar.setReviewShown(false)
            return
        }
        bar.place.isHidden = false
        let group = tabs?.currentGroup ?? ""
        let task = project.places.first { !$0.isMain && $0.id == group }
        let tint = project.tint.map { NSColor(srgbRed: $0[0], green: $0[1], blue: $0[2], alpha: 1) } // token-exempt: the project's own color, from the app
        bar.place.show(project: project.name, task: task?.name, mark: project.emoji.flatMap { $0.isEmpty ? nil : $0 } ?? project.initials,
                       image: project.image, tint: tint)
        bar.setReviewShown(task != nil)
    }

    /// The place's menu: go to a project, to this project's main or a task, or open its page.
    func placeMenu() -> [MenuEntry] {
        let projectsModel = sidebarModel()
        let current = projects?.activeFolder
        var entries: [MenuEntry] = []
        if let project = projectsModel.first(where: { $0.id == current }) {
            for place in project.places {
                entries.append(MenuEntry(place.isMain ? T("\(place.name) (the project's own)", "\(place.name) (o do projeto)") : place.name,
                                         icon: place.isMain ? .terminalWindow : .gitBranch) { [weak self] in self?.pickPlace(place.id) })
            }
            entries.append(MenuEntry(T("Project Page", "Página do projeto"), icon: .squaresFour) { [weak self] in
                _ = self?.commands.run("project.show-overview")
            })
            entries.append(.separator)
        }
        for project in projectsModel where project.id != current {
            entries.append(MenuEntry(project.name, icon: .folder) { [weak self] in self?.pickProject(project.id) })
        }
        entries.append(MenuEntry(T("Switch Project…", "Trocar de projeto…"), icon: .magnifyingGlass) { [weak self] in
            _ = self?.commands.run("project.switch")
        })
        return entries
    }
}
