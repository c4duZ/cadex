# orchestration (app macOS)

## O que eu quero
- Vários agentes de uma vez: a mesma tarefa em N agentes (corrida), tarefas encadeadas despachadas a
  agentes que reportam (execução) e prompts num horário (automação)
  (`../../../../docs/spec/orchestration.md`, plano `../../../../docs/plans/24-many-agents.md`,
  `../../../../docs/adr/0033-cadex-launches-agents.md`,
  `../../../../docs/adr/0034-scheduled-automations.md`).
- Só no Mac, por ora: se o Windows precisar, o modelo desce para o núcleo.

## O que eu não quero
- Abrir agente, banco, timer ou LaunchAgent com orchestration.enabled e orchestration.automations
  desligadas (nascem desligadas).
- O prompt num comando de shell: vai por argumento do exec ou por arquivo (ADR 0033).
- Importar o miolo de worktrees, agents ou agent-tools: o app liga as portas de entrada delas.
- Agente aprovando portão, parando despacho ou mexendo em automação.

## Como eu quero
- `OrchestrationModel.swift`: os registros (corrida e concorrentes, execução, tarefa, despacho,
  mensagem, automação e execução de automação), valores Codable; `LaunchMode` só tem `tab` (o
  `claude --bg` ficou de fora na fase B, 2026-11-16, até um teste mostrar que os hooks e a status
  line do kit chegam a uma sessão em segundo plano).
- `RunGraph.swift`: as regras, puras: `settle` (pronta quando as dependências estão concluídas e o
  portão aprovado; bloqueada quando uma falhou, está bloqueada, some ou o portão foi recusado, em
  cadeia), `cycle` (o ciclo que uma dependência fecharia), `maySpawn` (orchestration.maxDepth),
  `hasSlot` (orchestration.maxAgents), `stalled`, `orphaned` e `descendants`.
- `OrchestrationStore.swift`: o SQLite do sistema em
  `~/Library/Application Support/Cadex/orchestration/state.sqlite` (0600, pasta 0700), uma tabela por
  tipo, cada linha o JSON do registro com o id do pai indexado; linha que não lê é pulada; `batch`
  é tudo ou nada.
- `RunBook.swift` + `RunInbox.swift`: a vida de uma execução sobre o banco: tarefas sem ciclo,
  despacho só de tarefa pronta e dentro do teto, `reportDone`, `sign` (sinal de vida), `fail`,
  `retry`, portões, `stop` (o despacho e os de baixo; as tarefas voltam a prontas, "stopped"),
  `stopRun`, `reapOrphans` ("exited without reporting"); `spawn`, `ask` (ao dono ou ao
  coordenador), `send` (só na mesma execução), `answer` e `inbox`.
- `RaceBook.swift`: a corrida (2 a orchestration.maxAgents concorrentes numerados de 1), o vencedor
  e o descarte; `AutomationBook`: automações (nascem desligadas) e o histórico.
- `OrchestrationController.swift`: a porta de entrada (`shared`): `isEnabled`,
  `automationsEnabled` e `limits` vindos das configurações (`../../app/SettingsBridge.swift`); o banco só
  abre no primeiro uso com a feature ligada e fecha quando as duas desligam;
  `sessionEnvironment(dispatch:)` é o CADEX_DISPATCH_ID que o kit põe na sessão de um despacho
  (`SessionKit.claudeCommand(sessionEnvironment:)`).
- Configurações (`../settings/OrchestrationSettings.swift`, `../settings/OrchestrationRows.swift`):
  orchestration.enabled, orchestration.automations, orchestration.maxAgents (6),
  orchestration.maxDepth (2), orchestration.heartbeatMinutes (10),
  orchestration.keepAwakeDuringRuns, orchestration.defaultBudgetUsd (5) e
  orchestration.defaultMaxMinutes (60).

## Como validar
- `make macos-test` (OrchestrationTests, banco temporário ou em memória): dependências tornando
  tarefas prontas, ciclo recusado, falha bloqueando em cadeia e a nova tentativa, portões,
  profundidade máxima, parar o pai para os filhos, despacho órfão, relatório repetido, sinal de
  vida e "stalled?", teto de agentes e execução parada, caixa de entrada, o arquivo 0600 que
  persiste, linha ilegível pulada, lote desfeito, corrida, automações, e o controlador desligado
  sem arquivo nenhum.
