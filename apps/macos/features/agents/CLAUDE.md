# agents (app macOS)

## O que eu quero
- Ver os agentes de código rodando em todas as contas do Claude Code deste Mac: as sessões vivas por
  projeto, o estado (trabalhando, esperando você), os subagentes, e ir ao terminal de cada uma
  (plano 17, fase C; `../../../../docs/spec/agents.md`).

## O que eu não quero
- Mandar prompt ou falar com agente, nem mexer nos arquivos do Claude Code: só ler
  (`../../../../docs/adr/0019-agents-observe-only.md`). A exceção: abrir o agente de uma conta, que é
  digitar o comando dele num terminal, com o kit da sessão
  (`../../../../docs/adr/0021-cadex-managed-accounts.md`).
- Ler, guardar ou repassar token, login ou credencial, ou chamar o serviço de uso: nunca (ADR 0021).
- Ler ou vigiar alguma coisa com ninguém olhando, ou com agents.sessions desligado.
- Ler os logs das conversas: só o registro de cada sessão, as descrições dos subagentes, a data
  dos logs deles e, num clique num subagente, a conversa dele enquanto a aba está aberta.
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
- `AgentBackground.swift`: as sessões em segundo plano (agent view, `claude --bg`) abertas
  (trabalhando ou "blocked", que espera você), pelo `claude agents --json` da conta, a interface que
  a doc do Claude Code suporta (a pasta jobs/ é interna). Custa 0,15 s de CPU por chamada: roda só
  quando a pasta jobs/ de uma conta muda, no máximo a cada 5 s, fora da linha principal; sem o
  binário `claude` (~/.local/bin, /opt/homebrew/bin, /usr/local/bin), nada. O ambiente perde
  CLAUDECODE e CLAUDE_CODE_*.
- `AgentsController.swift`: a porta de entrada, uma para o app (`shared`). `watch` liga a leitura
  e `stop` desliga; sem ninguém, nenhum FSEvents e nenhum timer. Vigia por FSEvents com eventos
  por arquivo as pastas sessions e jobs das contas e a de subagentes da sessão aberta; a cada 10 s
  confere quem ainda está vivo (um agente que caiu não avisa) e acha pasta sessions nova. As sessões
  em segundo plano entram na mesma lista (`job`, `waitingFor`). `isEnabled` é o agents.sessions.
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
  "authentication_failed"`, que marca a conta com AgentUsageController.loginFailed). `AgentNotifier.swift`: a notificação do sistema quando uma sessão passa de
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
  permissões), agents.open-account e agents.customize-accounts (ADR 0019 e 0021). Conta escondida
  volta quando o `oauthAccount` muda (`fingerprint`, `onLoginChanged`).
- `AgentAccounts.swift` (plano 18, fase C): `AgentConfigShare`, a configuração compartilhada por
  link a partir do ~/.claude, lista negra do estado da conta (`isAccountState`; .credentials.json
  nunca), `plan` (o que vira link e, numa conta antiga que entra, o que vai antes para a lixeira),
  `apply` (lixeira, links, tira link de item que saiu da fonte), `ownCopy` e `follow`;
  `AgentManagedAccounts`, as contas criadas pelo Cadex em Application Support/Cadex/accounts
  (`create`, `folderName`, `all`, `isManaged`, `moveToTrash`: nada é apagado de vez).
  `AgentAccountCommands.swift`: agents.add-account, -set-active-account, -sync-account-config,
  -share-account-config, -use-own-copy, -follow-default-config e -remove-account, com as listas no
  ⌘K (`AgentChoiceSource`); o que pergunta e confirma é do app (`AgentAccountActions`).
  AgentNewSession.account: a conta de uma sessão nova (a do projeto, a ativa, a padrão).
  AgentAccount.find inclui as contas criadas pelo Cadex quando já têm .claude.json.
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
- Status: fases C, C2 (notificações) e D (Accounts e uso) do plano 17 no código; plano 18 fase B
  (uso sem token, kit da sessão) feita e conferida numa sessão real (bhband, 2026-11-14). Ainda não: o sinal no
  título da aba do agente. Fase C do plano 18 (contas gerenciadas) no código; falta criar uma conta de
  verdade e fazer o /login nela.

## Como validar
- `make macos-test` passa: contas, sessões vivas e mortas, arquivo quebrado, projeto e worktree,
  subagentes, grupos, sem leitura com ninguém olhando ou desligado, sessão nova aparecendo sozinha.
  Com CADEX_SNAPSHOT_DIR, o teste salva agents-page.png.
