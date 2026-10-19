import AppKit
import Explorer
import SourceControl

/// The explorer follows the terminal (docs/spec/workspace.md): when the
/// focused terminal changes folder, the tree goes to that folder's project,
/// the top of its git repository, or the folder itself outside one. The
/// owner typed `cd` and the tree stayed on the home folder (2026-10-19).
/// The repository's top keeps `cd src` inside a project from re-rooting the
/// tree at every step. explorer.followTerminal in settings.json turns it off.
extension AppDelegate {
    func terminalFolderMoved(_ folder: String?) {
        guard followTerminal, let folder, folder != lastTerminalFolder else { return }
        lastTerminalFolder = folder
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
