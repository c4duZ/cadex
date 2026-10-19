import AppKit

/// Commands every Mac app has. Copy, paste and the rest go down the
/// responder chain, so they act on the terminal or on a text field,
/// whichever has focus.
public enum StandardCommands {
    @MainActor
    public static var all: [Command] {
        [
            Command(id: "app.quit", title: "Sair do Cadex", keywords: ["quit", "fechar app"], category: .app,
                    defaultShortcut: "cmd+q", action: .run { NSApp.terminate(nil) }),
            Command(id: "app.hide", title: "Ocultar o Cadex", keywords: ["hide"], category: .app,
                    defaultShortcut: "cmd+h", action: .run { NSApp.hide(nil) }),
            .responder("edit.undo", "Desfazer", keywords: ["undo"], category: .edit, shortcut: "cmd+z",
                       selector: Selector(("undo:")), reason: "Nada para desfazer aqui"),
            .responder("edit.redo", "Refazer", keywords: ["redo"], category: .edit, shortcut: "cmd+shift+z",
                       selector: Selector(("redo:")), reason: "Nada para refazer aqui"),
            .responder("edit.cut", "Recortar", keywords: ["cut"], category: .edit, shortcut: "cmd+x",
                       selector: #selector(NSText.cut(_:)), reason: "Nada para recortar aqui"),
            .responder("edit.copy", "Copiar", keywords: ["copy", "seleção"], category: .edit, shortcut: "cmd+c",
                       selector: #selector(NSText.copy(_:)), reason: "Nada para copiar aqui"),
            .responder("edit.paste", "Colar", keywords: ["paste"], category: .edit, shortcut: "cmd+v",
                       selector: #selector(NSText.paste(_:)), reason: "Nada aceita colagem aqui"),
            .responder("edit.select-all", "Selecionar tudo", keywords: ["select all"], category: .edit,
                       shortcut: "cmd+a", selector: #selector(NSText.selectAll(_:)), reason: "Nada para selecionar aqui"),
        ]
    }
}
