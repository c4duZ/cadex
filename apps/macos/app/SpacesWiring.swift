import AppKit
import CommandPalette
import Explorer
import GitHistory
import Spaces
import Tabs

/// The spaces in the window (docs/spec/spaces.md): each space's tabs are
/// made here, wired like the window's (status bar, preview offers), and
/// the saved documents are made again by the FileOpener.
extension WindowSession {
    /// Made with the commands, before the window, so the palette and the
    /// shortcuts know space.*; the tabs are made later, in startSpaces.
    func makeSpaces(palette: CommandPaletteController) {
        let spaces = SpacesController(fileURL: isMain ? SpacesFile.defaultURL : nil) { [unowned self] in self.makeTabs() }
        spaces.onSwitch = { [weak self] tabs in self?.workspace?.show(tabs) }
        spaces.onChange = { [weak self, weak spaces] in
            self?.workspace?.titleBar.setSpace(name: spaces?.activeName ?? "", count: spaces?.spaces.count ?? 1)
        }
        commands.register(SpacesCommands.all(spaces, palette: palette) { [weak self] in
            self?.folder.root ?? NSHomeDirectory()
        })
        self.spaces = spaces
    }

    private func makeTabs() -> TabsController {
        let tabs = TabsController(window: window)
        tabs.onOpenPreview = { [weak self] url in self?.openPreview(url) }
        if let bar = workspace?.statusBar { connectStatusBar(bar, to: tabs) }
        return tabs
    }

    /// The saved spaces come back, or one with a terminal in the workspace.
    /// Without a folder on the command line, the last workspace folder too.
    func startSpaces() {
        guard let spaces else { return }
        let saved = spaces.savedFile
        if !folder.launchedWithFolder, let path = saved?.folder, FileManager.default.fileExists(atPath: path) {
            folder.open(path)
        }
        spaces.workspaceFolder = { [weak self] in self?.folder.root }
        spaces.start(folder: folder.root) { [weak self] identity in self?.opener?.makeDocument(identity: identity) }
        // Opened on a folder: the old tabs come back and the folder gets its
        // own terminal in the shown space (docs/spec/spaces.md), unless one
        // is already there: opening the same folder again stacked tabs.
        if folder.launchedWithFolder, saved != nil, let tabs, !hasTerminal(in: folder.root, tabs) {
            tabs.newTab(cwd: folder.root)
        }
    }

    private func hasTerminal(in folder: String, _ tabs: TabsController) -> Bool {
        tabs.snapshot().items.contains { item in
            if case let .terminal(_, layout, _) = item { return layout.folders.contains(folder) }
            return false
        }
    }
}
