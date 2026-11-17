# Plano 29 — Moldura nova (5/6): tela de início, ⌘N e ⌘J

Depende de: plano 28 · Features: home (nova), worktrees, orchestration, agents, projects,
command-palette, shortcuts · Decisões: `docs/adr/0035-work-frame.md`,
`docs/adr/0033-cadex-launches-agents.md` · Mockups: 0 (tela de início), 0b (Nova tarefa), 6 (⌘J) ·
Inventário: seção "Entradas" e os apelidos do 28.

## O que eu quero
- Duas portas só: a tela de início e o ⌘N. Terminal, agente, tarefa e corrida nascem delas.
- Tarefa e corrida na mesma folha: onde roda e quem faz; com 2+ agentes é corrida, com teto.

## O que eu não quero
- As folhas New Task e New Race separadas, ou alertas em fila no lugar da folha.
- A tela de início no caminho de quem já estava trabalhando: o Cadex volta onde parou.

## Como eu quero
- Telas: Home.dc.html, NewTask.dc.html, Switcher.dc.html (descritas em `docs/design/work-frame/screens.md`; cada uma implementada como a
  seção dela diz, e conferida lado a lado com o mockup).
- Tokens: components.home, components.newTask, components.sheet (valores exatos em
  `docs/design/work-frame/tokens.json`).
- Cada arquivo reescrito entra na lista de tools/check_design_literals.py: só valores de
  `DesignTokens`, nada digitado.
- **A. Tela de início.** Feita (2026-11-17): feature `home` (a tela comparada com o mockup no app),
  os recentes no projects.json, fechar o último projeto mostra a tela, aberto pelo Dock sem nada
  salvo também; o Enter abre o agente com o pedido (conferido com um `claude` real; achou e
  consertou o "--" que faltava antes do pedido no `cadex claude`); ⇧⌘A passou do power.toggle ao
  agents.open-account. Plano original: Feature `home`: aparece sem projeto aberto e por home.show; a caixa "o que
  você quer fazer em <projeto>" (Enter abre um terminal com o agente e o pedido, pela ADR 0036;
  o projeto pelo menu do nome ou "@"), a
  conta e o lugar abaixo dela; os quatro cartões (Terminal ⌘T, Agente ⌘⇧A, Tarefa ⌘N, Corrida);
  projetos recentes com o estado; Abrir pasta ⌘O e Clonar.
- **B. Nova tarefa (⌘N).** Feita (2026-11-17): a folha na feature worktrees, ligada pelo
  `../../apps/macos/app/NewTaskWiring.swift`; tarefa na pasta, numa cópia e corrida conferidas no
  app com o `claude` falso (a corrida numa pasta que a conta de teste já confia); a conta que não
  confia trava a corrida com "Open Claude to Trust"; o Codex de uma conta como agente (`cadex
  codex`, uma corrida Claude + Codex conferida com os falsos) e o pedido na tarefa remota. Plano original: Uma folha só: o pedido, onde (pasta do projeto ou cópia separada com o
  nome do branch), quem faz (lista de agentes com conta e uso; "+ Adicionar outro agente"); com 2+
  aparece o aviso de corrida com o teto e o botão vira Iniciar corrida. Usa o que
  WorktreesController.plan e a corrida já fazem; os "sim" que hoje são alertas (autorizar pasta,
  hooks novos, confiança) viram linhas da própria folha.
- **C. ⌘J.** Feita (2026-11-17): view.jump na paleta, com as linhas da árvore e as sessões de fora,
  comparado com o mockup no app (uma corrida de verdade com o `claude` falso). O ⇧⌘N da janela nova e o ⌘N da Nova tarefa entraram já na fase A (os cartões da tela
  de início mostram o atalho). Plano original: Pular por atenção (precisa de você, trabalhando, pronto) ou começar tarefa, como no
  mockup 6. window.new vai para ⇧⌘N.
- **D. Remoção.** Feita (2026-11-17): saiu o NewRaceForm.swift (as contas das outras folhas em
  AccountChoice.swift); o fluxo de alertas, a leitura de tabs.paneHeaders e os apelidos do 28 já
  tinham saído (fases A–B e plano 28); orchestration.new-race abre a folha com dois agentes e fica
  para o plano 30; CADEX_PERF_RACE_FORM virou CADEX_PERF_NEW_TASK. O ⌘1…⌘9 do ⌘J passa na frente do
  ir-para-a-aba (`takenFirst`), conferido no app com a tecla. Plano original: Saem: NewRaceForm.swift, o fluxo de alertas do New Task em
  WorktreesWiring.swift, a leitura de tabs.paneHeaders, os apelidos do 28;
  `orchestration.new-race` vira apelido do ⌘N com dois agentes (sai no 30). `CADEX_PERF_RACE_FORM` passa a abrir a folha nova. Specs e `CLAUDE.md` de
  worktrees, orchestration, home, shortcuts.
- **E. Varredura e fechamento.** Linhas do 29 em `saiu`; tools/find_unused.py; `make check`; `make
  perf`; prints ao lado dos mockups 0, 0b e 6, e o dono vê.

## Como validar
- `make check` e `make perf` passam.
- Uma tarefa e uma corrida criadas pela folha nova, no app, com agentes falsos.
