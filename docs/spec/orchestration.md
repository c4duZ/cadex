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

### As páginas da execução e da automação (plano 30 B)
- Na cara da moldura nova, como a página do projeto: o nome grande, a pasta e quem coordena (ou a
  agenda, onde e em qual conta), os botões à direita; a execução com o gasto contra o teto e cada
  tarefa num cartão com a peça de estado, recuado um passo à direita do que espera, com o que falta,
  o último despacho ("stalled?" em âmbar), o portão e as ações; a caixa de entrada em cartões; a
  automação com Turn on/off, Run now e cada rodada num cartão. A barra de título diz "projeto › run
  <nome>" na execução.

### O quadro (mockup Board; plano 30 B, feito junto da revisão do plano 29)
- view.board, o Quadro no pé da barra lateral e na faixa da janela estreita e o clique no item
  Agents da barra de baixo abrem a página "Board" com a barra lateral aberta, como toda página;
  "Fechar (Esc)" no topo, view.board de novo ou o Esc voltam à aba de antes (até 2026-11-20 o quadro
  fechava a barra lateral e o Esc era a única saída, sem nada dizendo; o dono).
- Além das tarefas, cada agente rodando na pasta do próprio projeto (o main) é um cartão; o clique
  vai ao terminal dele.
- As tarefas de todos os projetos da janela em quatro colunas: Needs you (pede permissão ou
  resposta, ou falhou), Working, In review (a tarefa em revisão) e Done; a parada fica de fora.
  Cada cartão: o estado, o nome, a idade, o que faz ou espera ("Wants to run Bash: make perf"),
  "projeto · agente", o +/− e a etiqueta da corrida, execução ou automação a que pertence.
- Pílulas de filtro: All, cada corrida e execução com a contagem, Automations; New race e New task.
- Responsivo: 4 colunas, 2 ou 1 pela largura; as pílulas quebram a linha e os botões sobem.

### Corrida
- A corrida no centro (mockup Race): os concorrentes locais lado a lado numa aba "Contenders · N",
  com a faixa do pedido, de onde partiu e o teto, e "Compare…"; cada um com o cabeçalho "#1 Claude
  Opus · conta · tempo", a linha do estado, custo e diff e a barra do teto (âmbar acima de 80%), e o
  pé com Review e Pick winner. A barra de título diz "projeto › race <nome>" e termina em
  "Compare". orchestration.show-race leva aos concorrentes; o quadro de colunas antigo fica só para
  a corrida sem nenhum concorrente local.
- A corrida nasce na folha "New task" (`worktrees.md`) com dois agentes ou mais: não há folha
  própria (`../adr/0035-work-frame.md`). worktrees.new-race abre a folha já com duas linhas de
  agente; com a feature desligada, a folha diz numa linha que o Começar a liga (o
  comando não fica indisponível). O que a
  folha pede para a corrida: o prompt, o ponto de partida (o branch atual, ou outro), e
  de 2 a orchestration.maxAgents concorrentes, cada um com conta, modelo e máquina (este Mac, ou uma
  remota pelo "Run on" mínimo, `docs/spec/worktrees.md`). Um concorrente pode ser o Codex de uma
  conta (~/.codex ou ~/.codex-*): o pedido vai pelo `cadex codex` (o mesmo arquivo e as mesmas
  regras do `cadex claude`), sem pedir confiança ao Claude Code; como o Codex não relata estado nem
  custo ao Cadex, o quadro o mostra trabalhando enquanto o programa roda e o teto dele é só o tempo
  (a folha avisa). Cria uma worktree por concorrente pelo
  New Task da feature worktrees, todas do mesmo commit, com os nomes `<tarefa>-1` … `<tarefa>-N`,
  e abre uma aba por concorrente com o prompt.
- A corrida abre no centro (orchestration.show-race; `../design/work-frame/screens.md`, seção
  Race; tokens components.race), com as abas "Contenders" e "Compare" na barra de título e, acima
  das colunas, o pedido, o ponto de partida e o teto. Uma coluna por concorrente com o estado
  (trabalhando, esperando você, terminou, saiu; no remoto, o do `claude agents --json`), o tempo, o
  custo (o `cost` da sessão gravado pelo `cadex statusline`), e o resumo do diff contra o ponto de
  partida (arquivos, +/−). Clicar numa coluna vai ao terminal dela; "Review" abre a revisão daquela
  worktree (`docs/spec/review.md`).
- "Compare" escolhe duas colunas e abre o diff entre as duas worktrees
  (git.review-compare-worktrees).
- "Pick Winner" (orchestration.pick-winner): o vencedor segue como uma tarefa normal da worktrees.
  Em seguida, "Discard the Others" (orchestration.discard-race) apaga as outras worktrees, direto,
  sem a Lixeira (o dono, 2026-11-16), depois de encerrar os agentes delas, e mantém as branches com
  os commits; o que nunca teve commit nelas se perde, e a confirmação diz isso;
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
- De onde parte (2026-11-16, fase D1): a folha do despacho oferece a branch da dependência
  concluída mais recente (o trabalho dela está lá), as outras dependências concluídas e a branch do
  repositório; a worktree se chama `<execução>-<tarefa>`.
- No teto de agentes (orchestration.maxAgents, corridas e execuções juntas), o despacho pedido
  espera na fila da tarefa, "waiting for a free slot (6 of 6)", e começa sozinho quando um agente
  termina, o mais antigo primeiro; "Stop Waiting" (ou orchestration.stop-dispatch) o tira da fila.
- Dependências mudadas depois (orchestration.set-dependencies), só numa tarefa pendente, pronta ou
  bloqueada: a que fecharia um ciclo é recusada dizendo o ciclo pelos títulos ("a → c → b → a").
- A folha do despacho mostra o prompt inteiro (rolável), a conta, o modelo, o modo de permissão, a
  branch de partida ou o terminal parado escolhido, e o teto da execução. Sem confiança na conta,
  "Open Claude to Trust" abre uma aba com o `claude` dela no repositório.
- Com o dono coordenando, "Mark Done" (orchestration.mark-done) é a palavra dele de que o trabalho
  ficou pronto: a tarefa fica concluída e as que dependiam dela podem ficar prontas. Vale também
  sobre a última tentativa que falhou ("exited without reporting": o agente saiu antes do clique).
  O `report-done` do próprio agente vem com os agentes supervisionados (fase D2).
- Teto da execução: o gasto é a soma do custo de cada despacho (o último que a status line gravou),
  e o tempo é o tempo com pelo menos um agente trabalhando (a união dos intervalos), não o tempo
  desde a criação: uma execução preenchida ao longo do dia bateria no teto antes de qualquer agente
  (decidido em 2026-11-16). Passou de um dos dois, todos os despachos vivos param e a execução fica
  "hit the cap", sem aceitar despachos novos.
- New Run escolhe quem coordena: o dono despachando cada tarefa, o dono com as tarefas prontas
  começando sozinhas (na conta e modelo escolhidos na folha), ou um agente: o Claude abre numa aba
  no repositório com o objetivo do dono como prompt (por arquivo, nunca pelo shell) e cria as
  tarefas pelo `spawn`; as dele começam sozinhas como a conta escolhida. Uma tarefa parada pelo
  dono não começa sozinha de novo: o dono a despacha (2026-11-16, D2). Uma que não consegue
  começar sozinha (sem confiança, especificação grande…) fica "falhou" com o motivo.
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
- `spawn` aceita também `after=<ids ou títulos>` (espera por elas) e `gate=yes` (o dono aprova antes);
  a sub-tarefa roda como o agente que a pediu, ou como a conta da execução quando é o coordenador.
- O coordenador agente lê a caixa dele (as perguntas dos agentes e como cada tarefa terminou),
  responde com `send-message to=<despacho> answers=<pergunta> text=…` e tenta de novo uma tarefa
  que falhou com `cadex run orchestration.retry task=<id>`. Parar a execução encerra também ele.
- Cada hook da sessão de um despacho é sinal de vida, como os reportes.
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
- orchestration.show-run abre a página no centro (também pelo filtro "Run" do quadro, na cara da
  moldura nova, plano 30): o grafo das tarefas (cada uma com estado e o despacho
  atual), a caixa de entrada, os portões abertos, o gasto e o tempo contra o teto. Cada despacho
  leva à aba dele. A página só lê o banco enquanto está aberta, e as mudanças chegam pelos hooks e
  pelos reportes, sem timer.
- orchestration.stop-run para todos os despachos da execução, com confirmação.

### Automações
- A página Automações (orchestration.show-automations, o Automações do pé da barra lateral; plano
  34 F) sempre abre. Vazia, a área inteira diz o que é uma automação, dá um exemplo e põe "Criar
  automação" no meio; com as automações desligadas, avisa que criar a primeira as liga (a mesma
  pergunta de orchestration.toggle-automations). Com itens, uma tabela: a chave de ligar na linha, o
  nome, quando, o projeto, a conta, a última rodada e a próxima; o clique abre as rodadas e o botão
  direito tem Executar agora, Ligar ou desligar e Apagar (a automação e o registro das rodadas).
  Criar volta à tabela, com a nova desligada.
- "New Automation" (orchestration.new-automation): nome, prompt, recorrência (dias úteis a uma hora,
  todo dia a uma hora, a cada N horas, a cada N minutos, uma vez numa data), destino (uma worktree nova a cada
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
- O modo de permissão escolhido vai sempre ao `claude` (`--permission-mode=default` também): sem
  ele valia o modo da conta, e o "auto mode" do Claude Code aprovou sozinho um comando que ninguém
  viu (2026-11-16). As ferramentas permitidas vão numa palavra só (`--allowedTools=a,b`), porque a
  opção aceita vários valores e engoliria o prompt.
- O app confere a agenda ao abrir, ao acordar o Mac e quando o job pede (`cadex automations due`,
  o pedido sem token no `app.sock`); com o app fechado, o job abre o Cadex em segundo plano
  (`open -g` no app empacotado; numa instância de teste, o executável com CADEX_BACKGROUND=1 e as
  pastas dela, passadas pelo plist). Um horário atrasado mais de 2 minutos é uma execução perdida.
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
- Corridas, execuções, tarefas, despachos, mensagens e o histórico das automações ficam num SQLite
  do sistema em `~/Library/Application Support/Cadex/orchestration/state.sqlite`, com o id da sessão
  e o caminho do transcript de cada despacho. Aberto só com a feature ligada.
- As automações (o que roda e quando) são configuração e ficam em texto: um JSON por automação em
  `~/Library/Application Support/Cadex/orchestration/automations/<id>.json`, com as chaves em
  ordem e as datas em ISO 8601, para o dono ou um agente lerem e editarem (o dono, 2026-11-22). O
  nome do arquivo é o id. Criar, mudar ou apagar um arquivo com o Cadex aberto vale na hora: a página
  se refaz e o agendamento do launchd segue as ligadas. Arquivo que não lê fica fora, com o motivo
  no log, e os outros valem. As automações de um banco antigo viram arquivos uma vez, ao abrir.
  O formato de cada campo está em `../guides/settings.md`.
- Todo agente da feature roda numa aba; `claude --bg` fica de fora até um teste mostrar que os
  hooks e a status line do kit chegam a uma sessão em segundo plano (fase B, 2026-11-16).

## Estados
- **Desligada**: o ⌘K mostra só "Turn On Agent Orchestration"; a página explica e oferece ligar.
- **Nenhuma corrida, execução ou automação**: o quadro (`../design/work-frame/screens.md`, seção
  Board) mostra "No races or runs yet" com "New race" (a folha New task com dois agentes) e "New run".
  As corridas e as execuções são filtros do quadro, que mostra todas as tarefas por estado.
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
- Concorrente numa máquina remota cuja pasta do repositório o Cadex ainda não conhece (nenhuma
  tarefa feita lá pelo "Run on"): a coluna fica "Failed to start", dizendo para criar uma tarefa lá
  antes; os outros seguem.
- O arquivo do prompt que nenhuma aba pegou (o app fechou antes) sai depois de um dia.

## Critérios de aceite
- [x] Com orchestration.enabled desligada, nenhum agente é aberto com prompt, nenhum banco aberto,
      nenhum timer e nenhum LaunchAgent (`ps`, `lsof`, `launchctl print`). (`make perf`, 2026-11-16:
      nenhum arquivo na pasta do estado nem na dos LaunchAgents, nenhum job, o peso e a CPU do parado.)
- [x] Testes do modelo com banco temporário: dependências tornando tarefas prontas, ciclo recusado,
      profundidade máxima, despacho órfão (o agente saiu sem reportar). (OrchestrationTests,
      2026-11-16, com portões, parar em cadeia, teto de agentes e a caixa de entrada.)
- [x] Uma corrida de 3 num repositório de teste cria 3 worktrees do mesmo commit, 3 abas com o
      prompt e o quadro com os três estados e custos; escolher o vencedor manda as outras worktrees
      e deixa as branches. (2026-11-16, instância de teste com o `claude` real; a
      corrida começou pelo gancho de teste, sem o formulário.)
- [x] "Compare" mostra o diff entre duas (pelo menu, kite-1 contra kite-2, 2026-11-16).
- [x] "Delete Branches" lista só as branches que restam (uma), apaga e não lista de novo
      (2026-11-16, pelo menu, na instância de teste; o "não lista de novo" com teste).
- [x] "New Race" pela folha de verdade começa a corrida; cancelar a confirmação não deixa corrida
      gravada (2026-11-16).
- [x] Uma execução de 3 tarefas encadeadas, com agentes reais, vai de pendente a concluída sozinha;
      um portão segura a terceira até a aprovação; parar o pai encerra os filhos; um agente sem
      sinal de vida aparece como "stalled?". (D2, 2026-11-16: com o `claude` real na conta bkdg,
      cada agente reportando por `cadex run orchestration.report-done`, a terceira esperando o
      "Approve"; o pai com um filho criado pelo `spawn`, os dois encerrados; o "stalled?" com um
      agente falso calado e o aviso.) (D1, 2026-11-16, na instância de teste com o `claude`
      real: 3 tarefas encadeadas de pendente a concluída, cada uma da branch da anterior, despachadas
      e marcadas pelo gancho de teste como o dono faria; parar, o agente que sai sem reportar e o
      teto da execução; e pelas folhas e botões de verdade, respondidos por gancho com a tela
      bloqueada: New Run, Add Task, as dependências com o ciclo recusado, despachar, a confiança,
      o terminal reaproveitado, a fila, parar, tentar de novo, Mark Done, Go to Terminal, Stop Run
      e o app reaberto no meio.)
- [x] Um prompt com aspas, `$()`, crase e quebra de linha chega intacto ao agente e nada é executado
      pelo shell (no Mac, com o `claude` real; no remoto, com um ssh falso e um `claude` falso).
- [x] Passou do teto de uma corrida, o agente local é encerrado e a coluna diz "hit the cap" (teto de
      1 min, encerrado aos ~61 s, 2026-11-16).
- [x] Os comandos de reporte só são aceitos de uma sessão com CADEX_DISPATCH_ID e só sobre a
      execução dela; approve-gate pela CLI é recusado. (2026-11-16, pela CLI de verdade com o token
      de uma sessão de despacho: outro CADEX_DISPATCH_ID recusado, approve-gate "not allowed for
      agents", retry de um agente de tarefa recusado, report-done repetido "already done".)
- [x] Uma automação a cada 2 minutos roda com o Cadex fechado (o LaunchAgent abre o app em segundo
      plano), para no teto e aparece no histórico com o link certo. (2026-11-16, instância de teste
      com um LaunchAgent de rótulo próprio: o launchd abriu o app às 22:00:07 e a automação rodou
      numa worktree nova; com agentes falsos, "hit the cap" e "stopped waiting" em 1 min; com o
      `claude` real, a sessão e o transcript certos no histórico.)
- [x] Um pedido de permissão sem ninguém vai ao quadro e a execução para no teto de duração.
      (2026-11-16, com o `claude` real e o modo "default": o `touch` esperou a permissão e a
      execução parou em 1 min, "stopped waiting", sem o arquivo; o quadro é o do plano 19, pelo hook.)
- [x] Com o Mac dormindo no horário, a automação roda ao acordar (ou é pulada, se assim marcada).
      (2026-11-16, simulado com o app fechado e o job descarregado no horário, o mesmo caminho do
      acordar: "rodar ao acordar" rodou uma vez ao abrir, "pular" ficou "skipped: missed". Um sono de
      verdade do Mac falta conferir com o dono.)
- [x] Desligar a última automação remove o LaunchAgent. (2026-11-16: o plist some e o `launchctl
      print` não acha o job; desligar orchestration.automations faz o mesmo, e religar o devolve.)
- [x] `fs_usage` e `nettop` não mostram o Cadex lendo o Keychain nem falando com a Anthropic.
      (`make perf`, 2026-11-16, com o `lsof`, porque o `fs_usage` pede root: com uma corrida de 3 e uma
      execução de 5 agentes, nenhuma conexão de rede do app e nenhum arquivo do Keychain aberto.)
- [x] `make perf`: com tudo desligado, os números de antes; 6 agentes falsos, uma corrida de 3 e uma
      execução de 5 tarefas dentro do limite. (2026-11-16, duas rodadas inteiras: desligado −2 a −3 MB
      do parado, nenhum arquivo nem job; ligado 158 a 161 MB e 1,4 a 1,5% de CPU, todos os agentes de
      pé, nenhuma rede nem Keychain.)
