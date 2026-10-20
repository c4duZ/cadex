import AppKit
import Strings

/// A view that can show a find bar (the terminal, the editor): edit.find
/// goes to whichever has focus.
@objc public protocol FindTarget {
    func showFind(_ sender: Any?)
}

/// Commands every Mac app has. Copy, paste and the rest go down the
/// responder chain, so they act on the terminal or on a text field,
/// whichever has focus.
public enum StandardCommands {
    @MainActor
    public static var all: [Command] {
        [
            Command(id: "app.quit", title: T("Quit Cadex", "Sair do Cadex"), keywords: ["quit", "fechar app", "exit"], category: .app,
                    defaultShortcut: "cmd+q", action: .run { NSApp.terminate(nil) }),
            Command(id: "app.hide", title: T("Hide Cadex", "Ocultar o Cadex"), keywords: ["hide"], category: .app,
                    defaultShortcut: "cmd+h", action: .run { NSApp.hide(nil) }),
            .responder("edit.undo", T("Undo", "Desfazer"), keywords: ["undo"], category: .edit, shortcut: "cmd+z",
                       selector: Selector(("undo:")), reason: T("Nothing to undo here", "Nada para desfazer aqui")),
            .responder("edit.redo", T("Redo", "Refazer"), keywords: ["redo"], category: .edit, shortcut: "cmd+shift+z",
                       selector: Selector(("redo:")), reason: T("Nothing to redo here", "Nada para refazer aqui")),
            .responder("edit.cut", T("Cut", "Recortar"), keywords: ["cut"], category: .edit, shortcut: "cmd+x",
                       selector: #selector(NSText.cut(_:)), reason: T("Nothing to cut here", "Nada para recortar aqui")),
            .responder("edit.copy", T("Copy", "Copiar"), keywords: ["copy", "seleção"], category: .edit, shortcut: "cmd+c",
                       selector: #selector(NSText.copy(_:)), reason: T("Nothing to copy here", "Nada para copiar aqui")),
            .responder("edit.paste", T("Paste", "Colar"), keywords: ["paste"], category: .edit, shortcut: "cmd+v",
                       selector: #selector(NSText.paste(_:)), reason: T("Nothing here accepts a paste", "Nada aceita colagem aqui")),
            .responder("edit.find", T("Find", "Buscar"), keywords: ["find", "procurar", "pesquisar"], category: .edit,
                       shortcut: "cmd+f", selector: #selector(FindTarget.showFind(_:)), reason: T("Nothing to search here", "Nada para buscar aqui")),
            .responder("edit.select-all", T("Select All", "Selecionar tudo"), keywords: ["select all"], category: .edit,
                       shortcut: "cmd+a", selector: #selector(NSText.selectAll(_:)), reason: T("Nothing to select here", "Nada para selecionar aqui")),
        ]
    }
}
