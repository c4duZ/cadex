# agents (app macOS)

## O que eu quero
- Ver os agentes de código rodando em todas as contas do Claude Code deste Mac: as sessões vivas por
  projeto, o estado (trabalhando, esperando você), os subagentes, e ir ao terminal de cada uma
  (plano 17, fase C; `../../../../docs/spec/agents.md`).

## O que eu não quero
- Mandar prompt ou falar com agente, nem mexer nos arquivos do Claude Code: só ler
  (`../../../../docs/adr/0019-agents-observe-only.md`). A exceção: abrir o agente de uma conta, que é
  digitar o comando dele num terminal.
- Ler ou vigiar alguma coisa com ninguém olhando, ou com agents.sessions desligado.
- Ler os logs das conversas: só o registro de cada sessão, as descrições dos subagentes e a data
  dos logs deles.
- Travar ou mostrar erro porque uma versão nova do Claude Code mudou um arquivo: pula e conta.

## Como eu quero
- `AgentSessions.swift`: o modelo e a leitura, puros e testados com uma pasta pessoal falsa.
  `AgentAccount` (~/.claude e as ~/.claude-* com .claude.json; nome da organização, ou a pasta
  quando é só "x's Organization"; nomes iguais ganham a pasta), `AgentSession` (o
  sessions/<pid>.json de cada conta com o processo vivo: busy é trabalhando, idle é esperando),
  `AgentProject` (o .git acima da pasta, worktree também, e o branch lido do HEAD, sem rodar git) e
  `AgentSubagent` (os .meta.json da pasta de subagentes da sessão; trabalhando se o log mudou nos
  últimos 30 s, uma estimativa).
- `AgentsController.swift`: a porta de entrada, uma para o app (`shared`). `watch` liga a leitura
  e `stop` desliga; sem ninguém, nenhum FSEvents e nenhum timer. Vigia por FSEvents com eventos
  por arquivo as pastas sessions das contas e a de subagentes da sessão aberta; a cada 10 s confere
  quem ainda está vivo (um agente que caiu não avisa) e acha pasta sessions nova. `isEnabled` é o
  agents.sessions.
- `AgentsLayout.swift`: grupos por projeto (o mais recente primeiro; esperando antes de
  trabalhando) e a linha de baixo ("main · conta", "esperando você · conta · fora do Cadex").
- `AgentsView.swift`: a página da barra lateral; lê só enquanto aparece. Clique abre e fecha os
  subagentes; duplo clique chama `onOpen`. `AgentRows.swift`: o sinal (anel girando, ponto azul,
  ✓), a linha clicável e os rótulos.
- `AgentStop.swift`: por que uma sessão parou, do fim do log (64 KB, uma vez por parada):
  permissão (ferramenta pedida sem resposta), pergunta (AskUserQuestion, ExitPlanMode), terminou
  (fim de turno). `AgentNotifier.swift`: a notificação do sistema quando uma sessão passa de
  trabalhando para esperando, por tipo (agents.notifyPermission, -Question, -Finished), nunca
  enquanto você olha o terminal dele; só de dentro de um .app (fora dele a central do sistema para o
  processo). `AgentNotifyIcon.swift`: a imagem de cada tipo, desenhada uma vez por cor no cache.
- `AgentUsage.swift`: o login (`AgentLogin`: o item do Keychain pelo hash da pasta, lido pelo
  `/usr/bin/security` a cada leitura, ou o .credentials.json; nunca guardado, renovado ou escrito),
  o uso (sessão de 5 h, semana, semana do Sonnet, cada um com o reinício) e o estado do cartão.
  `AgentUsageController.swift`: uma leitura para o app, só com Accounts ou o item na tela e o app
  ativo; 5 min entre leituras, 60 s de frescor, espera de 5/10/20/60 min nos erros e a pedida no
  429; login vencido sem requisição; se identifica como Cadex (ADR 0019). `AgentUsageViews.swift`:
  as barras do cartão (destaque, laranja a partir de 70%, vermelho a partir de 90%) e
  `AgentUsageRows`, as barras que o cartão e o popover dividem. `AgentUsageStrip.swift`: o item
  Agent usage, com a conta do terminal com foco (`focused`, que o app diz) ou a última, e o popover
  ao passar o ponteiro (`AgentUsageCard.swift` no `HoverCard` compartilhado, todas as contas; subir para dentro dele o mantém aberto). `CodexUsage.swift`: as contas
  do Codex e o uso tirado dos logs dele (os limites de cada uso), sem rede. `AgentAccountsView.swift`: a página
  Accounts (outra página da barra lateral, com o mesmo `AgentsView`) nos blocos do cartão (`AgentUsageCard.swift:block`), só as contas em uso (`visibleAccounts`:
  sem login ou vencida há mais de um dia ficam fora), com mais espaço entre elas que o cartão e sem linha; clique leva ao agente já aberto ou abre um, clique direito renomeia e
  esconde. `AgentLaunch.swift`: o comando que abre o agente de uma conta (`CLAUDE_CONFIG_DIR` ou
  `CODEX_HOME`, a flag sem permissões), agents.open-account e agents.customize-accounts; a única coisa
  que o Cadex inicia (ADR 0019). Conta escondida volta quando o login muda (`fingerprint`,
  `onLoginChanged`).
- O app (`../../app/AgentsWiring.swift`) põe as páginas Agents (agents.show, ⇧⌘J) e Accounts
  (agents.show-accounts) no catálogo da barra lateral, o ponto no ícone enquanto o ícone está lá, o item Agents da barra de status, e acha o
  terminal de cada sessão pelo grupo de processos (`cadex_terminal_foreground_group` do núcleo).
- Status: fases C, C2 (notificações) e D (Accounts e uso) no código. Ainda não: o sinal no título
  da aba do agente.

## Como validar
- `make macos-test` passa: contas, sessões vivas e mortas, arquivo quebrado, projeto e worktree,
  subagentes, grupos, sem leitura com ninguém olhando ou desligado, sessão nova aparecendo sozinha.
  Com CADEX_SNAPSHOT_DIR, o teste salva agents-page.png.
