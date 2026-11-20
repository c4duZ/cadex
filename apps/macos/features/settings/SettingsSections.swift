import AppKit
import Icons
import Strings

/// The settings window's sections, in the list on the left (plan 32 A; the owner, 2026-11-18: each
/// module in its section, the status bar and the accounts inside, a search). The rows of the ones
/// made of rows are searched; Appearance, Shortcuts and About are pages of their own.
enum SettingsSection: String, CaseIterable, Sendable {
    case general, appearance, terminal, files, git, agents, notifications, memory, orchestration, machines, phone, statusBar, shortcuts, about

    var title: String {
        switch self {
        case .general: T("General", "Geral")
        case .appearance: T("Appearance", "Aparência")
        case .terminal: "Terminal"
        case .files: T("Files and preview", "Arquivos e preview")
        case .git: T("Git and review", "Git e revisão")
        case .agents: T("Agents and accounts", "Agentes e contas")
        case .notifications: T("Notifications", "Notificações")
        case .memory: T("Memory", "Memória")
        case .orchestration: T("Many agents", "Muitos agentes")
        case .machines: T("Machines and SSH", "Máquinas e SSH")
        case .phone: T("Phone", "Celular")
        case .statusBar: T("Status bar", "Barra de status")
        case .shortcuts: T("Shortcuts", "Atalhos")
        case .about: T("About", "Sobre")
        }
    }

    var subtitle: String {
        switch self {
        case .general: T("Language, the interface's size and font, keeping the computer awake.", "Idioma, tamanho e fonte da interface, manter o computador acordado.")
        case .appearance: T("The theme, the window's frame and a background image.", "O tema, a moldura da janela e uma imagem de fundo.")
        case .terminal: T("The shell, the questions before closing or pasting, the text and the keyboard.", "O shell, as perguntas antes de fechar ou colar, o texto e o teclado.")
        case .files: T("Where files open, the file tree, Markdown and the web preview.", "Onde os arquivos abrem, a árvore, o Markdown e o preview web.")
        case .git: T("Where tasks' worktrees go and what the review marks.", "Onde ficam as worktrees das tarefas e o que a revisão marca.")
        case .agents: T("What Cadex reads of the agents, what they can use, and the accounts.", "O que o Cadex lê dos agentes, o que eles podem usar, e as contas.")
        case .notifications: T("The bell, the Dock and each kind of notification with its sound.", "O sino, o Dock e cada tipo de notificação com o som dele.")
        case .memory: T("The defaults for every project; a project's own are on its Settings page.", "Os padrões de todos os projetos; os de um projeto ficam na página Configurações dele.")
        case .orchestration: T("Races, runs and scheduled automations, and their caps.", "Corridas, execuções e automações agendadas, e os tetos delas.")
        case .machines: T("SSH hosts and the machines of your tailnet.", "Hosts SSH e as máquinas da sua tailnet.")
        case .phone: T("Your Cadex terminals and Claude from your phone, over SSH through your tailnet.", "Os terminais do Cadex e o Claude pelo celular, por SSH pela sua tailnet.")
        case .statusBar: T("Drag between Left and Right; a hidden item measures nothing.", "Arraste entre Esquerda e Direita; um item escondido não mede nada.")
        case .shortcuts: T("Every command's shortcut.", "O atalho de cada comando.")
        case .about: ""
        }
    }

    var icon: Icon {
        switch self {
        case .general: .gearSix
        case .appearance: .palette
        case .terminal: .terminalWindow
        case .files: .folder
        case .git: .gitBranch
        case .agents: .sparkle
        case .notifications: .bell
        case .memory: .memory
        case .orchestration: .kanban
        case .machines: .hardDrives
        case .phone: .deviceMobile
        case .statusBar: .slidersHorizontal
        case .shortcuts: .keyboard
        case .about: .info
        }
    }
}
