import CommandPalette
import Strings

/// The power commands (ADR 0005); the title bar's menu runs the same ids.
/// Each shows only when it changes something (owner, 2026-10-20).
public enum PowerCommands {
    @MainActor
    public static func all(_ power: PowerController) -> [Command] {
        func unless(_ mode: PowerController.Mode, _ reason: String) -> @MainActor @Sendable () -> String? {
            { [weak power] in power?.mode == mode ? reason : nil }
        }
        return [
            Command(id: "power.toggle", title: T("Toggle Keep Awake", "Ligar ou desligar o manter acordado"),
                    keywords: ["caffeinate", "amphetamine", "acordado", "awake", "dormir", "sleep", "toggle"], category: .app,
                    defaultShortcut: "cmd+shift+a", action: .run { [weak power] in power?.toggle() }),
            Command(id: "power.keep-awake", title: T("Keep the Computer Awake", "Manter o computador acordado"),
                    keywords: ["caffeinate", "amphetamine", "dormir", "sleep", "energia", "awake", "power"], category: .app,
                    action: .run { [weak power] in power?.set(.always) }, unavailableReason: unless(.always, T("Already awake", "Já está acordado"))),
            Command(id: "power.keep-awake-while-running", title: T("Keep Awake While a Program Runs", "Manter acordado com programa rodando"),
                    keywords: ["caffeinate", "amphetamine", "dormir", "sleep", "agente", "build", "awake", "agent", "running"], category: .app,
                    action: .run { [weak power] in power?.set(.running) }, unavailableReason: unless(.running, T("Already set", "Já está assim"))),
            Command(id: "power.allow-sleep", title: T("Let the Computer Sleep", "Deixar o computador dormir"),
                    keywords: ["caffeinate", "amphetamine", "dormir", "sleep", "desligar", "allow sleep"], category: .app,
                    action: .run { [weak power] in power?.set(.off) }, unavailableReason: unless(.off, T("Already allowed to sleep", "Já pode dormir"))),
        ]
    }
}
