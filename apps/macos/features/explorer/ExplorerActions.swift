import AppKit
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
            return selection.isEmpty ? "Nenhum arquivo selecionado" : nil
        case "explorer.rename":
            return selection.count == 1 ? nil : "Selecione um arquivo"
        case "explorer.paste-files":
            return Self.pasteboardFiles().isEmpty ? "Nenhum arquivo copiado" : nil
        case "explorer.open-in-terminal":
            return openInTerminal == nil ? "Nenhum terminal" : nil
        default:
            return nil
        }
    }

    /// Enter: folders open and close, files open in the system's app until
    /// the viewers exist (plan 5). A link pointing outside does not open.
    func openSelection() {
        for node in selectedNodes {
            if node.isFolder {
                outline.isItemExpanded(node) ? outline.collapseItem(node) : outline.expandItem(node)
            } else if cadex_workspace_is_authorized(node.path) {
                if let openFile { openFile(node.path) } else { NSWorkspace.shared.open(URL(fileURLWithPath: node.path)) }
            } else {
                showMessage("Aponta para fora da pasta aberta")
            }
        }
    }

    func newFile() { create(base: "sem título", folder: false) }
    func newFolder() { create(base: "pasta sem título", folder: true) }

    /// Creates under the target folder with a free name, then renames it in
    /// place with the name selected.
    private func create(base: String, folder: Bool) {
        let parent = targetFolder()
        if !parent.isLoaded { parent.load() }
        if parent !== root { outline.expandItem(parent) }
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
        let row = outline.row(forItem: node)
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: true) as? ExplorerCell,
              let field = cell.textField else { return }
        renaming = node
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
        alert.messageText = "Mover \(nodes.count) itens para a Lixeira?"
        alert.addButton(withTitle: "Mover para a Lixeira")
        alert.addButton(withTitle: "Cancelar").keyEquivalent = "\u{1b}"
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
        let folder = target.isFolder ? target : ((outline.parent(forItem: target) as? FileNode) ?? root)
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
        let parents = nodes.map { (outline.parent(forItem: $0) as? FileNode) ?? root }
        var seen = Set<ObjectIdentifier>()
        for parent in parents where seen.insert(ObjectIdentifier(parent)).inserted { reload(parent) }
    }

    static func pasteboardFiles() -> [String] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []).map(\.path)
    }
}
