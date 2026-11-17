# Plano 26 — Moldura nova (2/6): barra de título, barra de status e o painel da direita

Depende de: plano 25 · Features: app (TitleBarView, WorkspaceView, PanelView, SidebarWiring), tabs,
status-bar, inspector (nova), sidebar, explorer, source-control, git-history, memory, agents,
power, updates · Decisões: `docs/adr/0035-work-frame.md` · Mockups: 1 (o mapa), 2 (uma tarefa), 5
(o sino), as peças TitleBar, StatusBar e Inspector · Inventário: seções "Barra de título e janela",
"Páginas da barra lateral" e "Barra lateral de ícones" (o que é do 26).

## O que eu quero
- A janela com as quatro regiões do mockup: a barra de título nova, o centro, o painel da direita
  e a barra de status nova. A esquerda segue com a barra de hoje até o plano 27, mas sem as páginas
  que mudaram para a direita.
- O sino em popover, a etiqueta de uso com popover, e nenhuma função a menos.

## O que eu não quero
- Página que mudou de lugar ficando também no lugar velho.
- Café, atualização e configurações na barra de título (o mockup não tem).
- Painel da direita lendo com ele fechado: cada aba lê só enquanto aparece, como as páginas de hoje.

## Como eu quero
- Telas: TitleBar.dc.html, StatusBar.dc.html, Inspector.dc.html, InspectorFiles.dc.html,
  InspectorHistory.dc.html, Main.dc.html, Bell.dc.html (descritas em `docs/design/work-frame/screens.md`; cada uma implementada como a
  seção dela diz, e conferida lado a lado com o mockup).
- Tokens: components.titleBar, components.search, components.breadcrumb, components.tab,
  components.titleIconButton, components.badge, components.statusBar, components.inspector,
  components.popover (valores exatos em `docs/design/work-frame/tokens.json`).
- Cada arquivo reescrito entra na lista de tools/check_design_literals.py: só valores de
  `DesignTokens`, nada digitado.
- **A. Barra de título.** Feita (2026-11-17), revisada e conferida na galeria: 44 pt com os botões da
  janela descidos para o meio (seguindo a moldura deles), a busca, o lugar, as abas na largura do
  título (× só sob o ponteiro, como no mockup), o "+" de 28 e o sino com o número (também na
  janela aberta depois). O botão do painel da direita entra com a fase C e o do quadro com o plano
  30. Plano original: `apps/macos/app/TitleBarView.swift` reescrita como a peça TitleBar: busca
  ⌘K, "projeto › tarefa", as abas (com o `StateGlyph` do que roda, a ativa com fundo), "+", e à
  direita quadro, sino (com o número) e painel da direita. Saem dela: o botão de space (o comando
  fica no ⌘K até o plano 27), o café, a atualização e as configurações. TabBarView.swift na cara
  nova. Arrastar, renomear e o menu das abas continuam.
- **B. Barra de status.** Na cara da peça StatusBar: projeto e branch, quantos trabalham e quantos
  precisam de você, Memória, a conta mais perto do limite (etiqueta âmbar acima de 80%), Local ou a
  máquina. Novos itens: o café (power.toggle) e a atualização (só com versão nova). A etiqueta de
  uso abre um popover com as contas (o conteúdo da página Accounts: uso, recarregar, abrir conta,
  personalizar). Os itens de hoje continuam personalizáveis.
- **C. O painel da direita.** Feature nova `inspector` (spec do plano 25): coluna de 320 pt,
  recolhível (⌥⌘I, inspector.toggle), com as abas Mudanças, Arquivos, Histórico e Memória; cada
  aba é a página de hoje (source-control, explorer, git-history, memory) com o cabeçalho de
  `SidebarHeader`, pelo catálogo que `SidebarWiring` já monta. git.show, `git.show-history`,
  explorer.focus e memory.show abrem a aba dele. Mudanças ganha o seletor Última rodada /
  Tarefa / Sem commit e os botões Commit e Abrir PR. As abas Files e History não estão desenhadas
  nos mockups: antes de implementar, desenhá-las no canvas com os tokens das abas, o dono ver, e
  então entram em screens.md e no tokens.json.
- **D. O sino.** O botão da barra abre um popover com o conteúdo de `AgentAttentionView` (Precisa de
  você e Atividade), Permitir/Negar, e a resposta das perguntas ali mesmo pela
  docs/adr/0036-owner-words-reach-the-agent.md (o campo, ou um botão por opção; digitado no terminal
  do agente só se ele ainda está na pergunta, senão "The agent moved on"), testada com o fake agent
  e com o Claude real na conta de teste. `agents.show-attention` e `agents.show-feed` abrem o
  popover.
- **E. Remoção.** Saem da barra lateral as páginas files, git, history, memory, attention e accounts
  (e a página AgentAccountsView.swift); SidebarSubtabs.swift sai; sidebar.items é migrado uma
  vez (o que estava aberto vira a aba aberta do painel da direita); `sidebar.page-1…9` viram
  apelidos das abas do painel (saem no 27); `CADEX_PERF_SIDEBAR` dá lugar a `CADEX_PERF_PANEL` em
  `apps/macos/app/PerfHooks.swift` e `tools/perf/run.py`. Specs e `CLAUDE.md` de app, sidebar,
  tabs, status-bar, power, updates, agents e das quatro páginas atualizados. Comandos que saem
  também saem do `MAC_ONLY`.
- **F. Varredura e fechamento.** Linhas do 26 no inventário em `saiu`; tools/find_unused.py;
  `make check`; `make perf` (a barra nova e o painel da direita aberto); prints ao lado dos mockups
  1, 2 e 5, e o dono vê.

## Como validar
- `make check` e `make perf` passam.
- Toda ação das páginas que mudaram é achada no ⌘K e na sua aba nova.
