import AppKit
import Tabs

/// Entry point of the spaces feature (docs/spec/spaces.md): named sets of
/// tabs, one shown in the window at a time, saved after every change and
/// restored at launch. Each space is a TabsController; the hidden ones keep
/// their shells running.
@MainActor
public final class SpacesController {
    public final class Space {
        public var name: String
        public let tabs: TabsController

        init(name: String, tabs: TabsController) {
            self.name = name
            self.tabs = tabs
        }
    }

    public private(set) var spaces: [Space] = []
    public private(set) var activeIndex = 0
    public var active: TabsController? { spaces.indices.contains(activeIndex) ? spaces[activeIndex].tabs : nil }
    public var activeName: String { spaces.indices.contains(activeIndex) ? spaces[activeIndex].name : "" }
    /// The window shows these tabs now: the app swaps the view and the bar.
    public var onSwitch: ((TabsController) -> Void)?
    /// A name or the active space changed (the title bar's label).
    public var onChange: (() -> Void)?
    /// The workspace folder to save with the spaces.
    public var workspaceFolder: (() -> String?)?
    private let makeTabs: () -> TabsController
    /// Nil for a passing window (⌘N): only the main window is saved
    /// (docs/spec/workspace.md).
    private let fileURL: URL?
    private var savePending = false
    /// While restoring, the half-built state must not overwrite the file.
    private var restoring = false
    /// After the window closed nothing is saved: the shells ending must not
    /// overwrite what the window had.
    private var closed = false
    /// How long after a change the file is written: changes come in bursts
    /// (a split retitles, refocuses and resizes), and a crash loses at most this.
    static let saveDelay = 0.5

    /// `makeTabs` makes a TabsController wired to the window (status bar,
    /// preview offers); the spaces add the saving and the empty-space rule.
    public init(fileURL: URL? = SpacesFile.defaultURL, makeTabs: @escaping () -> TabsController) {
        self.fileURL = fileURL
        self.makeTabs = makeTabs
    }

    /// The saved spaces, or one with a terminal in `folder`. `makeDocument`
    /// makes a saved document from its identity (nil when it is gone).
    public func start(folder: String, makeDocument: (String) -> TabDocument?) {
        restoring = true
        defer { restoring = false }
        let saved = fileURL.flatMap(SpacesFile.load(from:))
        for space in saved?.spaces ?? [] {
            let tabs = add(name: space.name)
            activeIndex = spaces.count - 1
            tabs.restore(space.tabs, makeDocument: makeDocument)
            if tabs.count == 0 { tabs.newTab(cwd: folder) }
        }
        if spaces.isEmpty {
            add(name: "Space 1").newTab(cwd: folder)
        }
        let index = min(max(saved?.active ?? 0, 0), spaces.count - 1)
        spaces.forEach { $0.tabs.isShown = false }
        activeIndex = -1
        select(index)
    }

    @discardableResult
    private func add(name: String) -> TabsController {
        let tabs = makeTabs()
        let space = Space(name: name, tabs: tabs)
        tabs.isShown = false
        tabs.onStateChange = { [weak self] in self?.scheduleSave() }
        tabs.onEmpty = { [weak self, weak space] in
            guard let self, let space else { return }
            self.emptied(space)
        }
        spaces.append(space)
        return tabs
    }

    /// The last tab of a space closed: the space goes, or the window when
    /// it was the only one.
    private func emptied(_ space: Space) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0 === space }) else {
            saveNow()
            space.tabs.hostWindow?.close()
            return
        }
        remove(at: index)
    }

    // MARK: Switching

    public func select(_ index: Int) {
        guard spaces.indices.contains(index), index != activeIndex else { return }
        if spaces.indices.contains(activeIndex) { spaces[activeIndex].tabs.setShown(false) }
        activeIndex = index
        let tabs = spaces[index].tabs
        onSwitch?(tabs)
        tabs.setShown(true)
        onChange?()
        scheduleSave()
    }

    /// ⌃⌘→ and ⌃⌘←, wrapping.
    public func selectNext(step: Int) {
        guard spaces.count > 1 else { return }
        select((activeIndex + step + spaces.count) % spaces.count)
    }

    /// "Novo space": a terminal in `folder`, shown.
    public func newSpace(folder: String) {
        let names = Set(spaces.map(\.name))
        let n = ((spaces.count + 1)...).first { !names.contains("Space \($0)") }!
        add(name: "Space \(n)").newTab(cwd: folder)
        select(spaces.count - 1)
    }

    public func rename(at index: Int, to name: String) {
        guard spaces.indices.contains(index) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        spaces[index].name = trimmed
        onChange?()
        scheduleSave()
    }

    /// "Fechar space": asks over running programs and unsaved files, then
    /// shows the space before it. The last space does not close.
    public func closeActive() {
        guard spaces.count > 1, let tabs = active else { return }
        let index = activeIndex
        let close: @MainActor () -> Void = { [weak self] in
            tabs.closeAll()
            self?.remove(at: index)
        }
        if TabsController.shouldClose([tabs], in: tabs.hostWindow, what: "o space", then: close) { close() }
    }

    private func remove(at index: Int) {
        guard spaces.count > 1, spaces.indices.contains(index) else { return }
        let wasActive = index == activeIndex
        spaces[index].tabs.setShown(false)
        spaces.remove(at: index)
        if wasActive {
            activeIndex = -1
            select(max(index - 1, 0))
        } else if index < activeIndex {
            activeIndex -= 1
        }
        onChange?()
        scheduleSave()
    }

    /// Quitting or closing the window: one question for every space.
    public func shouldCloseAll(then close: @escaping @MainActor () -> Void,
                               cancelled: @escaping @MainActor () -> Void = {}) -> Bool {
        TabsController.shouldClose(spaces.map(\.tabs), in: active?.hostWindow, then: close, cancelled: cancelled)
    }

    /// The window closed (after shouldCloseAll): saves, then ends every
    /// space's shells. With other windows open the app goes on, and the
    /// shells of a closed window kept running (docs/spec/workspace.md).
    public func closeAll() {
        saveNow()
        closed = true
        spaces.forEach { $0.tabs.closeAll() }
    }

    // MARK: Saving

    public var saved: SavedSpaces {
        SavedSpaces(spaces: spaces.map { .init(name: $0.name, tabs: $0.tabs.snapshot()) }, active: max(activeIndex, 0),
                    folder: workspaceFolder?())
    }

    /// What was saved last time, read before start() (the workspace folder).
    public var savedFile: SavedSpaces? {
        fileURL.flatMap(SpacesFile.load(from:))
    }

    /// Something the spaces save changed outside the tabs (the folder).
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
        guard !restoring, !closed, !spaces.isEmpty, let fileURL else { return }
        try? SpacesFile.save(saved, to: fileURL)
    }
}
