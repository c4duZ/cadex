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
        /// The picture's file in `imagesFolder`, and an emoji for when there is none (plan 36 B).
        public var image: String?
        public var emoji: String?
        /// Kept in the rail with no terminal open (plan 36): its last tab closing leaves it there.
        public var pinned = false

        init(name: String, folder: String, tabs: TabsController) {
            self.name = name
            self.folder = folder
            self.tabs = tabs
        }
    }

    public private(set) var projects: [Project] = []
    public internal(set) var activeIndex = 0
    public var active: TabsController? { projects.indices.contains(activeIndex) ? projects[activeIndex].tabs : nil }
    public var activeName: String { projects.indices.contains(activeIndex) ? projects[activeIndex].name : "" }
    public var activeFolder: String? { projects.indices.contains(activeIndex) ? projects[activeIndex].folder : nil }
    /// The window shows these tabs now: the app swaps the view and the bar.
    public var onSwitch: ((TabsController) -> Void)?
    /// No project is open any more (the last one closed, or none at launch): the app shows the
    /// home screen (plan 29).
    public var onNone: (() -> Void)?
    /// The projects used lately, open or closed, the latest first (the home screen's list).
    public private(set) var recent: [SavedProjects.Recent] = []
    static let recentLimit = 8
    /// Makes a saved document again (start's), for a recent project's tabs.
    private var makeDocument: (String) -> TabDocument? = { _ in nil }
    /// A name or the active project changed (the title bar's label).
    public var onChange: (() -> Void)?
    /// Any project's tabs changed (opened, closed, moved, a folder): the work's tree redraws.
    public var onTabsChange: (() -> Void)?
    /// The workspace folder to save with the projects.
    public var workspaceFolder: (() -> String?)?
    private let makeTabs: () -> TabsController
    /// Nil for a passing window (⌘N): only the main window is saved (docs/spec/workspace.md).
    let fileURL: URL?
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
    /// saved document from its identity (nil when it is gone). `openFolder` false (a launch from
    /// the Dock, plan 29): with nothing saved open, no project, and the app shows the home screen.
    public func start(folder: String, openFolder: Bool = true, makeDocument: @escaping (String) -> TabDocument?) {
        self.makeDocument = makeDocument
        restoring = true
        defer { restoring = false }
        let saved = fileURL.flatMap(ProjectsFile.load(from:))
        recent = saved?.recent ?? []
        for project in saved?.projects ?? [] {
            let tabs = add(name: project.name, folder: project.folder)
            projects[projects.count - 1].color = project.color
            projects[projects.count - 1].image = project.image
            projects[projects.count - 1].emoji = project.emoji
            projects[projects.count - 1].pinned = project.pinned ?? true
            activeIndex = projects.count - 1
            tabs.restore(project.tabs, makeDocument: makeDocument)
            // Saved with no tab: a terminal in its folder (the spec), or the launch folder when gone;
            // a pinned one stays without (plan 36: in the rail, its click opens one).
            if tabs.count == 0, project.pinned != true {
                tabs.newTab(cwd: FileManager.default.fileExists(atPath: project.folder) ? project.folder : folder)
            }
        }
        if projects.isEmpty {
            guard openFolder else {
                activeIndex = -1
                onNone?()
                return
            }
            let root = ProjectsFile.repositoryRoot(folder)
            add(name: Self.name(of: root), folder: root).newTab(cwd: folder)
        }
        var index = min(max(saved?.active ?? 0, 0), projects.count - 1)
        projects.forEach { $0.tabs.isShown = false }
        activeIndex = -1
        // A pinned project without terminals is not shown at start: one with terminals, else the
        // home screen with the rail (plan 36).
        if projects[index].tabs.count == 0 {
            guard let open = projects.firstIndex(where: { $0.tabs.count > 0 }) else { return onNone?() ?? () }
            index = open
        }
        select(index)
    }

    @discardableResult
    private func add(name: String, folder: String) -> TabsController {
        let tabs = makeTabs()
        let project = Project(name: name, folder: folder, tabs: tabs)
        tabs.isShown = false
        tabs.onStateChange = { [weak self] in
            self?.scheduleSave()
            self?.onTabsChange?()
        }
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

    /// The last tab of a project closed: the project goes; the only one leaves the home screen
    /// (plan 29), or closes a passing window. A pinned one stays in the rail (plan 36).
    private func emptied(_ project: Project) {
        if project.pinned, fileURL != nil { return keepEmpty(project) }
        guard projects.count > 1 || fileURL != nil, let index = projects.firstIndex(where: { $0 === project }) else {
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
        noteUsed(projects[index])
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
        // A recent one comes back with the tabs it had when it closed (the home screen's list).
        let recent = self.recent.first { $0.folder == root }
        let tabs = add(name: recent?.name ?? Self.name(of: root), folder: root)
        if let saved = recent?.tabs, root == folder {
            restoring = true
            tabs.restore(saved, makeDocument: makeDocument)
            restoring = false
            projects[projects.count - 1].color = recent?.color
            projects[projects.count - 1].image = recent?.image
            projects[projects.count - 1].emoji = recent?.emoji
        }
        if tabs.count == 0 { tabs.newTab(cwd: folder) }
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
    /// it; the last one leaves the home screen (plan 29), save in a passing window, which keeps it.
    public func closeActive() {
        guard projects.count > 1 || fileURL != nil, let tabs = active else { return }
        let index = activeIndex
        let close: @MainActor () -> Void = { [weak self] in
            // What it had, taken before the shells end (the recent list keeps it).
            let kept = tabs.snapshot()
            tabs.closeAll()
            self?.remove(at: index, tabs: kept)
        }
        if TabsController.shouldClose([tabs], in: tabs.hostWindow, what: T("the project", "o projeto"), then: close) { close() }
    }

    /// The project of `folder` closed, asking as project.close does (the home screen's Clone…
    /// closes the parent folder's project it opened only to clone).
    public func close(folder: String) {
        guard let index = projects.firstIndex(where: { $0.folder == folder }) else { return }
        let tabs = projects[index].tabs
        let close: @MainActor () -> Void = { [weak self, weak tabs] in
            let kept = tabs?.snapshot()
            tabs?.closeAll()
            guard let self, let at = self.projects.firstIndex(where: { $0.folder == folder }) else { return }
            self.remove(at: at, tabs: kept)
        }
        if TabsController.shouldClose([tabs], in: tabs.hostWindow, what: T("the project", "o projeto"), then: close) { close() }
    }

    func remove(at index: Int, tabs kept: TabsSnapshot? = nil) {
        guard projects.indices.contains(index) else { return }
        let wasActive = index == activeIndex
        noteUsed(projects[index], tabs: kept)
        projects[index].tabs.setShown(false)
        projects.remove(at: index)
        if projects.isEmpty {
            activeIndex = -1
            onNone?()
        } else if wasActive {
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
        SavedProjects(projects: projects.map { .init(name: $0.name, folder: $0.folder, tabs: $0.tabs.snapshot(), color: $0.color,
                                                     image: $0.image, emoji: $0.emoji, pinned: $0.pinned) },
                      active: max(activeIndex, 0), folder: workspaceFolder?(), recent: recent)
    }

    /// The project goes to the top of the recent ones.
    /// `tabs`: what it had, when it closes (kept for opening it again).
    private func noteUsed(_ project: Project, tabs: TabsSnapshot? = nil, at date: Date = Date()) {
        recent.removeAll { $0.folder == project.folder }
        recent.insert(.init(name: project.name, folder: project.folder, usedAt: date, tabs: tabs, color: project.color,
                            image: project.image, emoji: project.emoji), at: 0)
        if recent.count > Self.recentLimit { recent.removeLast(recent.count - Self.recentLimit) }
    }

    /// A recent project that is gone (Remove on its row).
    public func forgetRecent(folder: String) {
        recent.removeAll { $0.folder == folder }
        scheduleSave()
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
        guard !restoring, !closed, let fileURL else { return }
        try? ProjectsFile.save(saved, to: fileURL)
    }
}

