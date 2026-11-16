import AppKit
import Strings

/// Many agents at once in General (docs/spec/orchestration.md, plan 24
/// phase B): races and runs, automations, and their caps. Both off by
/// default (docs/adr/0033-cadex-launches-agents.md).
@MainActor
enum OrchestrationRows {
    static func make(_ store: SettingsStore) -> [NSView] {
        let o = store.settings.orchestration
        return [
            SettingsPage.section(T("Many Agents", "Muitos agentes")),
            SettingsPage.row(T("Races and runs", "Corridas e execuções"),
                             T("Off by default. On, Cadex may open Claude with a prompt in a tab when you start a race (the same task in several agents) or a run (tasks dispatched to agents that report back). You always see what will run, where, on which account and with which cap before it starts; each agent spends that account's usage.",
                               "Desligado por padrão. Ligado, o Cadex pode abrir o Claude com um prompt numa aba quando você começa uma corrida (a mesma tarefa em vários agentes) ou uma execução (tarefas despachadas a agentes que reportam). Você sempre vê o que vai rodar, onde, em qual conta e com qual teto antes de começar; cada agente gasta o uso daquela conta."),
                             control: SettingsPage.toggle(o.enabled) { on in store.update { $0.orchestration.enabled = on } }),
            SettingsPage.row(T("Scheduled automations", "Automações agendadas"),
                             T("Off by default. On, an automation you turn on runs its prompt on its schedule, even with Cadex closed (macOS will say a background item was added). Anthropic's Consumer Terms (§3.7) restrict automated use of a subscription: each automation suggests an API key set in the account's Claude Code (apiKeyHelper), and using the subscription is your choice per automation. Cadex never stores or reads the key.",
                               "Desligado por padrão. Ligado, uma automação que você ligar roda o prompt dela no horário, mesmo com o Cadex fechado (o macOS vai avisar que um item em segundo plano foi adicionado). Os Termos de Consumidor da Anthropic (§3.7) restringem o uso automatizado de uma assinatura: cada automação sugere uma chave de API configurada no Claude Code da conta (apiKeyHelper), e usar a assinatura é escolha sua, por automação. O Cadex nunca guarda nem lê a chave."),
                             control: SettingsPage.toggle(o.automations) { on in store.update { $0.orchestration.automations = on } }),
            SettingsPage.row(T("Agents at once", "Agentes ao mesmo tempo"),
                             T("The most agents Cadex keeps running at once; more wait for a free slot.",
                               "O máximo de agentes que o Cadex deixa rodando ao mesmo tempo; os outros esperam uma vaga."),
                             control: SettingsPage.number(Double(o.maxAgents), range: 1...20, step: 1, format: "%.0f") { value in
                                 store.update { $0.orchestration.maxAgents = Int(value) }
                             }),
            SettingsPage.row(T("Sub-task depth", "Profundidade de sub-tarefas"),
                             T("How many levels of sub-tasks an agent may spawn.",
                               "Quantos níveis de sub-tarefas um agente pode criar."),
                             control: SettingsPage.number(Double(o.maxDepth), range: 0...5, step: 1, format: "%.0f") { value in
                                 store.update { $0.orchestration.maxDepth = Int(value) }
                             }),
            SettingsPage.row(T("Stalled after", "Parado depois de"),
                             T("Minutes without a sign of life before an agent of a run shows as stalled.",
                               "Minutos sem sinal de vida até um agente de uma execução aparecer como parado."),
                             control: SettingsPage.number(Double(o.heartbeatMinutes), range: 1...120, step: 1, format: "%.0f min") { value in
                                 store.update { $0.orchestration.heartbeatMinutes = Int(value) }
                             }),
            SettingsPage.row(T("Default spending cap", "Teto de gasto padrão"),
                             T("What a new race, run or automation proposes, in US dollars of the account's usage; past it, the agent is stopped.",
                               "O que uma corrida, execução ou automação nova propõe, em dólares do uso da conta; passou dele, o agente é parado."),
                             control: SettingsPage.number(o.defaultBudgetUsd, range: 0.5...100, step: 0.5, format: "US$ %.2f") { value in
                                 store.update { $0.orchestration.defaultBudgetUsd = value }
                             }),
            SettingsPage.row(T("Default time cap", "Teto de tempo padrão"),
                             T("What a new race, run or automation proposes; past it, the agent is stopped.",
                               "O que uma corrida, execução ou automação nova propõe; passou dele, o agente é parado."),
                             control: SettingsPage.number(Double(o.defaultMaxMinutes), range: 5...480, step: 5, format: "%.0f min") { value in
                                 store.update { $0.orchestration.defaultMaxMinutes = Int(value) }
                             }),
            SettingsPage.row(T("Keep awake during automations", "Manter acordado durante automações"),
                             T("The Mac does not sleep while an automation runs.",
                               "O Mac não dorme enquanto uma automação roda."),
                             control: SettingsPage.toggle(o.keepAwakeDuringRuns) { on in store.update { $0.orchestration.keepAwakeDuringRuns = on } }),
        ]
    }
}
