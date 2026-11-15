# Plano 18 — Contas e sessões na pasta do Cadex

Depende de: plano 17 · Features: agents, agent-tools (nova, núcleo e app), status-bar, sidebar,
settings, command-palette, tabs, terminal · Decisões: `docs/adr/0019-agents-observe-only.md`
(revista em parte pela ADR 0021, a escrever na fase A), `docs/adr/0002-zig-core-with-c-api.md`,
`docs/adr/0004-clean-rewrite.md`, `docs/adr/0005-every-action-is-a-command.md`,
`docs/adr/0007-one-step-install.md`, `docs/adr/0008-phosphor-icons.md`.

## O que eu quero
- Várias contas do Claude Code geridas pelo Cadex sem mexer no que já funciona: as contas de hoje
  (`~/.claude` e as `~/.claude-*`) continuam onde estão; conta nova nasce numa pasta do Cadex, com o
  login feito pelo próprio `claude` (`/login`) numa aba. O Cadex nunca vê token (o dono,
  2026-11-14).
- Uma configuração só para todas as contas: `~/.claude` é a conta padrão e a fonte; as outras
  recebem link de tudo o que não é estado da conta. Instalou uma skill, vale em todas (o dono,
  2026-11-14: "pode ser por link").
- O uso de cada conta (sessão de 5 h e semana) sem tocar no login: pelo `rate_limits` que o próprio
  Claude Code entrega à status line, nas sessões que o Cadex abre. Sai a leitura do Keychain e a
  requisição ao serviço de uso: os termos da Anthropic dizem que desenvolvedores "may not collect,
  store, or intermediate Claude.ai credentials or session tokens"
  (code.claude.com/docs/en/legal-and-compliance, lido em 2026-11-14).
- Todas as conversas de todas as contas num histórico só, com busca, e um clique para retomar na
  conta certa, ou continuar a mesma conversa em outra conta quando o limite de uma acaba.
- Escolher a conta das sessões novas (a conta ativa) e uma conta padrão por projeto.
- Leve: cada parte desligável, e desligada custa zero, como no plano 17.

## O que eu não quero
- Mover uma conta que já existe: no Mac o login fica no Keychain amarrado ao caminho da pasta, e
  mover desloga (o dono teria de refazer o `/login` em cada uma).
- Ler, guardar, renovar ou repassar token, credencial ou login, nem chamar o serviço de uso com
  ele. O Cadex se identifica como Cadex e não fala com a API da Anthropic.
- Compartilhar entre contas o que é estado da conta: .claude.json, projects/, sessions/,
  history.jsonl, jobs/, daemon/, state/, file-history/, paste-cache/, shell-snapshots/, cache/.
  Dois escritores no mesmo projects/ perdem mensagens, e a limpeza de 30 dias de uma conta
  apagaria sessões da outra.
- Escrever no .claude.json de conta nenhuma (o Claude Code o regrava com a sessão aberta), nem no
  `~/.claude` do dono, fora os links pedidos nas pastas que o Cadex cria. Status line, hooks e MCP
  do Cadex entram pelo kit da sessão, só nas sessões que o Cadex abre.
- Ler os transcripts inteiros a cada mudança: o índice lê só o que foi acrescentado.
- Código do Orca ou de outro app como referência (ADR 0004): o comportamento vem da documentação
  deles e dos testes feitos nesta máquina.
- Ação só em botão ou menu: cada uma é um comando com id (ADR 0005).
- Por enquanto: Codex nas contas gerenciadas (segue como no plano 17), o Windows, sessões na nuvem,
  o modo stream-json e a memória (plano 22).

## Como eu quero
**Fases:**
- **A. ADR e spec.** ADR 0021 (docs/adr/0021-cadex-managed-accounts.md, a criar):
  - o Cadex cria e gerencia pastas de conta e passa o kit da sessão (`--settings`, `--plugin-dir`,
    `--mcp-config`, ambiente da aba) às sessões que ele abre;
  - lê o uso pelo `rate_limits` da status line e deixa de ler o Keychain e o serviço de uso;
  - amplia o "a única coisa que o Cadex inicia" da ADR 0019: além de abrir o agente de uma conta,
    o Cadex abre o agente **sem prompt** em Retomar (aqui), Nova tarefa e relançar depois de
    hibernar (plano 19). Prompt, modelo e chat continuam fora (a ADR 0033 do plano 24 generaliza);
  - revê na ADR 0019 "Login só de leitura" e a leitura do uso; o resto dela continua valendo.
  - Registra a fonte dos termos e os testes de 2026-11-14. `docs/spec/agents.md` ganha Contas
    gerenciadas e Histórico, com estados, casos de borda e critérios. Termos no `docs/CONTEXT.md`:
    Conta gerenciada, Conta padrão, Conta ativa, Configuração compartilhada, Kit da sessão,
    Histórico de sessões, Continuar em outra conta. Nenhum código nesta fase.
- **B. Kit da sessão, executável `cadex` e uso sem token.**
  - Kit da sessão (apps/macos/shared/session-kit/, a criar, com `CLAUDE.md`): a única peça que
    monta o `--settings`, o `--plugin-dir`, o `--mcp-config` e o ambiente de uma sessão aberta pelo
    Cadex. Fica em shared porque agents, worktrees, review, memory e orchestration acrescentam
    itens a ele por uma porta de contribuição, ligada pelo app em `apps/macos/app/`; nenhuma
    feature importa outra para isso. O comando de AgentLaunch.swift
    (`apps/macos/features/agents/AgentLaunch.swift`) passa a pedir o kit.
  - O ambiente da aba é do kit: põe o `cadex` no PATH, CADEX_SESSION_TOKEN (plano 19) e
    CADEX_DISPATCH_ID (plano 24) quando houver, e **limpa o herdado**: tira CLAUDECODE e as
    CLAUDE_CODE_*, mantendo só o CLAUDE_CONFIG_DIR da conta. No teste de 2026-11-14, uma sessão que
    herdou CLAUDE_CODE_CHILD_SESSION ficou com o transcript desligado.
  - Testado em 2026-11-14 (Claude Code 2.1.325): hooks do `--settings` **se somam** aos das outras
    fontes (os do projeto e os do `--settings` rodaram juntos), então os hooks do dono (os do GSD)
    seguem rodando; o `statusLine` do `--settings` **substitui** o da conta (só o do Cadex
    apareceu), então o comando do Cadex chama o do dono.
  - MCPs do usuário: o kit lê (só leitura) os `mcpServers` da conta padrão e os passa pelo
    `--mcp-config`; nada é escrito no .claude.json de conta nenhuma.
  - O kit também exporta `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` (só quando o terminal do Cadex respeitar
    o modo DEC 2026, plano 19 E; ligado em 2026-11-15) e põe `preferredNotifChannel` no `--settings`
    (este não: o dono, 2026-11-15, os avisos de agente já vêm pelos hooks): testado em
    2026-11-14 (2.1.325), com TERM_PROGRAM=Cadex isso devolve a saída sincronizada e a notificação
    OSC 777 sem fingir ser Ghostty. E traz permissions.allow para as ferramentas seguras do Cadex
    (`mcp__cadex__*` de leitura, plano 20); as que agem continuam perguntando.
  - Não usar `CLAUDE_CODE_PROJECT_DIR_NAME`: funciona (sessão e memória na pasta com o nome dado,
    teste de 2026-11-14), mas sessões abertas fora do Cadex ficariam em outra pasta para o mesmo
    projeto. A pasta segue a regra do Claude Code, que o Cadex já calcula certo
    (`apps/macos/features/agents/AgentProjectFolder.swift`, corrigido em 2026-11-14: todo caractere
    não alfanumérico vira "-", acima de 200 o prefixo mais um hash).
  - Executável `cadex` (feature nova `agent-tools`: CLI no núcleo, core/features/agent-tools/, a
    criar, em Zig pela ADR 0002; servidor no app a partir do plano 19), no bundle, sem interface.
    Nasce mínimo: `cadex statusline`, o comando da status line do kit. Os planos 19 e 20
    acrescentam subcomandos.
  - `cadex statusline` recebe o JSON (testado: traz `rate_limits.five_hour` e `.seven_day` com
    `used_percentage` e `resets_at`, `context_window`, `cost`, `session_id`, `transcript_path`),
    grava por conta o `rate_limits` (`~/Library/Application Support/Cadex/usage/<conta>.json`, a
    criar) e por sessão o `context_window` e o `cost` (…/usage/sessions/<id>.json, a criar), escrita
    atômica, e roda a status line que o dono já tem na conta, imprimindo a saída dela.
  - `AgentUsageController` lê esses arquivos (FSEvents por arquivo, só com alguém mostrando o uso)
    em vez de `AgentLogin` + requisição; o `/usr/bin/security` em AgentUsage.swift sai, com os
    testes dele. Sem sessão aberta pelo Cadex na conta, o cartão mostra o último valor com
    "em <hora>"; janela que já reiniciou mostra 0%; sessão de fora do Cadex não informa ("Abra o
    agente pelo Cadex para ver o uso"). agents.accounts continua desligando tudo.
  - O que hoje depende do Keychain (plano 17) muda junto, sem ler login:
    - "Conta com login": o .claude.json dela tem `oauthAccount`.
    - "Login vencido": testado em 2026-11-14, a validade (`credential_expires_at`) só vem no
      `result` de um `claude -p`; a status line, o `system/init` e os hooks não a trazem, e
      `claude auth status` não é comando (vira prompt). O Cadex não roda `-p` só para isso: o cartão
      mostra "Login vencido: rode claude nesta conta" quando uma sessão falha com erro de
      autenticação ("Failed to authenticate…"), e aproveita o `credential_expires_at` de um `-p`
      que já rode (agente de memória, automação); fora isso, só a hora do último dado.
    - Conta escondida volta quando o `oauthAccount` muda (conta ou organização); agents.hiddenLogins
      passa a guardar isso.
  Features: agents, agent-tools, status-bar, settings.
- **C. Contas gerenciadas.** Na feature agents (AgentAccounts.swift, a criar):
  - "Adicionar conta" (agents.add-account): pede o nome, cria a pasta com caminho curto
    (`~/Library/Application Support/Cadex/accounts/<nome>`, a criar; o Orca precisou desligar um
    socket por caminho longo), cria os links, abre uma aba na pasta do workspace com `claude` e
    `CLAUDE_CONFIG_DIR` dela e mostra "Faça /login nesta aba". A conta aparece em Accounts quando o
    .claude.json dela ganha `oauthAccount`.
  - Configuração compartilhada: a fonte é `~/.claude`; a conta gerenciada recebe link de **tudo o
    que existe no topo da fonte, menos o estado da conta** (a lista de "O que eu não quero" e o
    estado novo que o Claude Code criar: backups/, downloads/, feedback/, session-env/,
    stats-cache.json, os arquivos daemon-* e .last-*). Lista negra, não branca: ferramentas
    instaladas na pasta, como o GSD (gsd-core/, gsd-file-manifest.json, package.json), seguem
    funcionando. Item novo na fonte entra no próximo "Sincronizar" (agents.sync-account-config).
    Testado em 2026-11-14 (num .claude/ de projeto): skills/ como link, uma skill lincada dentro
    dela, settings.json lincado com hook e `CLAUDE.md` lincado carregaram todos. O que o Claude
    grava num arquivo lincado atravessa o link e vale para todas as contas: a spec diz isso.
  - Exceção por conta: "Usar cópia própria de <item>" troca o link por uma cópia, que deixa de
    seguir a fonte; "Voltar a seguir a conta padrão" desfaz (a cópia vai para a lixeira).
  - Contas de hoje: "Compartilhar a configuração da conta padrão" é opcional e mostra antes o que
    vira link e o que já existe ali (arquivo existente vai para a lixeira, nunca apagado).
  - Conta ativa (agents.activeAccount): a das sessões novas abertas pelo Cadex; escolhida no item
    Agent usage e no ⌘K (agents.set-active-account). Conta padrão por projeto
    (agents.projectAccounts, raiz git → conta) vence a ativa naquele projeto.
  - Comandos novos: agents.add-account, agents.set-active-account, agents.sync-account-config,
    agents.remove-account (tira do Cadex; a pasta vai para a lixeira só depois de confirmar).
  Features: agents, status-bar, settings, command-palette, tabs, terminal.
- **D. Histórico unificado.** Página History na feature agents, ao lado de Sessions:
  - Índice de todas as contas: para cada `<pasta da conta>/projects/*/*.jsonl` guarda o caminho do
    arquivo, a conta dona, o id, a pasta original (`cwd`), o branch, a data, o primeiro prompt e o
    título que o Claude deu. Lê só o acrescentado (offset por arquivo), em pedaços fora da linha
    principal, como AgentTranscript.swift; nunca guarda resultado de ferramenta. A pasta de cada
    linha vem do `cwd` dela, não da pasta do arquivo: uma conversa do repositório retomada numa
    worktree continua gravando no projeto do repositório (teste de 2026-11-14).
  - Sessão continuada em outra conta: o índice guarda a origem (caminho da sessão de onde veio),
    porque os subagentes dela ficam só na conta de origem (a cópia leva só a conversa principal,
    teste de 2026-11-14); a conversa de um subagente é procurada também lá.
  - Onde fica: a leitura do formato do Claude Code no app, em Swift, como a ADR 0019 decidiu ("se
    as duas leituras ficarem iguais, a parte comum desce para o núcleo"). A busca em texto é uma
    peça compartilhada (apps/macos/shared/text-index/, a criar), porque a memória do plano 22 usa a
    mesma: SQLite do sistema com FTS5, sem dependência nova (ADR 0007). Conferido em 2026-11-14: o
    `/usr/bin/sqlite3` do macOS (3.54) cria e consulta tabela FTS5.
  - Busca por título, pasta, branch e trecho; agrupamento por projeto, pasta ou conta; escopo
    projeto atual ou tudo.
  - "Retomar" (agents.resume-session): abre aba na pasta original e digita
    `CLAUDE_CONFIG_DIR=<conta dona> claude --resume <id>`.
  - "Continuar em outra conta" (agents.continue-in-account): escolhe a conta e digita
    `CLAUDE_CONFIG_DIR=<outra> claude --resume <caminho do .jsonl> --fork-session`. Testado em
    2026-11-14 no Claude Code 2.1.325: a outra conta recebe a conversa inteira e grava a cópia na
    pasta dela; o arquivo original fica intacto (mesmo hash); só pelo id dá "No conversation
    found"; sem `--fork-session` a outra conta escreve no arquivo da primeira (por isso o fork é
    obrigatório); o custo acumulado passa junto. Também testado no modo interativo e com
    subagente (a outra conta lembrou o que o subagente achou). Falta só uma sessão longa, que a
    fase testa antes de mostrar o comando.
  - Também: copiar o comando de retomar (agents.copy-resume-command), revelar o arquivo
    (agents.reveal-session-log), abrir a pasta da sessão no workspace.
  - Configuração agents.history (ligada; desligada, nada indexado nem vigiado). Vigia só as pastas
    projects/ das contas com a página aberta; fechada, o índice fica em disco e nada roda.
  Features: agents, sidebar, settings, command-palette, tabs, terminal.
- **E. Peso e fechamento.** Cenário no `tools/perf/run.py`: 3 contas falsas (uma gerenciada com
  links) e 200 transcripts falsos numa pasta de teste (CADEX_PERF_HOME), com History aberta e
  fechada; limite de 10% acima do `idle_mb` e CPU parado igual. Os ids novos em `MAC_ONLY` de
  `tools/check_command_parity.py`. `CLAUDE.md` de agents, agent-tools e session-kit com os pontos
  de entrada e a regra "nunca token". README com contas e histórico. Notas da release em inglês.

## Como validar
- `make check` passa a cada fase; os ids novos aceitos pelo `tools/check_command_parity.py`.
- `make perf` nas fases B, D e E: tudo desligado, os números de hoje; tudo ligado, no máximo 10% a
  mais de memória e CPU parado sem mudança.
- Fase A: a ADR 0021 cita a ADR 0019 e os pontos revistos (login, uso, o que o Cadex inicia);
  `docs/spec/agents.md` com os critérios novos; `make manifests` passa.
- Fase B: com uma sessão aberta pelo Cadex, o cartão da conta mostra os mesmos números do `/usage`
  dela; a status line do dono continua aparecendo igual; os hooks do dono continuam rodando; o
  ambiente da aba não tem CLAUDECODE nem CLAUDE_CODE_* herdados e o transcript é gravado;
  `fs_usage` e `nettop` não mostram o Cadex chamando `/usr/bin/security` nem saindo para a rede;
  testes do `cadex statusline` e do leitor com JSON falso, campo faltando e arquivo quebrado; sem
  `oauthAccount`, a conta continua escondida.
- Fase C: "Adicionar conta" cria a pasta, os links certos (nenhum dos proibidos; uma pasta
  desconhecida na fonte, como gsd-core/, também vira link) e a aba com o `/login`; depois do login
  a conta aparece em Accounts; uma skill nova em `~/.claude/skills` aparece na conta gerenciada sem
  nada a fazer; um MCP da conta padrão aparece na sessão sem o .claude.json mudar; "cópia própria"
  deixa de seguir a fonte; nenhuma conta existente muda de lugar nem perde o login; testes com uma
  pasta pessoal falsa.
- Fase D: com duas contas reais, as sessões das duas aparecem, nos projetos certos; "Retomar" abre
  na conta dona; "Continuar em outra conta" repete o teste de 2026-11-14 (palavra-código lembrada,
  arquivo original com o mesmo hash, cópia na pasta da outra conta); um transcript crescendo só
  relê o acrescentado; formato desconhecido é pulado sem travar.
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`).

## Fechamento (2026-11-14)
- Fases A a E no código e conferidas em sessões reais do Claude Code 2.1.325, nas contas bhband e
  bkdg do dono:
  - B: o cartão de cada conta com os números do `/usage` dela (bhband 4% e 56%, bkdg 60% e 36%,
    sessões ao mesmo tempo); a status line e os hooks do dono rodando; 6,5 min sem processo filho
    além do shell nem socket de rede. Achado no caminho: a fatia x86_64 do `cadex` travava depois do
    `codesign` (folga no cabeçalho, `core/build.zig`; o empacotamento testa as duas fatias).
  - C: conta criada pelo código do app com 15 links e nenhum item de estado, o `claude` nela até
    "Select login method", o ~/.claude intacto; um MCP passado pelo kit no `/mcp` de outra conta.
    Falta o `/login` de uma conta nova, que é do dono.
  - D: GIRASSOL-47 retomada na bhband e continuada na bkdg (original com o mesmo hash, cópia na
    bkdg, origem achada nos dois formatos do Claude Code); uma conversa longa (198 pedidos, três
    compactações) continuada com tudo o que a conta original carregaria. Primeira leitura das 236
    conversas (2,5 GB) em 13 s e 97 MB de pico, depois 0,01 s.
- `make perf` (`history_scenario`: 3 contas, uma gerenciada com links, e 200 conversas pelo
  CADEX_PERF_HOME): History aberta 85 MB contra 85 MB parado (0%), CPU 0,1%; fechada 79 MB, CPU 0%,
  e o arquivo do índice nem nasce. O cenário pegou a página vigiando escondida (a barra lateral
  guarda todas as páginas na janela) e mostrou que a barra lateral não abre o primeiro ícone ao
  iniciar: os cenários pedem a página por CADEX_PERF_SIDEBAR, e o "tudo ligado" do plano 17 passou a
  abrir Agents de verdade (+1,2%).
- Os ids novos estão em MAC_ONLY no `tools/check_command_parity.py`.
- Diferenças do plano escrito: `CLAUDE_CODE_FORCE_SYNC_OUTPUT`, `preferredNotifChannel` e o `cadex`
  no PATH da aba ficaram para os planos 19 (fase E) e 20; o login vencido só é notado com alguma
  notificação ligada (é a leitura da parada que o acha).

## Notas da release (inglês)

```markdown
## Many Claude Code accounts, one setup (Mac)

- **Usage without your login.** Each account's 5-hour and weekly usage now comes from Claude Code itself, through the status line of the sessions Cadex opens. Cadex no longer reads the Keychain or calls any service, and your own status line keeps showing as before. An account only used outside Cadex says "Open the agent from Cadex to see usage".
- **Add Agent Account** makes a new account in Cadex's folder and opens `claude` in it for `/login`. It follows `~/.claude` through links — skills, hooks, settings, plugins — but keeps its own login, conversations and history. Existing accounts stay where they are and can follow too (Share the Default Account's Config…). Sync, own copy and follow again are commands.
- **Active account**: right-click the Agent usage item to choose where new sessions open; a project can have its own (Set This Project's Agent Account).

## Every conversation, one History (Mac)

- **The History page** lists the conversations of all your accounts — title, folder, branch, account — searchable by what was said, by project, folder or account, in this project or all.
- **Double-click resumes** in the account that owns it. **Continue in Another Account** carries a conversation to another account when one runs out of limit; the original stays untouched, and subagents from before the copy are still found.
- The first reading of a big history runs in the background (2.5 GB in about 13 s); then only what grows is read, and nothing runs while the page is closed.

## Smaller fixes (Mac)

- The `cadex` helper ships in both slices; the Intel one crashed after signing.
- Conversation titles never show a compaction summary or "[Request interrupted by user]".
```
