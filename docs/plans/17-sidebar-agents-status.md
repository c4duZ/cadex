# Plano 17 — Barra lateral com ícones, agentes e barra de status personalizável

Depende de: plano 16 · Features: sidebar (nova), agents (nova), ssh (nova), status-bar, settings,
command-palette, shortcuts, tabs, terminal · Decisões: `docs/adr/0019-agents-observe-only.md`,
`docs/adr/0004-clean-rewrite.md`, `docs/adr/0005-every-action-is-a-command.md`,
`docs/adr/0008-phosphor-icons.md`, `docs/adr/0015-english-default-two-languages.md`.

## O que eu quero
- A barra lateral com uma fileira de ícones no topo (Files, Search, Git, Agents) e as sub-abas da
  página logo abaixo, como no protótipo aprovado pelo dono em 2026-10-21
  (https://claude.ai/artifact/5wvbgJrXvvoaAA4VQozQMU): "perfeito, exatamente isso".
  Spec: `docs/spec/sidebar.md`.
- Uma página Agents que junta as sessões vivas do Claude Code de todas as contas da máquina,
  agrupadas por projeto, com estado (trabalhando, esperando você) e subagentes, e o uso do plano de
  cada conta (5 h e semana). Spec: `docs/spec/agents.md`.
- A barra de status montada por quem usa: trilha, ambiente, branch, uso das contas, agentes, RAM,
  CPU, memória do Cadex, terminais, portas e SSH; arrastar entre esquerda e direita, esconder, e
  deixar como é hoje se quiser. Muito personalizável: pedido explícito do dono. Spec:
  `docs/spec/status-bar.md`.
- Os servidores do `~/.ssh/config` na barra de status, com um teste de conexão ao abrir e um clique
  para abrir `ssh <host>` numa aba. Spec: `docs/spec/ssh.md`.
- Leve: tudo ligado, no máximo 10% acima do app sem as leituras; cada leitura desligável, e
  desligada custa zero. Medido pela prova de conceito de 2026-10-21 (ADR 0019): ~3 MB e CPU parado
  quase zero.

## O que eu não quero
- Perder a identidade do Cadex: nada com cara de cópia do Orca. Cores e fontes do tema e do
  UILooks, ícones Phosphor (nada de SF Symbols nem marca de outra empresa na barra), o desenho do
  protótipo, que é nosso.
- Código do Orca ou do ai-usagebar copiado, traduzido ou aberto (ADR 0004); só o comportamento.
- Iniciar agente, mandar prompt, chamar modelo ou renovar login (ADR 0019).
- Ler os logs completos das sessões a cada mudança: só o registro da sessão e as descrições dos
  subagentes; do log, só a data de modificação.
- Nada desligado ou escondido pesando (o dono, 2026-10-21, sobre as fases B, C e D): sem memória,
  sem arquivo vigiado, sem timer, sem requisição. Item escondido, página fechada ou janela fora da
  tela não lê; página só é criada quando aparece (como o Git History na barra lateral). Cada fase
  confere no `make perf` que, desligado, os números são os de antes.
- Ação que só existe no arrastar ou no botão direito: cada uma é um comando com id.
- Por enquanto: Codex, sessões na nuvem, o Windows (fica para depois, com o port) e o painel de
  Tasks e Automations do Orca.

## Como eu quero
**Fases:**
- **A. Barra lateral com ícones.** Feature nova `sidebar` (só app macOS): pasta com `CLAUDE.md`,
  testes e linha na tabela do `CLAUDE.md` da raiz. O que hoje está em
  app/SidebarView.swift (agora apagado) vira a feature: a fileira de ícones, o título com as sub-abas,
  o registro de páginas (id, ícone, título, comando, sub-abas, sinal) que o app preenche com as
  views de explorer, search, source-control e git-history pela porta de entrada de cada uma, e o
  painel Customize com arrastar. Configuração sidebar.items (lista em ordem) e a página aberta e as
  sub-abas salvas com os spaces. Comandos sidebar.customize, sidebar.toggle-page (com a lista no
  ⌘K) e sidebar.show-<página>; o Git passa a ter Changes e History como sub-abas. Phosphor: os
  ícones que faltarem entram na fonte de `apps/macos/shared/icons/`. Termos "Página da barra lateral"
  e "Sub-aba" no `docs/CONTEXT.md`. Features: sidebar, settings, command-palette, spaces.
- **B. Barra de status por itens.** Na feature status-bar: o item como unidade (id, lado, view,
  "visível" liga e desliga a medida), a barra montada pelos ids de statusBar.left e statusBar.right,
  o modo de edição com arrastar e a faixa dos escondidos, o menu do botão direito, a seção Status Bar
  em General nas configurações. Os itens desta fase: Folder e Environment (os de hoje), Git branch,
  RAM e CPU do sistema (`host_statistics64`, a cada 2 s, só visível), Cadex memory
  (`task_info`), Terminals. Cada item vem de quem tem o dado, ligado pelo app; a status-bar não
  importa feature nenhuma. Comandos statusBar.customize e statusBar.toggle-item (lista no ⌘K).
  Features: status-bar, settings, command-palette.
- **C. Agents › Sessions.** Feature nova `agents` (só app macOS): achar as contas, ler os registros
  das sessões vivas (pid vivo), os subagentes, o projeto (raiz git) e o branch; vigiar por FSEvents
  com eventos por arquivo, só as pastas de sessões das contas e a pasta de subagentes da sessão
  aberta. O modelo e a leitura como funções puras testadas com pastas falsas (formato velho, campo
  faltando, JSON quebrado). A página Sessions, o ponto no ícone, o item Agents da barra de status, o
  sinal no título da aba do agente (o terminal diz quais pids são filhos de cada PTY) e o duplo
  clique que foca o terminal. Configuração agents.sessions. Comando agents.show (⇧⌘J; o ⇧⌘A é do
  manter acordado). Features: agents, sidebar, status-bar, tabs, terminal, settings.
- **C2. Notificações (pedido do dono, 2026-10-21).** Quando um agente para e espera: pede permissão,
  fez uma pergunta ou terminou, cada um com a sua chave e a sua imagem; o motivo pelo fim do log
  (ADR 0019); clique leva ao terminal; nada enquanto você olha o terminal dele. Só Mac; no Windows
  com o port. Features: agents, settings.
- **Antes da D: auditoria do ai-usagebar** (autorizada pelo dono como exceção à ADR 0004, só
  comportamento, 2026-10-21). Ele renova e regrava o OAuth dos CLIs e se identifica como Claude
  Code; nada disso entra no Cadex. Serve: campos five_hour, seven_day, seven_day_sonnet e limits;
  cache de 60 s, dado velho até 7 dias, pausa de 5 min depois de 429, timeouts de 10 s; o estado
  "waiting" das sessões.
- **D. Agents › Accounts e uso.** O token pelo `/usr/bin/security`, uma requisição por conta, a cada
  5 min só com alguém mostrando, espera crescente em erro, 429 respeitado, login vencido sem
  requisição até o registro da conta mudar. A página Accounts, o item Agent usage da barra de
  status, renomear e esconder conta (agents.accountNames, agents.hiddenAccounts), agents.accounts.
  Comando agents.refresh-usage. Features: agents, status-bar, settings.
- **E. SSH e portas.** Feature nova `ssh` (só app macOS): ler o `~/.ssh/config` com `Include`,
  vigiar o arquivo, testar por TCP (`Network`, 3 s) ao abrir e a cada 10 min com o item visível, o
  item SSH com o menu e o comando ssh.connect (abre aba com `ssh <host>`; lista no ⌘K), ssh.ping. O
  item Ports na status-bar, com as portas ouvindo nos processos filhos dos PTYs (`libproc`), lido
  quando um programa começa ou termina e a cada 10 s com programa rodando. Features: ssh,
  status-bar, terminal, tabs, settings.
- **F. Peso e fechamento.** Cenário novo no `tools/perf/run.py`: tudo ligado (todos os itens da
  barra, Agents aberto, 3 contas falsas e 3 sessões falsas numa pasta de teste, 3 hosts locais), com
  limite de 10% acima do `idle_mb` e CPU parado igual ao de hoje; e o cenário de hoje com tudo
  desligado, sem mudar. Os ids novos em `MAC_ONLY` de `tools/check_command_parity.py`. README com a
  página Agents e a barra de status. Notas da release em inglês.

## Como validar
- `make check` passa a cada fase, com os ids novos aceitos pelo `tools/check_command_parity.py`.
- `make perf` nas fases B a F (mexem em desenho e em leitura em segundo plano): com tudo desligado,
  os números de hoje; com tudo ligado, no máximo 10% a mais de memória e CPU parado sem mudança.
- Fase A: os critérios de `docs/spec/sidebar.md`; testes do registro de páginas, da ordem salva e
  do id desconhecido no settings.json.
- Fase B: os critérios de `docs/spec/status-bar.md`; sem configuração, a barra igual à de antes;
  testes da montagem pelos ids, do arrastar (mudar de lado, sair, entrar) e do item escondido que não
  mede.
- Fase C: com `claude` em duas abas de contas diferentes, as duas sessões aparecem em até 1 s, nos
  projetos certos; o estado muda ao mandar mensagem e ao terminar; fechar a aba tira a sessão;
  testes com pastas falsas, incluindo formato desconhecido sem travar.
- Fase D: os números de cada conta iguais aos do `/usage` dela; login vencido sem requisição
  (`nettop`); sem rede, o último valor apagado com a hora.
- Fase E: hosts do `~/.ssh/config` no menu sem curingas; "Test Again" depois de ligar a rede volta
  para verde; ssh.connect abre a aba certa; `npm run dev` num terminal faz a porta aparecer.
- Com todas as leituras desligadas, `fs_usage` e `nettop` não mostram o Cadex abrindo arquivo do
  Claude Code, nem o `~/.ssh/config`, nem saindo para a rede.
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`), comparando com o protótipo.
