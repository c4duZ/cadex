# agents (app macOS)

## O que eu quero
- Ver os agentes de código rodando em todas as contas do Claude Code deste Mac: as sessões vivas por
  projeto, o estado (trabalhando, esperando você), os subagentes, e ir ao terminal de cada uma
  (plano 17, fase C; `../../../../docs/spec/agents.md`).
- O uso de cada conta sem token, contas criadas e geridas pelo Cadex com a configuração do ~/.claude
  por link, e o histórico de todas as conversas, com retomar e continuar em outra conta (plano 18,
  `../../../../docs/adr/0021-cadex-managed-accounts.md`).

## O que eu não quero
- Mandar prompt ou falar com agente, nem mexer nos arquivos do Claude Code: só ler
  (`../../../../docs/adr/0019-agents-observe-only.md`). O que o Cadex inicia é digitar um comando
  num terminal, sem prompt e com o kit da sessão (ADR 0021): abrir o agente de uma conta, retomar
  uma conversa e continuá-la em outra conta. O que ele escreve fica nas pastas que ele cria (contas
  gerenciadas, o kit, o uso, o índice); nas contas, só os links que o dono pede, e o que sai vai para
  a lixeira, nunca apagado.
- Ler, guardar ou repassar token, login ou credencial, ou chamar o serviço de uso: nunca (ADR 0021).
- Ler ou vigiar alguma coisa com ninguém olhando, ou com agents.sessions desligado.
- Ler os logs das conversas além do necessário: o registro de cada sessão, as descrições dos
  subagentes, o fim do log numa parada, a conversa de um subagente enquanto a aba dela está aberta e,
  para o histórico, só o que cada conversa cresceu, com a página aberta, sem nunca guardar resultado
  de ferramenta.
- Travar ou mostrar erro porque uma versão nova do Claude Code mudou um arquivo: pula e conta.

## Como eu quero
- `AgentSessions.swift`: o modelo e a leitura, puros e testados com uma pasta pessoal falsa.
  `AgentAccount` (~/.claude e as ~/.claude-* com .claude.json; nome da organização, ou a pasta
  quando é só "x's Organization"; nomes iguais ganham a pasta), `AgentSession` (o
  sessions/<pid>.json de cada conta com o processo vivo: busy é trabalhando, idle é esperando),
  `AgentProject` (o .git acima da pasta, worktree também, e o branch lido do HEAD, sem rodar git) e
  `AgentSubagent` (os .meta.json da pasta de subagentes da sessão; terminado pelo `finished` que o
  Claude Code escreve ao fim; arquivo antigo, sem `finished` nem `spawnDepth`, cai na estimativa de
  "o log mudou nos últimos 30 s"; 10 min sem escrever encerra de qualquer jeito).
- `AgentProjectFolder.swift`: a pasta de conversas de uma pasta de trabalho dentro de projects/,
  pela regra do Claude Code (todo caractere que não é letra ou número ASCII vira "-"; acima de 200,
  os 200 primeiros + "-" + hash em base 36), com busca pelo prefixo se o hash não bater. Uma regra
  só para subagentes, conversa do subagente e o fim do log (`AgentStop`); antes só "/" e "." viravam
  "-" e pastas com espaço, "_" ou acento perdiam subagentes e o motivo da parada (2026-11-14).
- `AgentBackground.swift`: as sessões em segundo plano (agent view, `claude --bg`) que rodam
  (trabalhando ou "blocked", que espera você), pelo `claude agents --json` da conta, a interface que
  a doc do Claude Code suporta (a pasta jobs/ é interna), filtradas por `liveJobs` (o job entre os
  `workers` do daemon/roster.json com processo vivo; os estacionados ficam fora, 2026-11-14) e uma
  por job (`distinct`, a conta que tem a conversa). Custa 0,15 s de CPU por chamada: roda só
  quando a pasta jobs/ de uma conta muda, no máximo a cada 5 s, fora da linha principal; sem o
  binário `claude` (~/.local/bin, /opt/homebrew/bin, /usr/local/bin), nada. O ambiente perde
  CLAUDECODE e CLAUDE_CODE_*.
- `AgentsController.swift`: a porta de entrada, uma para o app (`shared`). `watch` liga a leitura
  e `stop` desliga; sem ninguém, nenhum FSEvents e nenhum timer. Vigia por FSEvents com eventos
  por arquivo as pastas sessions e jobs das contas e a de subagentes da sessão aberta; a cada 10 s
  confere quem ainda está vivo (um agente que caiu não avisa) e acha pasta sessions nova. As sessões
  em segundo plano entram na mesma lista (`job`, `waitingFor`). `isEnabled` é o agents.sessions.
- O título do grupo de um projeto mostra o status e o comentário da tarefa dele (`projectNote`,
  que o app pede à feature worktrees).
- Sessões em outra máquina (plano 23, "Rodar em"): AgentBackground.parseRemote lê o `claude
  agents --json` de lá (interativas e em segundo plano; o formato das interativas não foi visto numa
  sessão real ainda), AgentSession.machine e a linha "· em pc"; o controller recebe a lista em
  `remote`, e `pageShown`/`onWatching` dizem ao app quando uma página Agents está na tela (o notifier
  vigia o controller sempre, então vigiado não é olhado).
- `AgentsLayout.swift`: grupos por projeto (o mais recente primeiro; esperando antes de
  trabalhando) e a linha de baixo ("main · conta", "esperando você · conta · fora do Cadex", "… ·
  em segundo plano").
- `AgentsView.swift`: a página da barra lateral; lê só enquanto aparece. `AgentSessionList.swift`:
  as sessões, com o logo da conta; clique (ou a seta) abre os subagentes, duplo clique chama
  `onOpen` (o terminal; numa sessão em segundo plano, uma aba nova com `claude attach <job>`, de
  `AgentLaunch.swift:attachCommand`),
  o título do projeto recolhe o grupo. `AgentMotion.swift`: a seta que gira e o `AgentReveal`, que
  desdobra e dobra (altura e opacidade, 0,2 s). `AgentRows.swift`: o sinal (anel girando, ponto
  azul, ✓), a linha clicável que acende ao passar e escurece ao apertar, e os rótulos.
- `AgentStop.swift`: por que uma sessão parou, do fim do log (64 KB, uma vez por parada):
  permissão (ferramenta pedida sem resposta), pergunta (AskUserQuestion, ExitPlanMode), terminou
  (fim de turno), parada por você (o Esc, que não avisa), login vencido (`"error":
  "authentication_failed"`, que marca a conta com AgentUsageController.loginFailed). Numa aba do
  Cadex o motivo vem do próprio agente pelo OSC 7501 (plano 19): AgentStop.fromReport traduz o
  relatório ("approve Bash: x", "answer: …", done) e o app o entrega por AgentNotifier.reportedStop,
  sem ler log; o fim do log fica para sessões em outros terminais. `AgentNotifier.swift` (é também o delegate do centro de notificações do app: o
  clique numa notificação de programa vai a `onOpenTerminal`): a notificação do sistema quando uma sessão passa de
  trabalhando para esperando, por tipo (agents.notifyPermission, -Question, -Finished), lido 1 s depois da
  parada, nunca enquanto você olha o terminal dele; só de dentro de um .app (fora dele a central do sistema para o
  processo). `AgentNotifyText.swift`: as palavras de cada notificação (tipo no
  título, onde no subtítulo, o detalhe no texto), sem imagem. `AgentNotifySound.swift`: o som de cada
  tipo, copiado para ~/Library/Sounds e tocado pelo sistema com a notificação. `forget` tira a
  notificação de uma sessão da Central quando o terminal dela ganha o foco.
- `AgentUsage.swift`: sem token (ADR 0021). `AgentAccountLogin`: o `oauthAccount` do .claude.json
  da conta, só lido (tem login, o plano pelo `organizationType`, e os ids que trazem de volta uma
  conta escondida). `AgentUsageFile`: onde o `cadex statusline` grava o `rate_limits` de cada conta
  (`CADEX_USAGE_DIR` ou Application Support/Cadex/usage, nome por SessionKit.accountKey).
  AgentUsage.parseFile: as porcentagens e os reinícios (segundos ou ISO; janela que já reiniciou é
  0%). `AgentUsageState`: lendo, pronto (com a hora do arquivo; mais de 10 min fica apagado com a
  idade), login vencido, sem login, sem uso ("Abra o agente pelo Cadex").
  `AgentUsageController.swift`: uma leitura para o app, só com Accounts ou o item na tela; vigia a
  pasta de uso (um descritor, o rename de cada arquivo avisa), relê a cada 60 s e lê os logins e os
  logs do Codex a cada 5 min fora da linha principal; uma falha de login vale até uma sessão
  posterior gravar uso. `AgentUsageViews.swift`:
  as barras do cartão (destaque, laranja a partir de 70%, vermelho a partir de 90%) e
  `AgentUsageRows`, as barras que o cartão e o popover dividem. `AgentUsageStrip.swift`: o item
  Agent usage, com a conta do terminal com foco (`focused`, que o app diz) ou a última, e o popover
  ao passar o ponteiro (`AgentUsageCard.swift` no `HoverCard` compartilhado, todas as contas; subir para dentro dele o mantém aberto). `CodexUsage.swift`: as contas
  do Codex e o uso tirado dos logs dele (os limites de cada uso), sem rede. `AgentAccountsView.swift`: a página
  Accounts (outra página da barra lateral, com o mesmo `AgentsView`) nos blocos do cartão (`AgentUsageCard.swift:block`), só as contas em uso (`visibleAccounts`:
  sem login ou vencida há mais de um dia ficam fora), com mais espaço entre elas que o cartão e sem linha; clique leva ao agente já aberto ou abre um, clique direito renomeia e
  esconde. `AgentLaunch.swift`: o comando que abre o agente de uma conta (o Claude pelo
  SessionKit.claudeCommand, com a status line do Cadex; o Codex com `CODEX_HOME`; a flag sem
  permissões), agents.open-account e agents.customize-accounts (ADR 0019 e 0021); agents.continue-in-agent
  ("Continue in…", plano 22 fase E), a conta escolhida no ⌘K e `continueCommand`: `cadex continue
  claude|codex` com CLAUDE_CONFIG_DIR ou CODEX_HOME da conta, numa aba na pasta do projeto. Conta escondida
  volta quando o `oauthAccount` muda (`fingerprint`, `onLoginChanged`).
- `AgentAccounts.swift` (plano 18, fase C): `AgentConfigShare`, a configuração compartilhada por
  link a partir do ~/.claude, lista negra do estado da conta (`isAccountState`; .credentials.json
  nunca), `plan` (o que vira link e, numa conta antiga que entra, o que vai antes para a lixeira),
  `apply` (lixeira, links, tira link de item que saiu da fonte), `ownCopy` e `follow`;
  `AgentManagedAccounts`, as contas criadas pelo Cadex em Application Support/Cadex/accounts
  (`create`, `folderName`, `all`, `isManaged`, `moveToTrash`: nada é apagado de vez).
  `AgentAccountCommands.swift`: agents.add-account, -set-active-account, -set-project-account (o
  projeto da janela, ou de volta à ativa), -sync-account-config,
  -share-account-config, -use-own-copy, -follow-default-config e -remove-account, com as listas no
  ⌘K (`AgentChoiceSource`); o que pergunta e confirma é do app (`AgentAccountActions`).
  O item Agent usage escolhe a conta ativa no clique direito (`AgentUsageStrip.swift`, "New
  Sessions Use"). AgentNewSession.account: a conta de uma sessão nova (a do projeto, a ativa, a padrão).
  AgentAccount.find inclui as contas criadas pelo Cadex quando já têm .claude.json.
- O histórico (plano 18, fase D): `AgentHistory.swift` (`AgentHistoryEntry`, uma conversa com a
  pasta, o branch, as datas, os títulos e a origem; `AgentHistoryReader`, que lê só o acrescentado,
  em pedaços com o próprio autorelease pool, acha o fim de linha com memchr, olha o nível de cima da
  linha pelos bytes antes de montar o JSON, pula linha acima de 64 KB e nunca guarda resultado de
  ferramenta), `AgentHistoryStore.swift` (o índice no `../../shared/text-index/`, uma fila só, lê o
  que cresceu e esquece o que sumiu), `AgentHistoryController.swift` (vigia as pastas projects/ das
  contas só com alguém olhando; `AgentHistoryLaunch`, os comandos de retomar e continuar com o kit),
  `AgentHistoryList.swift` (filtro e grupos puros, `AgentHistoryRows`, e a tabela que só desenha o
  que aparece), `AgentHistoryView.swift` (a página, com busca, escopo e agrupamento) e
  `AgentHistoryCommands.swift` (agents.resume-session, -continue-in-account, -copy-resume-command e
  -reveal-session-log, com a lista de conversas no ⌘K). agents.history é o `isEnabled`. Sessão
  continuada de outra conta: AgentSubagent.origins acha a pasta de subagentes da origem (pelas
  primeiras linhas do transcript, AgentHistoryReader.origin) e cada subagente guarda a pasta dele
  (`dir`), que a aba da conversa abre.
- A atenção (plano 19, fase C): `AgentAttention.swift` (AgentAttention.shared: os cartões do quadro,
  com as permissões cujo hook espera, que só Permitir e Negar respondem, no formato do Claude Code
  testado em 2026-11-15, e os pedidos vistos pelo OSC 7501; o feed, até 200; `unseen`, o número do
  sininho e do Dock; `update` recebe do app o que cada terminal relatou e fecha o hook quando o
  agente sai do "blocked"), `AgentAttentionView.swift` (a página do sininho: Needs You e Feed) e
  `AgentAttentionCommands.swift` (agents.approve, agents.deny e agents.mark-unread com a lista no ⌘K).
- Hibernação (plano 19, fase F): `AgentHibernation.swift`, as regras puras (`isDue`/`dueAt`: parado há
  agents.hibernateAfterMinutes e ninguém olhando; `configDir`: a conta pelo arquivo da conversa;
  `resumeCommand`: `cd <pasta> && claude --resume <id>` pelo kit, mantendo a sessão do kit e o token)
  e os comandos agents.hibernate e agents.restart; os terminais e o SIGTERM são do app
  (`../../app/AgentsHibernate.swift`).
- A conversa de um subagente numa aba (`AgentTranscriptDocument.swift`, um `TabDocument`): só pelo
  clique num subagente (`onOpenSubagent`). `AgentTranscript.swift` lê o log em pedaços, só o novo,
  e nunca guarda um resultado longo (prévia dos primeiros 4 KB, linhas contadas);
  `AgentTranscriptParse.swift` transforma cada linha em entradas (tarefa, resposta, ferramenta com o
  diff de um Edit, prévia do resultado); `AgentTranscriptStyle.swift` e `AgentMarkdown.swift`
  escrevem no jeito do Claude Code ("● Bash(…)", "⎿", Markdown) e `AgentTranscriptView.swift` mostra
  tudo numa vista de texto só (uma view por entrada custava 25 MB). Vigia o arquivo por um evento do
  sistema enquanto aberta; fechada, solta tudo.
- O app (`../../app/AgentsWiring.swift`) põe as páginas Agents (agents.show, ⇧⌘J) e Accounts
  (agents.show-accounts) no catálogo da barra lateral, o ponto no ícone enquanto o ícone está lá, o item Agents da barra de status, e acha o
  terminal de cada sessão pelo grupo de processos (`cadex_terminal_foreground_group` do núcleo).
- O id de cada sessão pelos hooks (plano 19, fase B): AgentsController.noteHook guarda, por pid do
  `claude`, o id que os hooks dizem (certo depois de /clear e --resume) e `withHookIDs` o põe no
  lugar do id do registro; o socket é da feature agent-tools.
- Status: fases C, C2 (notificações) e D (Accounts e uso) do plano 17 no código; plano 18 fase B
  (uso sem token, kit da sessão) feita e conferida numa sessão real (bhband, 2026-11-14). O sinal no título da aba
  do agente veio no plano 19 (feature tabs). Fase C do plano 18 (contas gerenciadas) no código; falta criar uma conta de
  verdade e fazer o /login nela.

## Como validar
- `make macos-test` passa: contas, sessões vivas e mortas, arquivo quebrado, projeto e worktree,
  subagentes, grupos, sem leitura com ninguém olhando ou desligado, sessão nova aparecendo sozinha.
  Com CADEX_SNAPSHOT_DIR, o teste salva agents-page.png.
