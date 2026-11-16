# Plano 24 — Muitos agentes: corrida, orquestração e automações

Depende de: planos 19 a 23 (o remoto só no mínimo do 23 C) · Features: orchestration (nova, só app
macOS), worktrees, agents, agent-tools, source-control, review, machines, power, tabs, sidebar,
settings, command-palette · Decisões: ADR 0033 e ADR 0034 (a escrever na fase A),
`docs/adr/0019-agents-observe-only.md` (revista pela 0033), docs/adr/0021-cadex-managed-accounts.md
(plano 18), docs/adr/0022-terminal-daemon.md e docs/adr/0023-answer-agent-permissions.md (plano
19), docs/adr/0024-agent-tools.md (plano 20), docs/adr/0029-memory-agent.md (plano 22),
docs/adr/0031-run-on-remote.md (plano 23), `docs/adr/0004-clean-rewrite.md`,
`docs/adr/0005-every-action-is-a-command.md`.

## O que eu quero
- Pôr vários agentes trabalhando de uma vez, como no Orca (o dono, 2026-11-14: "automações,
  orquestração, mesma tarefa em três agentes… muito bons"), nativo e leve, sem sair do Cadex.
- **Corrida:** a mesma tarefa em N agentes Claude, cada um na sua worktree, do mesmo ponto de
  partida, com conta e modelo próprios. Lado a lado, com o estado e o diff de cada; o dono compara,
  escolhe o vencedor e descarta os outros. Codex entra quando tiver kit da sessão (plano próprio).
- **Orquestração:** uma Execução com Tarefas que dependem umas das outras, despachadas a agentes
  supervisionados que reportam ao Cadex (feito, sinal de vida, pergunta), com portões em que o
  dono decide antes de seguir.
- **Automações:** um prompt que roda sozinho num horário (dias úteis 09:00, a cada 4 horas), numa
  worktree nova ou fixa, com conta e modelo escolhidos, histórico e teto de gasto, mesmo com o
  Cadex fechado.
- Em outra máquina, só o mínimo do "Rodar em" do plano 23: o agente roda lá e o estado vem do
  `claude agents --json` por ssh, sem reporte pela CLI. Reporte remoto, despacho remoto e
  automação remota dependem do completo da ADR 0031 (`cadexd`).
- Leve: com nada ligado, custo zero; com 6 agentes em paralelo, o Cadex não é o gargalo.

## O que eu não quero
- Iniciar agente sozinho sem o dono ter ligado: corrida, orquestração e automações vêm desligadas
  (orchestration.enabled, orchestration.automations), e cada execução tem teto de gasto, de duração
  e de agentes.
- Falar com o agente por stream-json ou Agent SDK: o Cadex abre uma aba com `claude` e o prompt
  inicial por argumento, como o dono faria; o motor stream-json fica para depois. Nada de proxy,
  token ou login tocado (ADR 0021).
- Montar o prompt numa string de shell: o prompt vai como argumento do exec (array) ou por arquivo
  lido pelo `claude`, nunca concatenado num comando digitado; vale para o `spawn` de um agente.
- Despachar sem o dono ver: toda Execução e toda automação mostram antes o que vão rodar, onde, em
  qual conta e com que teto; o portão de decisão nunca é pulado.
- Apagar trabalho: worktree descartada vai para a lixeira, a branch fica até o dono confirmar.
- Agente que gera agente sem fim: profundidade máxima de sub-agentes (padrão 2); parar um agente
  para os filhos dele.
- Código do Orca como referência (ADR 0004): só o comportamento descrito na documentação dele.
- Ação só em botão ou arrastar: cada uma é um comando com id (ADR 0005).
- Por enquanto: o Windows, o celular, o motor stream-json, Codex na corrida e o remoto completo.

## Como eu quero
**Fases:**
- **A. ADRs e specs.**
  - ADR 0033 (docs/adr/0033-cadex-launches-agents.md, a criar): o Cadex pode iniciar agentes com
    prompt, nas sessões dele (aba com `claude` e o prompt como argumento, conta pelo
    `CLAUDE_CONFIG_DIR`, kit da sessão dos planos 18–20). Generaliza o que as ADRs 0021 (abrir sem
    prompt) e 0029 (agente de memória) já abriram: revê o "não inicia agente" da ADR 0019 e
    reescreve a linha do `CLAUDE.md` da raiz para: "Modo em blocos e terminal privado ficaram de
    fora. Agentes rodam em abas de terminal; o Cadex os abre com prompt só quando o dono liga
    corrida, orquestração, automação ou o agente de memória, sempre com teto." Amplia a lista de
    comandos permitidos ao agente da ADR 0024 com os de reporte (report-done, report-heartbeat,
    ask, send-message, spawn), dizendo o porquê. Termos: cita a posição da ADR 0029 (uso
    automatizado da assinatura é zona cinzenta pelos Consumer Terms §3(7); desligado por padrão,
    com teto, chave de API sugerida) e acrescenta só a separação por caso: corrida e orquestração
    disparadas pelo dono são o `claude` sem modificação numa aba, o caso que a página de legal and
    compliance aceita; automação por horário é o caso automatizado da 0029 (a automação nova
    sugere `apiKeyHelper`, e usar a assinatura é escolha explícita do dono, por automação).
  - ADR 0034 (docs/adr/0034-scheduled-automations.md, a criar): automações rodam **no app**, não
    no daemon do terminal (a ADR 0022 não muda): um LaunchAgent do launchd, instalado só quando a
    primeira automação é ligada e removido com a última, abre o Cadex em segundo plano no horário
    (sem janela na frente); o app monta o kit, abre a aba e registra a execução; com o Mac
    dormindo, a execução perdida roda ao acordar (ou é pulada, por automação); a feature `power`
    pode manter acordado durante a execução. Sem servidor fora da máquina.
  - Specs: docs/spec/orchestration.md (a criar, modelo do `docs/spec/README.md`);
    docs/spec/worktrees.md (plano 19) e `docs/spec/agents.md` atualizadas. Termos Corrida,
    Execução, Tarefa, Despacho, Portão, Automação no `docs/CONTEXT.md`.
  - Escrita em 2026-11-16: `docs/adr/0033-cadex-launches-agents.md`,
    `docs/adr/0034-scheduled-automations.md`, `docs/spec/orchestration.md`; worktrees, agents,
    agent-tools e power nas specs; os termos no `docs/CONTEXT.md` (Corrida, Concorrente, Execução,
    Despacho, Agente supervisionado, Portão, Automação, Execução perdida, Teto); a linha da raiz e
    os cabeçalhos das ADRs 0019 e 0024. Decidido além do texto do plano:
    - o prompt vai a um arquivo 0600 do Cadex e a aba roda `cadex claude --cadex-prompt-file`, que
      o lê, apaga e passa como um elemento do argv; no remoto, um `ssh` à parte grava o texto num
      `mktemp` de lá e a aba roda `claude "$(cat <caminho>)"` (o texto nunca entra no comando);
    - a lista do agente ganha também orchestration.inbox (ler a própria caixa), sem a qual o `ask`
      e o `send-message` não têm volta: seis comandos, não cinco;
    - o LaunchAgent é um plist escrito pelo app com `StartCalendarInterval` (sem `KeepAlive` nem
      `StartInterval`), carregado por `launchctl bootstrap`; o job roda `cadex automations due`,
      que pede ao app pelo app.sock (pedido sem token, só `getpeereid`, que não diz o que rodar)
      ou abre o app em segundo plano; o SMAppService ficou de fora porque o plist dele é fixo no
      bundle;
    - comandos que o plano não nomeava: orchestration.add-task, orchestration.show-run,
      orchestration.stop-run, orchestration.toggle e orchestration.toggle-automations; e as
      configurações orchestration.heartbeatMinutes (10), orchestration.keepAwakeDuringRuns
      (ligada), orchestration.defaultBudgetUsd (5) e orchestration.defaultMaxMinutes (60).
- **B. Feature `orchestration` e o estado.** Feature nova só no app macOS
  (apps/macos/features/orchestration/, a criar, com `CLAUDE.md` e linha na tabela da raiz),
  porque corrida, execuções e automações são um modelo próprio que usa worktrees, agents e
  agent-tools pelas portas de entrada delas, sem importar o miolo; contribui ao kit da sessão
  (apps/macos/shared/session-kit/, plano 18) a variável CADEX_DISPATCH_ID. O estado vive em SQLite
  do sistema em `~/Library/Application Support/Cadex/orchestration/state.sqlite` (a criar):
  corridas, execuções, tarefas, despachos, mensagens, automações e o histórico, com o id da sessão
  e o caminho do transcript (plano 18) de cada despacho. Puro e testado com banco temporário. Se o
  Windows precisar, o modelo desce para o núcleo. Configurações orchestration.enabled (desligada),
  orchestration.automations (desligada), orchestration.maxAgents (padrão 6),
  orchestration.maxDepth (padrão 2).
- **C. Corrida: a mesma tarefa em N agentes.**
  - "Nova corrida" (orchestration.new-race): prompt, ponto de partida, N concorrentes Claude
    (conta, modelo, e máquina pelo mínimo do "Rodar em" do plano 23). Cria N worktrees pelo
    worktrees.new-task do plano 19 (nomes `<tarefa>-1…N`) e abre uma aba por concorrente com o
    prompt.
  - O quadro da corrida (orchestration.show-race): uma coluna por concorrente com estado (hooks do
    plano 19; no remoto, `claude agents --json`), tempo, custo (o `cost` por sessão que o
    `cadex statusline` grava, plano 18) e o resumo do diff; "Comparar" abre o diff entre duas
    worktrees da revisão do plano 21 (git.review-compare-worktrees).
  - "Escolher vencedor" (orchestration.pick-winner): o vencedor segue como worktree normal;
    orchestration.discard-race manda as outras worktrees para a lixeira e mantém as branches até
    orchestration.delete-race-branches, com confirmação.
  - Features: orchestration, worktrees, agents, source-control, tabs.
- **D. Orquestração: execuções, tarefas e despachos.** Em duas partes, cada uma numa sessão:
  **D1** o modelo e o despacho (execução, tarefas, dependências, despacho, parar), com o dono como
  coordenador e a página da execução; **D2** os agentes supervisionados (os comandos de reporte
  pela CLI, sinal de vida, mensagens, sub-tarefas, portões e o coordenador sendo um agente).
  - Execução (orchestration.new-run): nome, coordenador (uma sessão de agente ou o próprio dono) e
    caixa de entrada. Tarefas com especificação, dependências e estado: pendente, pronta,
    despachada, concluída, falhou, bloqueada. Uma tarefa fica pronta quando as dependências
    terminam.
  - Despacho (orchestration.dispatch): uma tentativa de uma tarefa numa worktree e aba novas (ou
    num terminal reaproveitado), só neste Mac, com a especificação como prompt inicial (argumento
    ou arquivo, nunca string de shell) e CADEX_DISPATCH_ID na aba pelo kit. Nova tentativa só pelo
    dono ou pelo coordenador (orchestration.retry), registrando a anterior.
  - O agente supervisionado reporta pela CLI `cadex` do plano 20, como comandos registrados (na
    lista permitida pela ADR 0033): `cadex run orchestration.report-done`, `…report-heartbeat`,
    `…ask` (pergunta ao coordenador ou ao dono), `…send-message` (para outro despacho da mesma
    execução), `…spawn` (sub-tarefa, até orchestration.maxDepth; o texto vira arquivo, não
    comando). Sem sinal de vida por N minutos, o despacho fica "parado?" e avisa.
  - Portões (orchestration.add-gate): uma tarefa que só fica pronta quando o dono aprova no quadro
    (orchestration.approve-gate, orchestration.reject-gate).
  - Parar (orchestration.stop-dispatch): encerra o agente e os despachos filhos dele.
  - Uma skill curta no plugin do kit (plano 20) ensina o agente a reportar; o guia completo sai do
    binário (`cadex skills get orchestration`).
  - A página da execução: grafo das tarefas, caixa de entrada, portões; cada despacho leva à aba.
  - Features: orchestration, agent-tools, worktrees, agents, tabs.
- **E. Automações agendadas.**
  - Automação (orchestration.new-automation): nome, prompt, recorrência (dias úteis 09:00, a cada
    N horas, uma vez), destino (worktree nova a cada execução ou uma fixa), conta, modelo, modo de
    permissão e lista de ferramentas permitidas, teto de gasto e de duração, assinatura ou chave
    de API. Nasce desligada (orchestration.toggle-automation). Só neste Mac.
  - Sem ninguém olhando: o modo de permissão e a lista de ferramentas da automação valem; o que
    ainda pedir permissão vai ao quadro "Precisa de você" e à notificação (plano 19), e a execução
    espera até o dono responder ou para no teto de duração, marcada como "parou esperando".
  - "Executar agora" (orchestration.run-automation-now); histórico de execuções com início, fim,
    custo, resultado e link para a sessão e o transcript (orchestration.show-automation-history).
  - O app aberto pelo LaunchAgent (ADR 0034) abre a aba da execução; com o Cadex fechado, ele abre
    em segundo plano e a aba fica lá. Uma execução que passa do teto é parada e marcada.
  - Notificação ao terminar ou falhar (os mesmos tipos do plano 19).
  - Visto em 2026-11-14 (2.1.325), para as fases C a E:
    - `claude "<prompt>"` interativo, com o prompt como argumento de exec, passa aspas, `$HOME`,
      crases, `;`, `&&`, `|` e quebras de linha intactos, e o turno começa sozinho.
    - Pasta nunca confiada: o interativo segura o prompt no diálogo de confiança e o `claude --bg`
      sai com erro ("Workspace not trusted"); a confiança é herdada pelas pastas filhas, então a
      aceitação única em `<repo>.worktrees/` (plano 19 D) destrava corrida, orquestração e
      automações. Antes de rodar, o Cadex confere a pasta; sem confiança, a execução não começa e
      avisa o dono, em vez de parar no diálogo.
    - `claude --bg` + `claude agents --json` (estado `working`/`blocked`, `waitingFor`) +
      `claude attach <id>` é um jeito de rodar e acompanhar execuções sem aba aberta; a página
      Agents já mostra essas sessões e abre cada uma com `attach` (feito em 2026-11-14,
      `apps/macos/features/agents/AgentBackground.swift`). A escolha entre aba e `--bg` por
      execução fica para a fase B.
  - Features: orchestration, worktrees, power, agents, settings.
- **F. Peso e fechamento.** Cenário novo no `tools/perf/run.py`: 6 agentes falsos em paralelo
  (programas que imitam os hooks do plano 19 e reportam pela CLI), uma corrida de 3 e uma execução
  com 5 tarefas; limite de memória e CPU do Cadex com o quadro aberto, e com orchestration.enabled
  desligado os números de antes (nenhum banco aberto, nenhum timer, nenhum LaunchAgent). Os ids
  novos em `MAC_ONLY` de `tools/check_command_parity.py`. README e notas da release em inglês.

## Como validar
- `make check` passa a cada fase, com os ids novos aceitos pelo `tools/check_command_parity.py`.
- Fase A: a ADR 0033 cita a 0019, a 0021, a 0024 (lista ampliada) e a 0029 (termos); a 0034 diz
  que roda no app e não muda a 0022; spec com critérios; `make manifests` passa.
- Fase B: testes do modelo (dependências tornando tarefas prontas, ciclo de dependência recusado,
  profundidade máxima, despacho órfão) com banco temporário.
- Fase C: uma corrida de 3 num repositório de teste cria 3 worktrees do mesmo ponto, 3 abas com o
  prompt e o quadro com os três estados e custos; "Comparar" mostra o diff entre duas; escolher o
  vencedor manda as outras worktrees para a lixeira e deixa as branches.
- Fase D: uma execução de 3 tarefas encadeadas, com agentes reais, vai de pendente a concluída
  sozinha; um portão segura a terceira até a aprovação; parar o pai encerra os filhos; um agente
  sem sinal de vida aparece como "parado?"; um prompt com aspas, `$()` e quebra de linha chega
  intacto e nada é executado pelo shell.
- Fase E: uma automação a cada 2 minutos roda com o Cadex fechado (o LaunchAgent abre o app em
  segundo plano), para no teto, e aparece no histórico com o link certo; um pedido de permissão
  sem ninguém vai ao quadro e a execução para no teto de duração; com o Mac dormindo, roda ao
  acordar; desligar a última automação remove o LaunchAgent.
- Termos: nenhuma execução sem o dono ter ligado a feature; `fs_usage` e `nettop` não mostram o
  Cadex lendo o Keychain nem falando com o serviço da Anthropic.
- `make perf` na fase F: com tudo desligado, os números de antes; com 6 agentes, dentro do limite.
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`).
