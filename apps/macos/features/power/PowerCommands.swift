import CommandPalette

/// The power commands (ADR 0005); the title bar's menu runs the same ids.
/// Each shows only when it changes something (owner, 2026-10-20).
public enum PowerCommands {
    @MainActor
    public static func all(_ power: PowerController) -> [Command] {
        func unless(_ mode: PowerController.Mode, _ reason: String) -> @MainActor @Sendable () -> String? {
            { [weak power] in power?.mode == mode ? reason : nil }
        }
        return [
            Command(id: "power.keep-awake", title: "Manter o computador acordado",
                    keywords: ["caffeinate", "amphetamine", "dormir", "sleep", "energia"], category: .app,
                    action: .run { [weak power] in power?.set(.always) }, unavailableReason: unless(.always, "Já está acordado")),
            Command(id: "power.keep-awake-while-running", title: "Manter acordado com programa rodando",
                    keywords: ["caffeinate", "amphetamine", "dormir", "sleep", "agente", "build"], category: .app,
                    action: .run { [weak power] in power?.set(.running) }, unavailableReason: unless(.running, "Já está assim")),
            Command(id: "power.allow-sleep", title: "Deixar o computador dormir",
                    keywords: ["caffeinate", "amphetamine", "dormir", "sleep", "desligar"], category: .app,
                    action: .run { [weak power] in power?.set(.off) }, unavailableReason: unless(.off, "Já pode dormir")),
        ]
    }
}
