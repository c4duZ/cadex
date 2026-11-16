# orchestration

## Para que serve
Pôr vários agentes trabalhando de uma vez sem sair do Cadex: a mesma tarefa em N agentes para
comparar e escolher (corrida), uma execução com tarefas encadeadas despachadas a agentes que
reportam ao Cadex (orquestração) e um prompt que roda sozinho num horário (automação). Os agentes
são o `claude` do dono numa aba de terminal, abertos com prompt só porque o dono ligou
(`docs/adr/0033-cadex-launches-agents.md`); as automações acordam o app pelo launchd
(`docs/adr/0034-scheduled-automations.md`). Plano `docs/plans/24-many-agents.md`. Só no Mac.

## Comportamento
### Ligar
- Tudo nasce desligado: orchestration.enabled (corrida e orquestração) e
  orchestration.automations (automações). Desligada, nenhum comando da feature aparece no ⌘K além
  do que a liga, nenhum banco é aberto, nenhum timer roda e nenhum LaunchAgent existe.
- Ligar mostra antes, numa folha, o que muda: o Cadex vai abrir agentes com prompt, cada um gasta o
  plano da conta escolhida, e cada execução tem teto. Para as automações, a folha diz também que
  uso automatizado da assinatura é zona cinzenta nos termos e sugere a chave de API pelo
  `apiKeyHelper` da conta (a posição da `docs/adr/0029-memory-agent.md`).
- Tetos: orchestration.maxAgents (agentes vivos ao mesmo tempo, padrão 6), orchestration.maxDepth
  (sub-tarefas de sub-tarefas, padrão 2), e por execução teto de gasto (US$) e de duração (min).

### Antes de rodar
- Toda corrida, despacho e automação mostra antes o que vai rodar: o prompt (as primeiras linhas,
  e o todo num clique), a pasta ou worktree, a máquina, a conta, o modelo, o modo de permissão e o
  teto. Só roda no "Start" do dono (ou, numa automação ligada, no horário que o dono ligou).
- A pasta tem de estar confiada pelo Claude Code (numa worktree, o repositório principal;
  `docs/spec/worktrees.md`). Sem confiança, nada abre: o Cadex diz "Trust this repository in
  Claude Code first" e oferece abrir uma aba com `claude` no repositório para o dono aceitar.
- O prompt chega ao `claude` como argumento do exec, nunca dentro de um comando de shell (ADR 0033).
  Aspas, `$()`, crases, `;` e quebras de linha chegam intactos e nada é executado.

### Corrida
- "New Race" (orchestration.new-race): o prompt, o ponto de partida (o branch atual, ou outro), e
  de 2 a orchestration.maxAgents concorrentes, cada um com conta, modelo e máquina (este Mac, ou uma
  remota pelo "Run on" mínimo, `docs/spec/worktrees.md`). Cria uma worktree por concorrente pelo
  New Task da feature worktrees, todas do mesmo commit, com os nomes `<tarefa>-1` … `<tarefa>-N`,
  e abre uma aba por concorrente com o prompt.
- O quadro da corrida (orchestration.show-race): uma coluna por concorrente com o estado
  (trabalhando, esperando você, terminou, saiu; no remoto, o do `claude agents --json`), o tempo, o
  custo (o `cost` da sessão gravado pelo `cadex statusline`), e o resumo do diff contra o ponto de
  partida (arquivos, +/−). Clicar numa coluna vai ao terminal dela; "Review" abre a revisão daquela
  worktree (`docs/spec/review.md`).
- "Compare" escolhe duas colunas e abre o diff entre as duas worktrees
  (git.review-compare-worktrees).
- "Pick Winner" (orchestration.pick-winner): o vencedor segue como uma tarefa normal da worktrees.
  Em seguida, "Discard the Others" (orchestration.discard-race) manda as outras worktrees para a
  Lixeira, depois de encerrar os agentes delas, e mantém as branches;
  orchestration.delete-race-branches apaga as branches das descartadas, com confirmação que lista
  cada uma.
- No remoto, descartar roda o `git worktree remove` lá, com a mesma confirmação, e a branch fica.

### Execuções (orquestração)
- "New Run" (orchestration.new-run): nome, repositório, coordenador (o dono, o padrão, ou uma sessão
  de agente aberta pelo Cadex) e teto. A execução tem uma caixa de entrada (perguntas e recados) e
  tarefas.
- Tarefa (orchestration.add-task): título, especificação (o texto que vira prompt), dependências
  (outras tarefas da execução) e, se o dono quiser, um portão. Estados: pendente, pronta,
  despachada, concluída, falhou, bloqueada. Fica **pronta** quando todas as dependências estão
  concluídas; fica **bloqueada** quando uma dependência falhou. Dependência que fecharia um ciclo é
  recusada na hora, dizendo o ciclo.
- Despacho (orchestration.dispatch): uma tentativa de uma tarefa pronta numa worktree e aba novas
  (ou num terminal parado reaproveitado, escolhido pelo dono), só neste Mac, com a especificação
  como prompt e CADEX_DISPATCH_ID no ambiente da aba (pelo kit da sessão). Com o dono coordenando,
  despachar é dele; com um agente coordenando, o agente despacha pelo `spawn` e cada tarefa nova
  aparece no quadro.
- Nova tentativa (orchestration.retry), só pelo dono ou pelo coordenador: um despacho novo da mesma
  tarefa; o anterior fica no histórico da tarefa, com o motivo.
- Parar (orchestration.stop-dispatch): encerra o agente do despacho (SIGTERM no `claude`) e os
  despachos filhos dele; a tarefa volta a pronta, marcada "stopped".

### Agentes supervisionados
- Uma sessão com CADEX_DISPATCH_ID reporta ao Cadex pela CLI `cadex` (`docs/spec/agent-tools.md`),
  com comandos que só valem para a execução dela:
  - `cadex run orchestration.report-done summary=…`: o despacho terminou; a tarefa fica concluída,
    com o resumo, e as que dependiam dela podem ficar prontas;
  - `cadex run orchestration.report-heartbeat note=…`: sinal de vida, com uma nota curta;
  - `cadex run orchestration.ask question=…`: a pergunta vai à caixa de entrada (do coordenador, ou
    do dono) e o despacho fica "esperando resposta"; a resposta volta pelo `cadex run
    orchestration.inbox` do agente;
  - `cadex run orchestration.send-message to=<despacho> text=…`: recado a outro despacho da mesma
    execução, lido por ele na caixa dele;
  - `cadex run orchestration.spawn title=… spec-file=<arquivo>`: uma sub-tarefa, até
    orchestration.maxDepth; a especificação vai em arquivo, e o Cadex a lê, nunca a executa.
- Sem sinal de vida nem hook por orchestration.heartbeatMinutes (padrão 10), o despacho fica
  "stalled?" no quadro e o Cadex avisa (a notificação do plano 19, tipo pergunta). Voltar a reportar
  tira a marca.
- Um agente que sai sem `report-done` deixa a tarefa "falhou", com o motivo "exited without
  reporting"; o dono decide se tenta de novo.
- Uma skill curta no plugin do kit diz ao agente quando reportar; o guia inteiro vem de
  `cadex skills get orchestration`.

### Portões
- orchestration.add-gate marca uma tarefa para só ficar pronta quando o dono aprovar. O portão
  aparece no quadro com o que as dependências entregaram (resumos e diffs), e "Approve"
  (orchestration.approve-gate) ou "Reject" (orchestration.reject-gate, com o motivo, deixa a tarefa
  bloqueada). Nenhum agente aprova portão: o comando não está na lista do agente.

### A página da execução
- orchestration.show-run abre a página: o grafo das tarefas (cada uma com estado e o despacho
  atual), a caixa de entrada, os portões abertos, o gasto e o tempo contra o teto. Cada despacho
  leva à aba dele. A página só lê o banco enquanto está aberta, e as mudanças chegam pelos hooks e
  pelos reportes, sem timer.
- orchestration.stop-run para todos os despachos da execução, com confirmação.

### Automações
- "New Automation" (orchestration.new-automation): nome, prompt, recorrência (dias úteis a uma hora,
  todo dia a uma hora, a cada N horas, uma vez numa data), destino (uma worktree nova a cada
  execução, ou uma pasta fixa), conta, modelo, modo de permissão e ferramentas permitidas, teto de
  gasto e de duração, assinatura ou chave de API (a chave é do `apiKeyHelper` da conta; o Cadex só
  diz se a conta tem um), e o que fazer com uma execução perdida (rodar ao acordar, o padrão, ou
  pular). Nasce desligada; orchestration.toggle-automation liga e desliga. Só neste Mac.
- A primeira automação ligada instala o LaunchAgent (o macOS avisa do item em segundo plano, e a
  folha diz isso antes); desligar a última, ou orchestration.automations, o remove (ADR 0034).
- No horário, com o Cadex aberto, a aba abre na janela principal sem trazê-la para a frente; com o
  Cadex fechado, ele abre em segundo plano e a aba fica lá. Enquanto roda, o computador não dorme
  (orchestration.keepAwakeDuringRuns, ligada, pela feature `power`).
- Sem ninguém olhando valem o modo de permissão e as ferramentas da automação; o que ainda pedir
  permissão vai ao quadro "Precisa de você" e à notificação (`docs/spec/agents.md`), e a execução
  espera até o dono responder ou até o teto de duração, marcada "stopped waiting".
- Passou do teto de gasto ou de duração: o agente é encerrado e a execução fica "hit the cap".
- "Run Now" (orchestration.run-automation-now) roda fora do horário, com o mesmo teto.
- O histórico (orchestration.show-automation-history): uma linha por execução com início, fim,
  custo, resultado (done, failed, hit the cap, stopped waiting, skipped) e o link para a sessão (vai
  à aba, ou retoma pelo History) e para o transcript.
- Ao terminar ou falhar, a notificação do plano 19 (Finished, ou o motivo da falha).

### Em outra máquina
- Só a corrida aceita outra máquina, pelo "Run on" mínimo (`docs/adr/0031-run-on-remote.md`): o
  agente roda lá, com o login de lá, e o estado vem do `claude agents --json` por ssh, só com o
  quadro aberto. Sem reporte, sem custo (fica "—") e sem conferência de confiança: o diálogo de
  confiança, se houver, aparece na aba. Despacho, reporte e automação remotos dependem do `cadexd`.

### Configurações
- orchestration.toggle liga e desliga orchestration.enabled, e orchestration.toggle-automations,
  orchestration.automations (as duas pela folha de "Ligar").
- orchestration.enabled (desligada), orchestration.automations (desligada),
  orchestration.maxAgents (6), orchestration.maxDepth (2), orchestration.heartbeatMinutes (10),
  orchestration.keepAwakeDuringRuns (ligada), orchestration.defaultBudgetUsd (5) e
  orchestration.defaultMaxMinutes (60), o teto que uma execução nova propõe.

### O estado
- Corridas, execuções, tarefas, despachos, mensagens, automações e o histórico ficam num SQLite do
  sistema em `~/Library/Application Support/Cadex/orchestration/state.sqlite`, com o id da sessão
  e o caminho do transcript de cada despacho. Aberto só com a feature ligada.
- Todo agente da feature roda numa aba; `claude --bg` fica de fora até um teste mostrar que os
  hooks e a status line do kit chegam a uma sessão em segundo plano (fase B, 2026-11-16).

## Estados
- **Desligada**: o ⌘K mostra só "Turn On Agent Orchestration"; a página explica e oferece ligar.
- **Nenhuma corrida, execução ou automação**: "No races or runs yet" com "New Race" e "New Run".
- **Esperando a confiança**: a execução não começou; a linha diz por quê e tem "Open Claude to
  Trust".
- **No teto de agentes**: um despacho a mais espera na fila, "waiting for a free slot (6 of 6)".
- **Parado?**: despacho sem sinal de vida, em amarelo, com "Go to Terminal" e "Stop".
- **Erro ao criar a worktree**: o concorrente ou o despacho fica "failed to start" com o erro do
  `git`, e os outros seguem.

## Casos de borda
- Conta sem login, ou com o limite de uso batido: o agente falha na aba; o despacho fica "failed"
  com o erro, e a corrida segue com os outros.
- O app fecha no meio de uma execução: com terminal.keepSessions, os agentes seguem e reportam ao
  app reaberto (o token vale, ADR 0022); sem ele, os agentes saem com o app, e os despachos ficam
  "exited without reporting".
- Dois `report-done` do mesmo despacho: o segundo é ignorado e respondido "already done".
- `spawn` acima da profundidade ou do teto de agentes: recusado com o motivo, e o agente recebe a
  recusa na saída do `cadex`.
- Um despacho de uma execução tenta reportar em outra (outro CADEX_DISPATCH_ID): recusado.
- Worktree de um concorrente apagada por fora: a coluna diz "worktree gone" e sai do "Compare".
- Automação vencida com a anterior da mesma automação ainda rodando: a nova é pulada ("still
  running").
- Mac desligado no horário: na próxima abertura do app, a regra da execução perdida vale.
- Prompt enorme (mais de 100 KB): recusado antes de abrir, pelo limite de argumento do sistema.

## Critérios de aceite
- [ ] Com orchestration.enabled desligada, nenhum agente é aberto com prompt, nenhum banco aberto,
      nenhum timer e nenhum LaunchAgent (`ps`, `lsof`, `launchctl print`).
- [x] Testes do modelo com banco temporário: dependências tornando tarefas prontas, ciclo recusado,
      profundidade máxima, despacho órfão (o agente saiu sem reportar). (OrchestrationTests,
      2026-11-16, com portões, parar em cadeia, teto de agentes e a caixa de entrada.)
- [ ] Uma corrida de 3 num repositório de teste cria 3 worktrees do mesmo commit, 3 abas com o
      prompt e o quadro com os três estados e custos; "Compare" mostra o diff entre duas; escolher o
      vencedor manda as outras worktrees para a Lixeira e deixa as branches.
- [ ] Uma execução de 3 tarefas encadeadas, com agentes reais, vai de pendente a concluída sozinha;
      um portão segura a terceira até a aprovação; parar o pai encerra os filhos; um agente sem
      sinal de vida aparece como "stalled?".
- [ ] Um prompt com aspas, `$()`, crase e quebra de linha chega intacto ao agente e nada é executado
      pelo shell (no Mac e no remoto).
- [ ] Os comandos de reporte só são aceitos de uma sessão com CADEX_DISPATCH_ID e só sobre a
      execução dela; approve-gate pela CLI é recusado.
- [ ] Uma automação a cada 2 minutos roda com o Cadex fechado (o LaunchAgent abre o app em segundo
      plano), para no teto e aparece no histórico com o link certo.
- [ ] Um pedido de permissão sem ninguém vai ao quadro e a execução para no teto de duração.
- [ ] Com o Mac dormindo no horário, a automação roda ao acordar (ou é pulada, se assim marcada).
- [ ] Desligar a última automação remove o LaunchAgent.
- [ ] `fs_usage` e `nettop` não mostram o Cadex lendo o Keychain nem falando com a Anthropic.
- [ ] `make perf`: com tudo desligado, os números de antes; 6 agentes falsos, uma corrida de 3 e uma
      execução de 5 tarefas dentro do limite.
