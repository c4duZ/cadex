import AppKit
import CommandPalette

/// The commands that change the workspace root (docs/spec/workspace.md).
public enum WorkspaceCommands {
    /// `terminalFolder` is the focused terminal's folder, from the tabs; the
    /// explorer does not see terminals.
    @MainActor
    public static func all(_ folder: WorkspaceFolder, window: @escaping @MainActor () -> NSWindow?,
                           terminalFolder: @escaping @MainActor () -> String?) -> [Command] {
        [
            Command(id: "workspace.open-folder", title: "Abrir pasta…", keywords: ["open folder", "workspace", "projeto"],
                    category: .file, defaultShortcut: "cmd+o",
                    action: .run { folder.chooseFolder(in: window()) }),
            Command(id: "workspace.use-terminal-folder", title: "Usar a pasta do terminal",
                    keywords: ["workspace", "cwd", "diretório", "seguir"], category: .file,
                    action: .run { if let path = terminalFolder() { folder.open(path) } },
                    unavailableReason: { terminalFolder() == nil ? "Nenhum terminal com pasta conhecida" : nil }),
        ]
    }
}
