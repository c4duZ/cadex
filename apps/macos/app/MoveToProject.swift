import AppKit
import CommandPalette
import Strings
import Terminal

/// A terminal that went into another open project's folder (`cd ../Bea`) stays in the project it
/// was opened in, and says so: "Move to Bea" at its foot; the click runs project.move-terminal, which
/// moves the tab there with its shell (the owner, 2026-11-20: an offer, not a move on its own, so a
/// look into another folder never moves the tab). A terminal with no project (the home folder) gets
/// the same offer.
extension WindowSession {
    func moveCommands() -> [Command] {
        [Command(id: "project.move-terminal", title: T("Move Terminal to Its Folder's Project", "Mover o terminal para o projeto da pasta"),
                 keywords: ["move", "project", "terminal", "mover", "projeto"], category: .tabs,
                 action: .run { [weak self] in self?.moveTerminalToProject() },
                 unavailableReason: { [weak self] in
                     self?.projectOfFocusedFolder() == nil ? T("The terminal is in its own project", "O terminal está no próprio projeto") : nil
                 })]
    }

    /// The offer on the focused terminal, after each `cd` (FolderFollow).
    func refreshMoveOffer() {
        guard let terminal = tabs?.activeTerminal else { return }
        guard let target = projectOfFocusedFolder() else { return terminal.offerMove(to: nil) }
        terminal.offerMove(to: target.name) { [weak self] in _ = self?.commands.run("project.move-terminal") }
    }

    /// The open project the focused terminal's folder belongs to, when it is not the terminal's own.
    func projectOfFocusedFolder() -> (name: String, index: Int)? {
        guard let projects, let folder = tabs?.activeTerminal?.currentDirectory else { return nil }
        let own = projects.activeIndex
        let homes = projects.projects.indices.filter { i in
            let root = projects.projects[i].folder
            return !Self.isLoose(root) && Self.folder(folder, isIn: root)
        }
        // The deepest project holding the folder (a project inside another's folder).
        guard let best = homes.max(by: { projects.projects[$0].folder.count < projects.projects[$1].folder.count }), best != own else { return nil }
        // Still inside its own project (a project nested in this one's folder): it stays.
        if own >= 0, own < projects.projects.count, !Self.isLoose(projects.projects[own].folder),
           Self.folder(folder, isIn: projects.projects[own].folder),
           projects.projects[own].folder.count >= projects.projects[best].folder.count { return nil }
        return (projects.projects[best].name, best)
    }

    /// project.move-terminal: the focused terminal leaves its tab (the tab goes when it was alone)
    /// for a new tab in the project of its folder, which shows.
    func moveTerminalToProject() {
        guard let projects, let target = projectOfFocusedFolder(), let terminal = tabs?.takeFocusedTerminal() else { return NSSound.beep() }
        terminal.offerMove(to: nil)
        projects.projects[target.index].tabs.adopt(terminal)
        projects.select(target.index)
        lastTerminalFolder = nil
        terminalFolderMoved(terminal.currentDirectory)
        drawRail()
    }
}
