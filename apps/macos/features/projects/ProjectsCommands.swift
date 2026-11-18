import AppKit
import Strings
import CommandPalette
import Icons

/// The projects' commands (ADR 0005; docs/spec/projects.md): project.switch, .new, .rename, .close,
/// .next and .previous (the old space.* ids left in plan 28). `chooseFolder` asks for the folder
/// of a new project (Open Folder).
public enum ProjectsCommands {
    @MainActor
    public static func all(_ projects: ProjectsController, palette: CommandPaletteController,
                           chooseFolder: @escaping @MainActor () -> Void) -> [Command] {
        func needsTwo() -> String? { projects.projects.count > 1 ? nil : T("Only one project open", "Só um projeto aberto") }
        let commands: [(id: String, title: String, keywords: [String], shortcut: String?, run: @MainActor () -> Void,
                        unavailable: @MainActor () -> String?)] = [
            ("project.switch", T("Switch Project", "Trocar de projeto"), ["project", "switch", "projeto", "trocar"], "cmd+shift+s",
             { palette.open(ProjectSource(projects: projects)) }, { nil }),
            ("project.new", T("Open Project…", "Abrir projeto…"), ["project", "open", "folder", "new", "projeto", "abrir", "pasta"], "ctrl+cmd+n",
             chooseFolder, { nil }),
            ("project.rename", T("Rename Project", "Renomear o projeto"), ["project", "rename", "name", "projeto", "renomear"], nil,
             { askName(projects) }, { nil }),
            ("project.close", T("Close Project", "Fechar o projeto"), ["project", "close", "projeto", "fechar"], nil,
             { projects.closeActive() }, needsTwo),
            ("project.next", T("Next Project", "Próximo projeto"), ["project", "next", "projeto", "próximo"], "ctrl+cmd+right",
             { projects.selectNext(step: 1) }, needsTwo),
            ("project.previous", T("Previous Project", "Projeto anterior"), ["project", "previous", "projeto", "anterior"], "ctrl+cmd+left",
             { projects.selectNext(step: -1) }, needsTwo),
        ]
        return commands.map { c in
            Command(id: c.id, title: c.title, keywords: c.keywords, category: .tabs, defaultShortcut: c.shortcut,
                    action: .run(c.run), unavailableReason: c.unavailable)
        }
    }

    /// project.rename: empty goes back to the folder's name.
    @MainActor
    static func askName(_ projects: ProjectsController) {
        guard let window = projects.active?.hostWindow else { return }
        let index = projects.activeIndex
        let alert = NSAlert()
        alert.messageText = T("Rename project", "Renomear o projeto")
        alert.informativeText = T("Empty goes back to the folder's name.", "Vazio volta ao nome da pasta.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = projects.activeName
        alert.accessoryView = field
        alert.addButton(withTitle: T("Rename", "Renomear"))
        alert.addButton(withTitle: T("Cancel", "Cancelar")).keyEquivalent = "\u{1B}"
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                if response == .alertFirstButtonReturn { projects.rename(at: index, to: field.stringValue) }
            }
        }
    }
}

extension ProjectsCommands {
    /// The projects as a palette list, for the app's "@" (with the tabs).
    @MainActor
    public static func source(_ projects: ProjectsController) -> PaletteSource { ProjectSource(projects: projects) }
}

/// The projects in the palette, with their folder (two of one name tell apart); choosing one
/// shows it.
@MainActor
final class ProjectSource: PaletteSource {
    private weak var projects: ProjectsController?

    init(projects: ProjectsController) {
        self.projects = projects
    }

    var placeholder: String { T("Switch to project", "Trocar para o projeto") }
    var emptyText: String { T("No projects", "Nenhum projeto") }
    var icon: Icon { .stack }

    func search(_ query: String, show: @escaping @MainActor ([PaletteItem], String?) -> Void) {
        guard let projects else { return show([], nil) }
        let home = NSHomeDirectory()
        let items = projects.projects.enumerated()
            .filter { query.isEmpty || $0.element.name.localizedCaseInsensitiveContains(query) || $0.element.folder.localizedCaseInsensitiveContains(query) }
            .map { index, project in
                let tabs = project.tabs.count == 1 ? T("1 tab", "1 aba") : T("\(project.tabs.count) tabs", "\(project.tabs.count) abas")
                let place = project.folder.hasPrefix(home) ? "~" + project.folder.dropFirst(home.count) : project.folder
                // The project's picture on the left, as the rail shows it (plan 36 B); the glyph without one.
                let picture = projects.imageURL(project.image).flatMap { NSImage(contentsOf: $0) }
                let item = PaletteItem(id: String(index), title: (project.emoji.map { $0 + "  " } ?? "") + project.name,
                                       detail: (index == projects.activeIndex ? T("current · ", "atual · ") : "") + "\(place) · \(tabs)",
                                       icon: picture == nil ? .stack : nil, image: picture)
                return item
            }
        show(items, nil)
    }

    func choose(_ item: PaletteItem) {
        if let index = Int(item.id) { projects?.select(index) }
    }

    func stop() {}
}
