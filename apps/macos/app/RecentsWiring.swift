import AppKit
import Home
import Projects
import Sidebar
import Themes

/// Nothing open (plan 38 G; ADR 0039): the sidebar lists the recent projects with their faces, New
/// Project… and Open Folder…; the home screen is in the center; the bottom bar keeps only what
/// counts without a project.
extension WindowSession {
    /// The drawer, the account, the coffee and the environment (the reference's "Nada aberto").
    static let nothingOpenItems: Set<String> = ["drawer", "usage", "keepAwake", "environment"]

    func drawNothingOpen(_ sidebar: WorkSidebarView) {
        let recents = (projects?.recent ?? []).filter { FileManager.default.fileExists(atPath: $0.folder) }.map { recent in
            let face = WorkProject(id: recent.folder, name: recent.name, tint: Self.workTint(recent.color),
                                   image: projects?.imageURL(recent.image)?.path, emoji: recent.emoji)
            return WorkRecent(project: face, when: HomeWords.when(recent.usedAt))
        }
        sidebar.showRecents(recents, openShortcut: app.keymapLabel("project.new") ?? "")
    }

    /// A project's color name as the avatar's red, green and blue, in the theme's ANSI.
    static func workTint(_ name: String?) -> [Double]? {
        name.flatMap(WorkColor.init(rawValue:)).map { color in
            let value = color.rgb(in: ThemeStore.shared.current).value
            return [Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255]
        }
    }
}
