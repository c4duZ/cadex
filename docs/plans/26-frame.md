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
  components.popover, components.bell (valores exatos em `docs/design/work-frame/tokens.json`).
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
- **B. Barra de status.** Feita (2026-11-17), revisada e conferida na galeria: a cara dos tokens, os
  itens Project, Agents (duas contagens com o ponto de estado), Memory (sem a contagem de páginas:
  nada lê a wiki só para o item), o café e a atualização (saíram da barra de título), a etiqueta
  de uso no formato do mockup e âmbar acima de 80% (ainda a conta do terminal com foco, a escolha
  do dono de 2026-10-21; o popover com todas as contas fica), o padrão novo e a migração única
  (versão 3). Plano original: Na cara da peça StatusBar: projeto e branch, quantos trabalham e quantos
  precisam de você, Memória, a conta mais perto do limite (etiqueta âmbar acima de 80%), Local ou a
  máquina. Novos itens: o café (power.toggle) e a atualização (só com versão nova). A etiqueta de
  uso abre um popover com as contas (o conteúdo da página Accounts: uso, recarregar, abrir conta,
  personalizar). Os itens de hoje continuam personalizáveis.
- **C. O painel da direita.** C1 feita (2026-11-17, o dono aprovou os desenhos de Files e History):
  a feature `apps/macos/features/inspector/`, a coluna de 320 com as abas e "⌥⌘I", a linha de
  contexto com os botões da aba (até 3 e o "⋯", desenhados no mockup Inspector), as páginas de
  antes dentro (saíram da barra lateral), inspector.toggle (⌥⌘I) e o botão da barra de título,
  inspector.visible e inspector.tab salvos, e os ganchos de teste CADEX_PERF_PANEL e
  CADEX_PERF_SNAPSHOT (a janela de teste abre noutra mesa, onde o screencapture falha). C2a feita
  (2026-11-17): Changes no desenho (o seletor Last turn / Task / Uncommitted, as linhas com letra,
  pasta e +/−, Commit… e Open PR; a última rodada pelos hooks de edição e de parada, agora sempre no
  kit; a linha "make check passed" espera uma fonte). C2b feita (2026-11-17): Files e History nos desenhos
  aprovados (a árvore de 28 com recuo de 16 e a linha escolhida; os commits em duas linhas com o
  grafo de uma cor e o ponto azul no HEAD, os arquivos do commit aberto com +/−). C2c feita
  (2026-11-17): Memory no desenho (a busca, memory.search; LEARNED TODAY com as páginas de hoje; a
  WIKI com as marcas e as contagens; o estado numa linha; a nota do briefing; as propostas ficam,
  em cartões). C2d feita (2026-11-17):
  a borda arrastável (inspector.width, de 240 a 640, salva ao soltar) e a janela estreita (abaixo de
  1000 pt, abrir o painel recolhe a barra lateral, e fechá-lo a devolve). Fase C inteira feita. Plano original: Feature nova `inspector` (spec do plano 25): coluna de 320 pt,
  recolhível (⌥⌘I, inspector.toggle), com as abas Mudanças, Arquivos, Histórico e Memória; cada
  aba é a página de hoje (source-control, explorer, git-history, memory) com o cabeçalho de
  `SidebarHeader`, pelo catálogo que `SidebarWiring` já monta. git.show, `git.show-history`,
  explorer.focus e memory.show abrem a aba dele. Mudanças ganha o seletor Última rodada /
  Tarefa / Sem commit e os botões Commit e Abrir PR. As abas Files e History não estão desenhadas
  nos mockups: antes de implementar, desenhá-las no canvas com os tokens das abas, o dono ver, e
  então entram em screens.md e no tokens.json.
- **D. O sino.** D1 feita (2026-11-17): o popover do sino no desenho do mockup (`AnchoredPanel` em
  `apps/macos/shared/menus/AnchoredPanel.swift`, abre no clique, fecha fora e no Esc; o conteúdo
  em `apps/macos/features/agents/AgentAttentionView.swift`), Allow/Deny/Go to tab, "EARLIER", a
  Atividade com os filtros, e a página do sininho saiu da barra lateral. D2 feita (2026-11-17): responder a pergunta pelo
  sino. Testado antes com o Claude real (conta bkdg, haiku, Claude Code 2.1.326): o aviso dele já
  traz as opções ("Which color? (Red · Blue)"), o número da opção escolhe na hora, e o número
  seguinte às opções, o texto e Enter mandam palavras próprias, com 0,3 s entre as teclas.
  `apps/macos/features/agents/AgentAnswer.swift`, os botões das opções e o campo no cartão, o
  comando agents.answer, e o app digita só se o agente ainda pergunta aquilo (senão "The agent
  moved on" no feed). As opções vêm do hook PreToolUse do AskUserQuestion, não do aviso: um
  rótulo com " · " se partia no aviso, e formulário e múltipla escolha ficam para a aba (o dono
  pediu, 2026-11-17; conferido com o Claude real). Plano original: O botão da barra abre um popover com o conteúdo de `AgentAttentionView` (Precisa de
  você e Atividade), Permitir/Negar, e a resposta das perguntas ali mesmo pela
  docs/adr/0036-owner-words-reach-the-agent.md (o campo, ou um botão por opção; digitado no terminal
  do agente só se ele ainda está na pergunta, senão "The agent moved on"), testada com o fake agent
  e com o Claude real na conta de teste. `agents.show-attention` e `agents.show-feed` abrem o
  popover.
- **E. Remoção.** Feita (2026-11-17): a página Accounts e AgentAccountsView.swift saíram (as
  contas no cartão do item de uso, clicáveis; agents.show-accounts o abre fixo; renomear virou
  agents.rename-account); a versão 4 das configurações tira do sidebar.items, uma vez, as páginas que
  saíram; ⌃⌘1 a ⌃⌘4 (sidebar.page-N) abrem as abas do painel; o CADEX_PERF_SIDEBAR fica até o 27,
  porque Agents e History seguem na barra (o inventário diz). Plano original: Saem da barra lateral as páginas files, git, history, memory, attention e accounts
  (e a página AgentAccountsView.swift); SidebarSubtabs.swift sai; sidebar.items é migrado uma
  vez (o que estava aberto vira a aba aberta do painel da direita); `sidebar.page-1…9` viram
  apelidos das abas do painel (saem no 27); `CADEX_PERF_SIDEBAR` dá lugar a `CADEX_PERF_PANEL` em
  `apps/macos/app/PerfHooks.swift` e `tools/perf/run.py`. Specs e `CLAUDE.md` de app, sidebar,
  tabs, status-bar, power, updates, agents e das quatro páginas atualizados. Comandos que saem
  também saem do `MAC_ONLY`.
- **F. Varredura e fechamento.** Feita (2026-11-17): o tools/find_unused.py achou um resto (o
  preenchimento do botão do café, que saiu da barra de título) e ele saiu; o inventário sem peça do 26
  sobrando (check_leftovers); `make check` e `make perf` passaram, o painel da direita aberto; os
  prints na galeria (a janela ao lado do mockup 2; o sino, mockup 5, nas fases D1 e D2). Plano 26
  feito. Plano original: Linhas do 26 no inventário em `saiu`; tools/find_unused.py;
  `make check`; `make perf` (a barra nova e o painel da direita aberto); prints ao lado dos mockups
  1, 2 e 5, e o dono vê.

## Como validar
- `make check` e `make perf` passam.
- Toda ação das páginas que mudaram é achada no ⌘K e na sua aba nova.
