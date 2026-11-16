import AppKit
import Strings

/// The project memory's section in General (docs/spec/memory.md, plan 22
/// phase C): on or off, and whether the accounts share it.
@MainActor
enum MemoryRows {
    static func make(_ store: SettingsStore) -> [NSView] {
        let m = store.settings.memory
        return [
            SettingsPage.section(T("Memory", "Memória")),
            SettingsPage.row(T("Project memory", "Memória do projeto"),
                             T("What each agent session opened by Cadex did (prompts, the files it touched, how it ended) is kept per repository on this Mac, and the next session starts with it. Besides a short preparation after each update, nothing runs until an agent session opens. Off, sessions get no memory hooks.",
                               "O que cada sessão de agente aberta pelo Cadex fez (prompts, os arquivos que mexeu, como terminou) fica guardado por repositório neste Mac, e a próxima sessão começa com isso. Fora uma preparação curta depois de cada atualização, nada roda até uma sessão de agente abrir. Desligado, as sessões não ganham os hooks da memória."),
                             control: SettingsPage.toggle(m.enabled) { on in store.update { $0.memory.enabled = on } }),
            SettingsPage.row(T("Share across accounts", "Compartilhar entre contas"),
                             T("Every account sees the same memory of a project. Off, each account keeps its own, for clients' accounts that must not see each other's work.",
                               "Todas as contas veem a mesma memória de um projeto. Desligado, cada conta tem a sua, para contas de clientes que não podem ver o trabalho uma da outra."),
                             control: SettingsPage.toggle(m.shareAcrossAccounts) { on in store.update { $0.memory.shareAcrossAccounts = on } }),
        ]
    }
}
