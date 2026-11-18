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
  e o descarte; `branchesLeft` e `markBranchDeleted`: as branches dos descartados que ainda
  existem, para o orchestration.delete-race-branches não listar de novo a apagada; `AutomationBook`: automações (nascem desligadas) e o histórico.
- `OrchestrationController.swift`: a porta de entrada (`shared`): `isEnabled`,
  `automationsEnabled` e `limits` vindos das configurações (`../../app/SettingsBridge.swift`); o banco só
  abre no primeiro uso com a feature ligada e fecha quando as duas desligam;
  `sessionEnvironment(dispatch:)` é o CADEX_DISPATCH_ID que o kit põe na sessão de um despacho
  (`SessionKit.claudeCommand(sessionEnvironment:)`).
- A corrida (fase C): `PromptFiles.swift` (o prompt num arquivo 0600 numa pasta 0700, até 100 KB,
  sem NUL; CADEX_PROMPTS_DIR numa instância de teste; o que ninguém pegou sai depois de um dia),
  `ClaudeTrust.swift` (a confiança do Claude Code lida sem escrever: `projects[<pasta>]
  .hasTrustDialogAccepted` do .claude.json da conta, a pasta, uma pasta mãe confiada ou o
  repositório principal), `RaceLaunch.swift` (as recusas antes de criar qualquer coisa: desligada,
  menos de 2 ou mais de orchestration.maxAgents, prompt vazio ou grande, conta local sem confiança;
  e o comando do concorrente, `cadex claude --cadex-prompt-file` pelo kit), `RaceColumns.swift`
  (as colunas do quadro, puras, e `SessionCost`, o `cost.total_cost_usd` que o `cadex statusline`
  grava por sessão), `AccountChoice.swift` (as contas das folhas de execução e automação; o formulário de corrida saiu no plano 29, a corrida nasce na folha Nova tarefa da worktrees), `RaceBoardView.swift` e
  `RaceBoardDocument.swift` (o quadro numa aba), `RaceCommands.swift` (orchestration.toggle,
  -show-race, -pick-winner, -discard-race e -delete-race-branches, com as listas no ⌘K).
  O que junta worktrees, agents, tabs e source-control é do app (`../../app/RaceWiring.swift`,
  `../../app/RaceBoardWiring.swift`). CADEX_ORCHESTRATION_DIR troca a pasta do estado numa
  instância de teste.
- A execução com o dono coordenando (fase D1): `RunOwner.swift` (`attach`, a sessão da aba depois
  de gravar o despacho, porque o id dele vai no CADEX_DISPATCH_ID; `record`, o custo e o id do
  Claude, só escrito quando muda; `markDone`, o "Mark Done" do dono, também sobre a última
  tentativa que falhou; `enforceCap`; e em `RunGraph` `spent`, `busySeconds`, a união dos
  intervalos com agente trabalhando, não o tempo desde a criação, e `overCap`), `RunLaunch.swift`
  (as recusas antes de criar: desligada, execução parada, tarefa não pronta, especificação vazia ou
  grande, sem vaga, conta sem confiança; o prompt é a especificação, ou o título; `bases`: a
  branch da dependência concluída mais recente primeiro, depois a do repositório), `RunRows.swift`
  (as linhas da página, puras: o nível no grafo, a última tentativa e as anteriores com o motivo, a
  linha "waiting for a free slot (N of M)" e as ações que cabem), `RunQueue.swift` (a fila no teto de
  agentes, guardada na tarefa, a mais antiga primeiro; e RunError.message, o erro pelos títulos,
  o ciclo como "a → c → b → a"), `RunForms.swift` (as folhas New Run, Add Task, a do despacho, com
  o prompt inteiro, o modo de permissão e um terminal parado para reaproveitar, e a das
  dependências), `RunPageView.swift` (a página e o `RunPageDocument`, sem relógio próprio) e
  `RunCommands.swift` (orchestration.new-run, -show-run, -add-task, -dispatch, -retry, -mark-done,
  -stop-dispatch, que também tira da fila, -stop-run e -set-dependencies, com as listas no ⌘K). O
  teto de agentes vale para corridas e execuções juntas (`othersLive`). O despacho usa o RaceLaunch.localCommand com
  `sessionEnvironment`. O app liga (`../../app/RunWiring.swift`, `../../app/RunPageWiring.swift`).
- Os agentes supervisionados (fase D2): `RunAgents.swift` (`caller`: o despacho da sessão do token,
  também um já encerrado, para o segundo report-done ouvir "already done", senão a execução que ela
  coordena; um CADEX_DISPATCH_ID que não é ele é recusado; `heartbeat`, `addGate`, `spawnTask`, um
  nível abaixo do pedinte e recusado em orchestration.maxDepth, com `after=` e `gate=`, despachada
  sozinha como o agente que pediu; `tellCoordinator`, `configure` e `setCoordinator`;
  `readyOnTheirOwn`, as prontas que começam sozinhas, menos a que o dono parou; `failTask`, a que não
  conseguiu começar sozinha) e `RunAgentAPI.swift` (a resposta de cada comando do agente:
  report-done, report-heartbeat, ask, send-message, inbox, spawn e o retry do coordenador, com o que
  o app faz depois). `NewRunForm.swift`: quem coordena (o dono, o dono com as prontas sozinhas, um
  agente com o objetivo), a conta e o modelo. A página ganhou o portão com o que as dependências
  entregaram, "stalled?" em amarelo, "waiting for an answer", a nota do sinal de vida e a caixa de
  entrada com "Answer…"; o ⌘K, orchestration.add-gate, -approve-gate, -reject-gate,
  -answer-question e os seis comandos do agente (com argumentos, pelo `cadex run`).
- As automações (fase E): `AutomationSchedule.swift` (puro: o próximo horário de cada recorrência,
  dias úteis, todo dia, a cada N horas desde a meia-noite, a cada N minutos desde a hora e uma vez;
  o que vence agora, várias perdidas viram uma, atrasada mais de 2 min é perdida e roda ou é pulada
  pela regra dela, "still running" com a anterior rodando; as datas do launchd), `AutomationAgent.swift`
  (o plist do LaunchAgent com StartCalendarInterval, sem KeepAlive, RunAtLoad nem StartInterval, o
  programa `cadex automations due`, escrito e carregado com `launchctl bootstrap`, removido sem
  data; CADEX_LAUNCH_AGENTS_DIR e CADEX_LAUNCH_LABEL numa instância de teste),
  `AutomationLaunch.swift` (as recusas antes de rodar, com a chave de API pelo apiKeyHelper da conta
  lido sem escrever, a menos que a automação use a assinatura; as palavras do `claude`, o modo de
  permissão sempre; e a vida da execução no `AutomationBook`: ligar a partir de agora, começar,
  pular, terminar), `NewAutomationForm.swift`, `AutomationHistory.swift` (as linhas e a página do
  histórico) e `AutomationCommands.swift` (orchestration.toggle-automations, -new-automation,
  -toggle-automation, -run-automation-now e -show-automation-history). O controlador avisa quando
  orchestration.automations muda (`onAutomationsSwitch`).
- `OrchestrationPage.swift` (plano 30 B): a cara nova das páginas da orquestração (a página que
  rola, o cabeçalho com o nome e os botões, o rótulo de seção, o cartão com a peça de estado e o
  recuo do grafo, os botões do app); a página da execução (`RunPageView.swift`, cada tarefa um
  cartão) e o histórico de uma automação (`AutomationHistory.swift`, cada rodada um cartão) são
  páginas (isPage) feitas com ela.
- O quadro (plano 30 B): `BoardModel.swift` (cartões, colunas pelo estado e filtros, puros),
  `BoardView.swift` (`BoardDocument`, a página "cadex:board") e `BoardParts.swift` (a página com a
  rolagem, as colunas em 4, 2 ou 1 e a fileira de filtros que quebra). A corrida no centro:
  `RaceLaneViews.swift` (a faixa do pedido com Compare… e o pé de cada concorrente).
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
  sem arquivo nenhum; da corrida: o arquivo do prompt, a confiança, as recusas, o comando sem o
  texto, as colunas e o custo; da execução (D1): marcar concluída (a última tentativa, também a que
  falhou), o custo gravado, o tempo com agentes como união, o teto parando tudo, as recusas do
  despacho em ordem, de onde ele parte, as linhas da página e o CADEX_DISPATCH_ID só nas
  configurações da sessão; a fila (ordem, só prontas, sai ao despachar e com a execução parada), a
  vaga dividida com a corrida, as dependências mudadas depois (ciclo pelos títulos, não numa
  despachada), o grafo, o histórico e a linha da fila na página; da D2 (`tests/Agents.swift`): o
  pedinte pela sessão e as recusas, report-done e o repetido, sinal de vida e "stalled?", pergunta
  ao dono e a resposta, recado só na mesma execução, o coordenador respondendo e sabendo como as
  tarefas terminaram, spawn (profundidade, after, gate, a vaga, parar o pai), o coordenador criando
  no topo, portões, a tarefa que não começa sozinha e o prompt do coordenador; da E
  (`tests/Automations.swift`): o próximo horário de cada recorrência, o que vence e a perdida, o
  plist e a instalação com um launchctl falso, as recusas e as palavras, o histórico.
