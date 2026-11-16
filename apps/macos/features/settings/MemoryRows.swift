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
            SettingsPage.row(T("Consolidate in the session", "Consolidar na sessão"),
                             T("At a milestone (the task marked ready, the context filling up, or Consolidate Memory Now) the agent is asked, when it finishes its answer, to write the session's decisions and lessons into the memory itself, once per milestone. No key and no other model: it is your session's Claude. The request shows in the conversation as a message from you.",
                               "Num marco (a tarefa marcada como pronta, o contexto enchendo, ou Consolidar a memória agora) o agente recebe, ao terminar a resposta, o pedido de escrever na memória as decisões e lições da sessão, uma vez por marco. Sem chave e sem outro modelo: é o Claude da sua sessão. O pedido aparece na conversa como uma mensagem sua."),
                             control: SettingsPage.toggle(m.consolidateInSession) { on in store.update { $0.memory.consolidateInSession = on } }),
            SettingsPage.row(T("Consolidate at context", "Consolidar com o contexto em"),
                             T("How full the session's context must be to count as a milestone.",
                               "O quanto o contexto da sessão precisa estar cheio para contar como marco."),
                             control: SettingsPage.number(Double(m.consolidateAtContext), range: 10...95, step: 5, format: "%.0f%%") { value in
                                 store.update { $0.memory.consolidateAtContext = Int(value) }
                             }),
        ]
    }
}
