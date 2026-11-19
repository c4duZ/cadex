import AppKit
import Strings

/// The menu bar read as a Mac user expects (UX audit, 2026-11-18): View had about 88 items and
/// Terminal 65 in registration order, with no Window nor Help menu. Each category's commands go by
/// area (the id's first word: git, agents, memory…): a long menu gets one submenu per area, a short
/// one separators between areas. Every command is still there, and ⌘K finds them all.
extension CommandMenu {
    /// Over this many, a category's areas become submenus.
    static let flatLimit = 18

    func fill(_ menu: NSMenu, with commands: [Command]) {
        var areas: [(String, [Command])] = []
        for command in commands {
            let area = Self.area(of: command.id)
            if let index = areas.firstIndex(where: { $0.0 == area }) { areas[index].1.append(command) } else { areas.append((area, [command])) }
        }
        let nested = commands.count > Self.flatLimit && areas.count > 2
        for (index, (area, members)) in areas.enumerated() {
            if nested && members.count > 1 {
                let sub = NSMenu(title: Self.title(of: area))
                members.forEach { sub.addItem(item(for: $0)) }
                let holder = NSMenuItem(title: Self.title(of: area), action: nil, keyEquivalent: "")
                holder.submenu = sub
                menu.addItem(holder)
            } else {
                if index > 0, !nested { menu.addItem(.separator()) }
                members.forEach { menu.addItem(item(for: $0)) }
            }
        }
    }

    static func area(of id: String) -> String { String(id.split(separator: ".").first ?? Substring(id)) }

    /// An area's name in the menu.
    static func title(of area: String) -> String {
        switch area {
        case "agents": T("Agents", "Agentes")
        case "agent-tools": T("Agent Tools", "Ferramentas do agente")
        case "git": "Git"
        case "history": T("Git History", "Histórico do git")
        case "project": T("Project", "Projeto")
        case "memory": T("Memory", "Memória")
        case "preview": "Preview"
        case "theme": T("Themes", "Temas")
        case "machines": T("Machines", "Máquinas")
        case "worktrees": T("Tasks", "Tarefas")
        case "review": T("Review", "Revisão")
        case "power": T("Keep Awake", "Manter acordado")
        case "orchestration": T("Automations and Races", "Automações e corridas")
        case "computer-use": "Computer Use"
        case "media": T("Media", "Mídia")
        case "search": T("Search", "Busca")
        case "markdown": "Markdown"
        case "editor": "Editor"
        case "ssh", "remote": "SSH"
        case "drawer": T("Drawer", "Gaveta")
        case "tab": T("Tabs", "Abas")
        case "pane": T("Panes", "Painéis")
        default: area.prefix(1).uppercased() + area.dropFirst()
        }
    }

    /// The Mac's Window menu: Minimize, Zoom, Bring All to Front, and the windows, which AppKit
    /// lists itself once it is the app's windowsMenu.
    func windowMenu() -> NSMenuItem {
        let menu = NSMenu(title: T("Window", "Janela"))
        menu.addItem(withTitle: T("Minimize", "Minimizar"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: T("Zoom", "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: T("Bring All to Front", "Trazer tudo para a frente"), action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp?.windowsMenu = menu
        let top = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }

    /// The Mac's Help menu: its search field finds any menu item, and the palette is one click away.
    func helpMenu() -> NSMenuItem {
        let menu = NSMenu(title: T("Help", "Ajuda"))
        if let palette = registry.commands.first(where: { $0.id == "palette.open" }) { menu.addItem(item(for: palette)) }
        NSApp?.helpMenu = menu
        let top = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        top.submenu = menu
        return top
    }
}
