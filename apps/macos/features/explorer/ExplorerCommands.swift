import CommandPalette

/// The explorer's commands (ADR 0005). The tree's own keys (Enter, F2,
/// ⌘⌫, ⌘C, ⌘V) run these ids from ExplorerOutline; the app-wide shortcuts
/// here are only the ones the terminal does not need.
public enum ExplorerCommands {
    /// id, title, keywords, default shortcut.
    private static let table: [(String, String, [String], String?)] = [
        ("explorer.focus", "Mostrar os arquivos", ["explorer", "árvore", "focus"], "cmd+shift+e"),
        ("explorer.open", "Abrir arquivo", ["open", "abrir"], nil),
        ("explorer.open-beside", "Abrir ao lado", ["open beside", "split", "painel", "abrir"], nil),
        ("explorer.open-in-tab", "Abrir em nova aba", ["open in tab", "aba", "abrir"], nil),
        ("explorer.new-file", "Novo arquivo", ["new file", "criar"], nil),
        ("explorer.new-folder", "Nova pasta", ["new folder", "criar", "diretório"], nil),
        ("explorer.rename", "Renomear", ["rename", "nome"], nil),
        ("explorer.trash", "Mover para a Lixeira", ["delete", "apagar", "excluir", "trash"], nil),
        ("explorer.copy-files", "Copiar arquivos", ["copy", "copiar"], nil),
        ("explorer.paste-files", "Colar arquivos", ["paste", "colar"], nil),
        ("explorer.reveal", "Revelar no Finder", ["reveal", "finder", "mostrar"], nil),
        ("explorer.open-in-finder", "Abrir no Finder", ["open in finder", "finder", "pasta"], nil),
        ("explorer.copy-path", "Copiar caminho", ["copy path", "caminho"], nil),
        ("explorer.copy-relative-path", "Copiar caminho relativo", ["copy relative path", "caminho"], nil),
        ("explorer.open-in-terminal", "Abrir no terminal", ["cd", "terminal", "pasta"], nil),
        ("explorer.toggle-hidden", "Mostrar ou esconder arquivos ocultos", ["hidden", "ocultos", "dotfiles"], "cmd+shift+."),
        ("explorer.refresh", "Recarregar arquivos", ["refresh", "atualizar"], nil),
        ("explorer.collapse-all", "Recolher todas as pastas", ["collapse", "fechar"], nil),
    ]

    static func title(_ id: String) -> String {
        table.first { $0.0 == id }?.1 ?? id
    }

    @MainActor
    public static func all(_ explorer: ExplorerController) -> [Command] {
        table.map { id, title, keywords, shortcut in
            Command(id: id, title: title, keywords: keywords, category: .file, defaultShortcut: shortcut,
                    action: .run { [weak explorer] in explorer?.perform(id) },
                    unavailableReason: { [weak explorer] in explorer?.unavailableReason(id) })
        }
    }
}

extension ExplorerController {
    func perform(_ id: String) {
        switch id {
        case "explorer.focus": focus()
        case "explorer.open": openSelection()
        case "explorer.open-beside": openSelection(beside: true)
        case "explorer.open-in-tab": openSelection(beside: false)
        case "explorer.new-file": newFile()
        case "explorer.new-folder": newFolder()
        case "explorer.rename": beginRename()
        case "explorer.trash": trashSelection()
        case "explorer.copy-files": copySelection()
        case "explorer.paste-files": pasteFiles()
        case "explorer.reveal": revealInFinder()
        case "explorer.open-in-finder": openFoldersInFinder()
        case "explorer.copy-path": copyPaths(relative: false)
        case "explorer.copy-relative-path": copyPaths(relative: true)
        case "explorer.open-in-terminal": openSelectionInTerminal()
        case "explorer.toggle-hidden": toggleHidden()
        case "explorer.refresh": reloadAll()
        case "explorer.collapse-all": collapseAll()
        default: break
        }
    }
}
