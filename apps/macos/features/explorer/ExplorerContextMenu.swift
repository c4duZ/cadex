import AppKit
import Icons
import Menus

/// The tree's right-click menu (docs/spec/explorer.md): what applies to
/// the clicked kind of row, without what cannot run now. Folders start
/// with the terminal; files with the ways to open them.
extension ExplorerCommands {
    /// In order; nil is a separator. A file has no terminal or Finder
    /// opening and a folder no file opening: an item that cannot apply
    /// to the row is not shown at all (owner, 2026-10-20).
    static func contextMenu(forFolders: Bool) -> [String?] {
        let opening: [String?] = forFolders
            ? ["explorer.open-in-terminal", "explorer.open-in-finder"]
            : ["explorer.open", "explorer.open-beside", "explorer.open-in-tab"]
        return opening + [nil, "explorer.new-file", "explorer.new-folder", nil, "explorer.rename", "explorer.copy-files",
                          "explorer.paste-files", "explorer.trash", nil, "explorer.copy-path",
                          "explorer.copy-relative-path", "explorer.reveal"]
    }

    /// Each item's icon and, for the tree's own keys, the key.
    static let menuLooks: [String: (Icon, String?)] = [
        "explorer.open": (.file, "↩"),
        "explorer.open-beside": (.squareSplitHorizontal, nil),
        "explorer.open-in-tab": (.plus, nil),
        "explorer.open-in-terminal": (.terminalWindow, nil),
        "explorer.new-file": (.filePlus, nil),
        "explorer.new-folder": (.folderPlus, nil),
        "explorer.rename": (.pencilSimple, "F2"),
        "explorer.copy-files": (.copy, "⌘C"),
        "explorer.paste-files": (.clipboardText, "⌘V"),
        "explorer.trash": (.trash, "⌘⌫"),
        "explorer.copy-path": (.path, nil),
        "explorer.copy-relative-path": (.link, nil),
        "explorer.open-in-finder": (.folderOpen, nil),
        "explorer.reveal": (.arrowSquareOut, nil),
    ]
}

extension ExplorerController {
    /// The menu for the current selection; nothing selected (a click
    /// below the rows) is the workspace folder.
    func contextEntries() -> [MenuEntry] {
        let forFolders = selectedNodes.allSatisfy(\.isFolder)
        return ExplorerCommands.contextMenu(forFolders: forFolders).compactMap { id in
            guard let id else { return .separator }
            guard unavailableReason(id) == nil else { return nil }
            let look = ExplorerCommands.menuLooks[id]
            return MenuEntry(ExplorerCommands.title(id), icon: look?.0, shortcut: look?.1) { [weak self] in
                _ = self?.run(id)
            }
        }
    }
}
