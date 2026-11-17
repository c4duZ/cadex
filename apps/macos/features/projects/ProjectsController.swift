import AppKit
import Strings
import Tabs

/// Entry point of the projects feature (docs/spec/projects.md; plan 27, what were the spaces): a
/// folder with its tabs, a name and a color, one shown in the window at a time, saved after every
/// change and restored at launch. Each project is a TabsController; the hidden ones keep their
/// shells running.
@MainActor
public final class ProjectsController {
    public final class Project {
        public var name: String
        /// Its repository's folder (ProjectsFile.repositoryRoot).
        public let folder: String
        public let tabs: TabsController
        /// A work color's name (project.set-color, plan 15, phase D).
        public var color: String?

        init(name: String, folder: String, tabs: TabsController) {
            self.name = name
            self.folder = folder
            self.tabs = tabs
        }
    }

    public private(set) var projects: [Project] = []
    public private(set) var activeIndex = 0
    public var active: TabsController? { projects.indices.contains(activeIndex) ? projects[activeIndex].tabs : nil }
    public var activeName: String { projects.indices.contains(activeIndex) ? projects[activeIndex].name : "" }
    public var activeFolder: String? { projects.indices.contains(activeIndex) ? projects[activeIndex].folder : nil }
    /// The window shows these tabs now: the app swaps the view and the bar.
    public var onSwitch: ((TabsController) -> Void)?
    /// A name or the active project changed (the title bar's label).
    public var onChange: (() -> Void)?
    /// The workspace folder to save with the projects.
    public var workspaceFolder: (() -> String?)?
    private let makeTabs: () -> TabsController
    /// Nil for a passing window (⌘N): only the main window is saved (docs/spec/workspace.md).
    private let fileURL: URL?
    private var savePending = false
    /// While restoring, the half-built state must not overwrite the file.
    private var restoring = false
    /// After the window closed nothing is saved: the shells ending must not overwrite what the
    /// window had.
    private var closed = false
    /// How long after a change the file is written: changes come in bursts (a split retitles,
    /// refocuses and resizes), and a crash loses at most this.
    static let saveDelay = 0.5

    /// `makeTabs` makes a TabsController wired to the window (status bar, preview offers); the
    /// projects add the saving and the empty-project rule.
    public init(fileURL: URL? = ProjectsFile.defaultURL, makeTabs: @escaping () -> TabsController) {
        self.fileURL = fileURL
        self.makeTabs = makeTabs
    }

    /// The saved projects, or the project of `folder` with a terminal in it. `makeDocument` makes a
    /// saved document from its identity (nil when it is gone).
    public func start(folder: String, makeDocument: (String) -> TabDocument?) {
        restoring = true
        defer { restoring = false }
        let saved = fileURL.flatMap(ProjectsFile.load(from:))
        for project in saved?.projects ?? [] {
            let tabs = add(name: project.name, folder: project.folder)
            projects[projects.count - 1].color = project.color
            activeIndex = projects.count - 1
            tabs.restore(project.tabs, makeDocument: makeDocument)
            // Saved with no tab: a terminal in its folder (the spec), or the launch folder when gone.
            if tabs.count == 0 { tabs.newTab(cwd: FileManager.default.fileExists(atPath: project.folder) ? project.folder : folder) }
        }
        if projects.isEmpty {
            let root = ProjectsFile.repositoryRoot(folder)
            add(name: Self.name(of: root), folder: root).newTab(cwd: folder)
        }
        let index = min(max(saved?.active ?? 0, 0), projects.count - 1)
        projects.forEach { $0.tabs.isShown = false }
        activeIndex = -1
        select(index)
    }

    @discardableResult
    private func add(name: String, folder: String) -> TabsController {
        let tabs = makeTabs()
        let project = Project(name: name, folder: folder, tabs: tabs)
        tabs.isShown = false
        tabs.onStateChange = { [weak self] in self?.scheduleSave() }
        tabs.onEmpty = { [weak self, weak project] in
            guard let self, let project else { return }
            self.emptied(project)
        }
        projects.append(project)
        return tabs
    }

    /// A project's name from its folder.
    static func name(of folder: String) -> String {
        let name = (folder as NSString).lastPathComponent
        return name.isEmpty ? folder : name
    }

    /// The last tab of a project closed: the project goes, or the window when it was the only one
    /// (the home screen takes this over in plan 29).
    private func emptied(_ project: Project) {
        guard projects.count > 1, let index = projects.firstIndex(where: { $0 === project }) else {
            saveNow()
            project.tabs.hostWindow?.close()
            return
        }
        remove(at: index)
    }

    // MARK: Switching

    public func select(_ index: Int) {
        guard projects.indices.contains(index), index != activeIndex else { return }
        if projects.indices.contains(activeIndex) { projects[activeIndex].tabs.setShown(false) }
        activeIndex = index
        let tabs = projects[index].tabs
        onSwitch?(tabs)
        tabs.setShown(true)
        onChange?()
        scheduleSave()
    }

    /// ⌃⌘→ and ⌃⌘←, wrapping.
    public func selectNext(step: Int) {
        guard projects.count > 1 else { return }
        select((activeIndex + step + projects.count) % projects.count)
    }

    /// project.new: the project of `folder` (its repository), shown; one that exists already is
    /// only shown (the spec: opening a project's folder goes to it).
    public func open(folder: String) {
        let root = ProjectsFile.repositoryRoot(folder)
        if let index = projects.firstIndex(where: { $0.folder == root }) { return select(index) }
        add(name: Self.name(of: root), folder: root).newTab(cwd: folder)
        select(projects.count - 1)
    }

    public var activeColor: String? { projects.indices.contains(activeIndex) ? projects[activeIndex].color : nil }

    /// The active project's work color; nil takes it off.
    public func setActiveColor(_ name: String?) {
        guard projects.indices.contains(activeIndex) else { return }
        projects[activeIndex].color = name
        onChange?()
        scheduleSave()
    }

    /// project.rename: empty goes back to the folder's name (docs/spec/projects.md).
    public func rename(at index: Int, to name: String) {
        guard projects.indices.contains(index) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        projects[index].name = trimmed.isEmpty ? Self.name(of: projects[index].folder) : trimmed
        onChange?()
        scheduleSave()
    }

    /// project.close: asks over running programs and unsaved files, then shows the project before
    /// it. The last project does not close until the home screen exists (plan 29).
    public func closeActive() {
        guard projects.count > 1, let tabs = active else { return }
        let index = activeIndex
        let close: @MainActor () -> Void = { [weak self] in
            tabs.closeAll()
            self?.remove(at: index)
        }
        if TabsController.shouldClose([tabs], in: tabs.hostWindow, what: T("the project", "o projeto"), then: close) { close() }
    }

    private func remove(at index: Int) {
        guard projects.count > 1, projects.indices.contains(index) else { return }
        let wasActive = index == activeIndex
        projects[index].tabs.setShown(false)
        projects.remove(at: index)
        if wasActive {
            activeIndex = -1
            select(max(index - 1, 0))
        } else if index < activeIndex {
            activeIndex -= 1
        }
        onChange?()
        scheduleSave()
    }

    /// Quitting or closing the window: one question for every project.
    public func shouldCloseAll(then close: @escaping @MainActor () -> Void,
                               cancelled: @escaping @MainActor () -> Void = {}) -> Bool {
        TabsController.shouldClose(projects.map(\.tabs), in: active?.hostWindow, then: close, cancelled: cancelled)
    }

    /// The window closed (after shouldCloseAll): saves, then ends every project's shells. With
    /// other windows open the app goes on, and the shells of a closed window kept running
    /// (docs/spec/workspace.md).
    public func closeAll() {
        saveNow()
        closed = true
        projects.forEach { $0.tabs.closeAll(keepingSessions: $0.tabs.keepsSessions) }
    }

    // MARK: Saving

    public var saved: SavedProjects {
        SavedProjects(projects: projects.map { .init(name: $0.name, folder: $0.folder, tabs: $0.tabs.snapshot(), color: $0.color) },
                      active: max(activeIndex, 0), folder: workspaceFolder?())
    }

    /// What was saved last time, read before start() (the workspace folder).
    public var savedFile: SavedProjects? {
        fileURL.flatMap(ProjectsFile.load(from:))
    }

    /// Something the projects save changed outside the tabs (the folder).
    public func scheduleSave() {
        guard !restoring, !closed, !savePending else { return }
        savePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay) { [weak self] in
            guard let self, self.savePending else { return }
            self.saveNow()
        }
    }

    /// Writes now (quitting, closing the window).
    public func saveNow() {
        savePending = false
        guard !restoring, !closed, !projects.isEmpty, let fileURL else { return }
        try? ProjectsFile.save(saved, to: fileURL)
    }
}
