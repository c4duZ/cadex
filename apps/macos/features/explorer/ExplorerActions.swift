import AppKit
import Strings
import CCadex

/// What the explorer commands do (ExplorerCommands registers them).
extension ExplorerController {
    /// Nil when the command can run now, otherwise why not. Shared by the
    /// commands and the context menu.
    func unavailableReason(_ id: String) -> String? {
        let selection = selectedNodes
        switch id {
        case "explorer.open", "explorer.trash", "explorer.copy-files", "explorer.reveal", "explorer.copy-path",
             "explorer.copy-relative-path":
            return selection.isEmpty ? T("No file selected", "Nenhum arquivo selecionado") : nil
        case "explorer.open-beside", "explorer.open-in-tab":
            if openFileAs == nil { return T("Nowhere to open it", "Nada onde abrir") }
            return selection.contains { !$0.isFolder } ? nil : T("No file selected", "Nenhum arquivo selecionado")
        case "explorer.rename":
            return selection.count == 1 ? nil : T("Select one file", "Selecione um arquivo")
        case "explorer.paste-files":
            return Self.pasteboardFiles().isEmpty ? T("No files copied", "Nenhum arquivo copiado") : nil
        case "explorer.open-in-terminal":
            return openInTerminal == nil ? T("No terminal", "Nenhum terminal") : nil
        case "explorer.open-in-finder":
            return selection.isEmpty || selection.contains(where: \.isFolder) ? nil : T("No folder selected", "Nenhuma pasta selecionada")
        default:
            return nil
        }
    }

    /// Enter: folders open and close, files open where the settings say
    /// (openFile), or in the system's app without it. `beside` chooses on
    /// the spot ("Abrir ao lado", "Abrir em nova aba"), folders untouched.
    /// A link pointing outside does not open.
    func openSelection(beside: Bool? = nil) {
        for node in selectedNodes {
            if node.isFolder {
                guard beside == nil else { continue }
                let row = item(of: node)
                outline.isItemExpanded(row) ? outline.collapseItem(row) : outline.expandItem(row)
            } else if cadex_workspace_is_authorized(node.path) {
                if let beside, let openFileAs { openFileAs(node.path, beside) }
                else if let openFile { openFile(node.path) }
                else { NSWorkspace.shared.open(URL(fileURLWithPath: node.path)) }
            } else {
                showMessage(T("Points outside the open folder", "Aponta para fora da pasta aberta"))
            }
        }
    }

    func newFile() { create(base: T("untitled", "sem título"), folder: false) }
    func newFolder() { create(base: T("untitled folder", "pasta sem título"), folder: true) }

    /// Creates under the target folder with a free name, then renames it in
    /// place with the name selected.
    private func create(base: String, folder: Bool) {
        let parent = targetFolder()
        if !parent.isLoaded { parent.load() }
        if parent !== root { outline.expandItem(item(of: parent)) }
        for n in 1...100 {
            let path = FileNode.join(parent.path, n == 1 ? base : "\(base) \(n)")
            do {
                try folder ? ExplorerFiles.createDirectory(path) : ExplorerFiles.createFile(path)
            } catch where error.status == CADEX_ALREADY_EXISTS {
                continue
            } catch {
                return showMessage(error.message)
            }
            reload(parent)
            select(path: path)
            beginRename()
            return
        }
    }

    /// F2: the name becomes editable; the part before the extension is
    /// selected, as in the Finder.
    func beginRename() {
        guard let node = selectedNodes.first, selectedNodes.count == 1 else { return }
        let row = self.row(of: node)
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? ExplorerCell,
              let field = cell.textField else { return }
        renaming = node
        // A compact row shows "a/b/c"; only the last folder is renamed.
        field.stringValue = node.name
        field.isEditable = true
        field.window?.makeFirstResponder(field)
        let stem = node.isFolder ? node.name : (node.name as NSString).deletingPathExtension
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem.isEmpty ? node.name : stem).utf16.count)
    }

    func trashSelection() {
        let nodes = selectedNodes
        guard !nodes.isEmpty else { return }
        let go = { [weak self] in
            guard let self else { return }
            for node in nodes {
                do throws(ExplorerError) { try ExplorerFiles.trash(node.path) } catch { self.showMessage(error.message) }
            }
            self.reloadParents(of: nodes)
        }
        guard nodes.count > 1, let window = outline.window else { return go() }
        let alert = NSAlert()
        alert.messageText = T("Move \(nodes.count) items to the Trash?", "Mover \(nodes.count) itens para a Lixeira?")
        alert.addButton(withTitle: T("Move to Trash", "Mover para a Lixeira"))
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { MainActor.assumeIsolated { go() } }
        }
    }

    func copySelection() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(selectedNodes.map { URL(fileURLWithPath: $0.path) as NSURL })
    }

    func pasteFiles() {
        let target = targetFolder()
        var last: String?
        for path in Self.pasteboardFiles() {
            do { last = try ExplorerFiles.copy(path, into: target.path) } catch { showMessage(error.message) }
        }
        if !target.isLoaded { target.load() }
        reload(target)
        if let last { select(path: last) }
    }

    /// Moves dropped rows into `target` (a folder, or a file's folder).
    func move(_ paths: [String], into target: FileNode) {
        let folder = target.isFolder ? tail(of: target) : parentFolder(of: target)
        var last: String?
        for path in paths {
            do { last = try ExplorerFiles.move(path, into: folder.path) } catch { showMessage(error.message) }
        }
        reloadAll()
        if let last { select(path: last) }
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting(selectedNodes.map { URL(fileURLWithPath: $0.path) })
    }

    /// The selected folders in Finder windows; nothing selected, the
    /// workspace folder.
    func openFoldersInFinder() {
        let folders = selectedNodes.isEmpty ? [root] : selectedNodes.filter(\.isFolder)
        folders.forEach { NSWorkspace.shared.open(URL(fileURLWithPath: $0.path)) }
    }

    func copyPaths(relative: Bool) {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let paths = selectedNodes.map { relative && $0.path.hasPrefix(prefix) ? String($0.path.dropFirst(prefix.count)) : $0.path }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    /// The selected folder, or the selected file's folder, or the root.
    func openSelectionInTerminal() {
        openInTerminal?(targetFolder().path)
    }

    func toggleHidden() {
        showHidden.toggle()
        onShowHiddenChange?(showHidden)
    }

    func collapseAll() {
        outline.collapseItem(nil, collapseChildren: true)
    }

    /// ⇧⌘E: the tree takes the keyboard, with a row selected.
    func focus() {
        revealSidebar?()
        outline.window?.makeFirstResponder(outline)
        if outline.selectedRow < 0, outline.numberOfRows > 0 { outline.selectRowIndexes([0], byExtendingSelection: false) }
    }

    private func reloadParents(of nodes: [FileNode]) {
        let parents = nodes.map { parentFolder(of: $0) }
        var seen = Set<ObjectIdentifier>()
        for parent in parents where seen.insert(ObjectIdentifier(parent)).inserted { reload(parent) }
    }

    static func pasteboardFiles() -> [String] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []).map(\.path)
    }
}
