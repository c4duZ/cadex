import Foundation
import Strings
import Tabs

// MARK: Pinned (plan 36; docs/adr/0038-rail-and-side-column.md)

extension ProjectsController {
    /// A pinned project with no terminal left stays; shown, it gives way to one with terminals, or
    /// to the home screen.
    func keepEmpty(_ project: Project) {
        if let index = projects.firstIndex(where: { $0 === project }), index == activeIndex {
            project.tabs.setShown(false)
            if let other = projects.firstIndex(where: { $0 !== project && $0.tabs.count > 0 }) {
                select(other)
            } else {
                activeIndex = -1
                onNone?()
            }
        }
        onChange?()
        scheduleSave()
    }

    public func isPinned(_ folder: String) -> Bool { projects.first { $0.folder == folder }?.pinned ?? false }

    public func setPinned(_ pinned: Bool, for folder: String) {
        guard let project = projects.first(where: { $0.folder == folder }), project.pinned != pinned else { return }
        project.pinned = pinned
        // Unpinned with no terminal: nothing keeps it in the rail.
        if !pinned, project.tabs.count == 0, let index = projects.firstIndex(where: { $0 === project }) {
            return remove(at: index)
        }
        onChange?()
        scheduleSave()
    }

    /// Close Terminals: every tab of the project, asking as project.close does; a pinned one stays.
    public func closeTerminals(folder: String) {
        guard let project = projects.first(where: { $0.folder == folder }) else { return }
        guard project.pinned else { return close(folder: folder) }
        let tabs = project.tabs
        let close: @MainActor () -> Void = { [weak self, weak project] in
            tabs.closeAll()
            if let self, let project { self.keepEmpty(project) }
        }
        if TabsController.shouldClose([tabs], in: tabs.hostWindow, what: T("the project", "o projeto"), then: close) { close() }
    }

    /// Remove from the Sidebar: unpinned and closed (nothing on disk goes).
    public func removeFromRail(folder: String) {
        projects.first { $0.folder == folder }?.pinned = false
        close(folder: folder)
    }
}
