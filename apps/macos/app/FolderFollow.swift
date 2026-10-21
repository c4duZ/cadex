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
        guard let folder, folder != lastTerminalFolder else { return }
        lastTerminalFolder = folder
        // ⌘P keeps the files nearest the terminal when the workspace is too
        // big to index whole (docs/spec/search.md).
        search?.setFocus(folder)
        guard followTerminal else { return }
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
}
