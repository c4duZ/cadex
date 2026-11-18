import AppKit
import CommandPalette
import Icons
import Menus
import Projects
import Strings
import Themes

/// Editing a project (plan 36 phase B; docs/adr/0038-rail-and-side-column.md): the "Edit project"
/// sheet with the name, the picture or emoji and the color, the same sheet creating one from the
/// rail's "+", a picture dropped on the rail, and the rail's right click. Every action is a
/// command (ADR 0005); the right click sets `projectTarget` so the command acts on that project.
extension WindowSession {
    /// The project a command acts on: the one right-clicked in the rail, else the active one.
    func takeProjectTarget() -> String? {
        defer { projectTarget = nil }
        return projectTarget ?? projects?.activeFolder
    }

    func projectEditCommands() -> [Command] {
        [
            Command(id: "project.edit", title: T("Edit Project (Name, Image, Color)…", "Editar o projeto (nome, imagem, cor)…"),
                    keywords: ["project", "rename", "name", "image", "picture", "photo", "icon", "emoji", "color",
                               "projeto", "nome", "imagem", "foto", "ícone", "cor"], category: .tabs,
                    action: .run { [weak self] in if let self, let folder = self.takeProjectTarget() { self.editProject(folder) } }),
            Command(id: "project.create", title: T("New Project…", "Novo projeto…"),
                    keywords: ["project", "new", "create", "folder", "projeto", "novo", "criar", "pasta"], category: .tabs,
                    action: .run { [weak self] in self?.createProject() }),
            Command(id: "project.new-terminal", title: T("New Terminal in the Project", "Novo terminal no projeto"),
                    keywords: ["project", "terminal", "new", "projeto", "novo"], category: .tabs,
                    action: .run { [weak self] in
                        guard let self, let folder = self.takeProjectTarget() else { return }
                        self.pickProject(folder)
                        self.projects?.active?.newTab(cwd: folder)
                    }),
            Command(id: "project.pin", title: T("Pin or Unpin the Project", "Fixar ou soltar o projeto"),
                    keywords: ["project", "pin", "unpin", "keep", "rail", "projeto", "fixar", "soltar", "trilho"], category: .tabs,
                    action: .run { [weak self] in
                        guard let self, let projects = self.projects, let folder = self.takeProjectTarget() else { return }
                        projects.setPinned(!projects.isPinned(folder), for: folder)
                        self.refreshTree()
                    }),
            Command(id: "project.close-terminals", title: T("Close the Project's Terminals", "Fechar os terminais do projeto"),
                    keywords: ["project", "close", "terminals", "projeto", "fechar", "terminais"], category: .tabs,
                    action: .run { [weak self] in
                        guard let self, let folder = self.takeProjectTarget() else { return }
                        self.projects?.closeTerminals(folder: folder)
                        self.refreshTree()
                    }),
            Command(id: "project.remove", title: T("Remove the Project from the Sidebar", "Tirar o projeto da barra lateral"),
                    keywords: ["project", "remove", "rail", "sidebar", "projeto", "tirar", "remover", "trilho"], category: .tabs,
                    action: .run { [weak self] in
                        guard let self, let folder = self.takeProjectTarget() else { return }
                        self.projects?.removeFromRail(folder: folder)
                        self.refreshTree()
                    }),
            Command(id: "project.reveal", title: T("Show the Project in Finder", "Mostrar o projeto no Finder"),
                    keywords: ["project", "finder", "reveal", "folder", "projeto", "pasta"], category: .tabs,
                    action: .run { [weak self] in
                        guard let folder = self?.takeProjectTarget() else { return }
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                    }),
            Command(id: "project.copy-path", title: T("Copy the Project's Path", "Copiar o caminho do projeto"),
                    keywords: ["project", "path", "copy", "folder", "projeto", "caminho", "copiar"], category: .tabs,
                    action: .run { [weak self] in
                        guard let folder = self?.takeProjectTarget() else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(folder, forType: .string)
                    }),
        ]
    }

    /// The rail's right click on a project: each line runs a command on it. New Task, Settings and
    /// Close show the project first (they act on the one in the window).
    func railMenu(_ folder: String) -> [MenuEntry] {
        func on(_ id: String) -> @MainActor () -> Void {
            { [weak self] in self?.projectTarget = folder; _ = self?.commands.run(id) }
        }
        func shown(_ id: String) -> @MainActor () -> Void {
            { [weak self] in self?.pickProject(folder); _ = self?.commands.run(id) }
        }
        let pinned = projects?.isPinned(folder) ?? false
        return [
            MenuEntry(T("New Terminal", "Novo terminal"), icon: .terminalWindow, action: on("project.new-terminal")),
            MenuEntry(T("New Task…", "Nova tarefa…"), icon: .plus, action: shown("worktrees.new-task")),
            .separator,
            MenuEntry(T("Edit Name and Image…", "Editar nome e imagem…"), icon: .pencilSimple, action: on("project.edit")),
            MenuEntry(pinned ? T("Unpin", "Soltar") : T("Pin", "Fixar"), icon: .pushPin, action: on("project.pin")),
            MenuEntry(T("Project Settings…", "Configurações do projeto…"), icon: .gearSix, action: shown("project.show-settings")),
            .separator,
            MenuEntry(T("Show in Finder", "Mostrar no Finder"), icon: .folderOpen, action: on("project.reveal")),
            MenuEntry(T("Copy Path", "Copiar o caminho"), icon: .copy, action: on("project.copy-path")),
            .separator,
            MenuEntry(T("Close Terminals", "Fechar os terminais"), icon: .x, action: on("project.close-terminals")),
            MenuEntry(T("Remove from the Sidebar", "Tirar da barra lateral"), icon: .trash, action: on("project.remove")),
        ]
    }

    /// A project's tile for the pages (the Projects cards, the project page's head).
    func projectPicture(_ folder: String) -> ProjectPicture? {
        guard let projects, let look = projects.look(of: folder) else { return nil }
        let tint = look.color.flatMap(WorkColor.init(rawValue:)).map { $0.rgb(in: ThemeStore.shared.current).nsColor }
        return ProjectPicture(image: projects.imageURL(look.image)?.path, emoji: look.emoji, tint: tint)
    }

    /// The work colors as the sheet offers them, in the theme's colors.
    private func workColorChoices() -> [(name: String, color: NSColor)] {
        let theme = ThemeStore.shared.current
        return WorkColor.allCases.map { ($0.rawValue, $0.rgb(in: theme).nsColor) }
    }

    func editProject(_ folder: String) {
        guard let projects, let look = projects.look(of: folder) else { return }
        let form = ProjectEditForm(name: look.name, color: look.color, colors: workColorChoices(),
                                   image: projects.imageURL(look.image)?.path, emoji: look.emoji, folder: nil)
        form.widthAnchor.constraint(equalToConstant: 420).isActive = true
        showForm(T("Edit Project", "Editar o projeto"), text: folder, form: form, primary: T("Save", "Salvar"), first: form.nameField) { [weak self] in
            self?.apply(form, to: folder, keeping: look.image)
        }
    }

    /// The rail's "+": the same sheet with the folder; Save opens the project and gives it the look.
    func createProject() {
        let form = ProjectEditForm(name: "", color: nil, colors: workColorChoices(), image: nil, emoji: nil, folder: "")
        form.widthAnchor.constraint(equalToConstant: 420).isActive = true
        showForm(T("New Project", "Novo projeto"), text: T("A folder of code, with the name and image you choose.",
                                                          "Uma pasta de código, com o nome e a imagem que você escolher."),
                 form: form, primary: T("Create", "Criar"), first: form.nameField) { [weak self] in
            guard let self, let folder = form.folder, !folder.isEmpty, let projects = self.projects else { return }
            self.folder.open(folder)
            projects.open(folder: folder)
            guard let root = projects.activeFolder else { return }
            // Made here: pinned (an opened folder, ⌘O, is not; ADR 0038).
            projects.setPinned(true, for: root)
            self.apply(form, to: root, keeping: nil)
        }
    }

    private func apply(_ form: ProjectEditForm, to folder: String, keeping image: String?) {
        guard let projects else { return }
        let picture = form.pickedImage.flatMap { projects.storeImage(from: $0) } ?? (form.removesImage ? nil : image)
        projects.setLook(ProjectLook(name: form.nameField.stringValue, color: form.color, image: picture, emoji: form.emoji), for: folder)
        refreshWorkColor()
        refreshTree()
    }

    /// An image file dropped on a project in the rail: its picture now.
    func dropProjectImage(_ folder: String, _ url: URL) {
        guard let projects, var look = projects.look(of: folder), let name = projects.storeImage(from: url) else { NSSound.beep(); return }
        look.image = name
        projects.setLook(look, for: folder)
        refreshTree()
    }
}
