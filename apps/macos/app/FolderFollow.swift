import AppKit
import Explorer
import SourceControl

/// The explorer follows the terminal (docs/spec/workspace.md): when the
/// focused terminal changes folder, the tree goes to the top of that
/// folder's git repository, or to the folder itself outside one. The owner
/// typed `cd` and the tree stayed on the home folder (2026-10-19). Following
/// only into repositories (2026-10-20) left folders without .git out of the
/// tree, and the owner wants them (2026-10-21); the indexes stay light even
/// on the home folder since then (lazy, a budget nearest the terminal).
/// The repository's top keeps `cd src` inside a project from re-rooting the
/// tree at every step. explorer.followTerminal in settings.json turns it off.
extension WindowSession {
    func terminalFolderMoved(_ folder: String?) {
        refreshMoveOffer()
        guard let folder, folder != lastTerminalFolder else { return }
        lastTerminalFolder = folder
        // ⌘P keeps the files nearest the terminal when the workspace is too
        // big to index whole (docs/spec/search.md).
        search?.setFocus(folder)
        guard followTerminal else { return }
        showFilesWhereTerminalIs()
        // Inside the chosen project (or the task the terminal is in), Files and Changes show it, so a
        // `cd src` does not move the root (ADR 0038). A `cd` out of it is followed: the tree stayed on
        // the project with the terminal elsewhere (the owner, 2026-11-20: "ele deveria mudar").
        if let anchor = projectAnchor(for: folder), Self.folder(folder, isIn: anchor) {
            if anchor != self.folder.root, WorkspaceFolder.allow(anchor) != nil { self.folder.open(anchor) }
            return
        }
        // Outside the project, or no project: the folder's repository, else the folder.
        // git runs only inside authorized folders; the user went there.
        guard WorkspaceFolder.allow(folder) != nil else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let project = SourceControlController.repositoryRoot(containing: folder) ?? folder
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // A newer `cd` arrived meanwhile: that one decides.
                    guard let self, self.lastTerminalFolder == folder, project != self.folder.root else { return }
                    self.folder.open(project)
                }
            }
        }
    }

    /// The folder Files and Changes show for a terminal in `folder`: its task's worktree, else the
    /// chosen project's folder; nil without a project.
    func projectAnchor(for folder: String?) -> String? {
        if let task = taskFolder(containing: folder) { return task }
        return projects?.activeFolder
    }

    /// Whether `folder` is `root` or under it.
    static func folder(_ folder: String, isIn root: String) -> Bool {
        folder == root || folder.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// A project came into the window: the column shows it (the focused terminal's task, if any), or
    /// where the focused terminal is when that is outside the project.
    func followProject() {
        let here = tabs?.activeTerminal?.currentDirectory
        guard followTerminal, let anchor = projectAnchor(for: here) else { return }
        if let here, !Self.folder(here, isIn: anchor) {
            lastTerminalFolder = nil
            return terminalFolderMoved(here)
        }
        if anchor != folder.root, WorkspaceFolder.allow(anchor) != nil { folder.open(anchor) }
    }

    /// Files shows the focused terminal's folder when it is under the root: a terminal in `app/` shows
    /// `app/`, not the project's top (the owner, 2026-11-24: "se o terminal está em uma sub, a sub deve
    /// aparecer"). Only the tree: git, the search and the title stay on the project.
    func showFilesWhereTerminalIs() {
        let root = folder.root
        var shown = root
        if followTerminal, let here = tabs?.activeTerminal?.currentDirectory, Self.folder(here, isIn: root) {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: here, isDirectory: &isFolder), isFolder.boolValue { shown = here }
        }
        guard let explorer, explorer.rootPath != shown else { return showPanelFolder(shown) }
        explorer.setRoot(shown)
        showPanelFolder(shown)
    }
}
