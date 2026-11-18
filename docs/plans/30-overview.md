# Plano 30 — Moldura nova (6/6): visão geral, gaveta e a auditoria final

Depende de: plano 29 · Features: projects (a página do projeto), orchestration (quadro, corrida,
execução, automações), agents, memory, terminal (a gaveta), tabs · Decisões:
`docs/adr/0035-work-frame.md` · Mockups: 4 (página do projeto), 7 (quadro), 8 (corrida), 9
(gaveta) · Inventário: seção "Visão geral" e tudo o que ainda estiver em `sai`.

## O que eu quero
- A página do projeto, o quadro, a corrida e a gaveta como nos mockups.
- O fim da troca: nenhuma linha do inventário em `sai`, nada da casca velha no código, nas specs,
  nos manifestos, no README nem nos testes.

## O que eu não quero
- Fechar a série com "depois a gente tira": o que sobrou sai aqui.

## Como eu quero
- Telas: Project.dc.html, Board.dc.html, Race.dc.html, Drawer.dc.html (descritas em `docs/design/work-frame/screens.md`; cada uma implementada como a
  seção dela diz, e conferida lado a lado com o mockup).
- Tokens: components.project, components.board, components.race, components.drawer (valores
  exatos em `docs/design/work-frame/tokens.json`).
- Cada arquivo reescrito entra na lista de tools/check_design_literals.py: só valores de
  `DesignTokens`, nada digitado.
- **A. A página do projeto.** Feita (2026-11-17, junto da revisão do plano 29, a pedido do dono): conferida no app em 1440 e 900 pt. Plano original: No centro, ao clicar no nome do projeto: números (tarefas abertas,
  gasto da semana, PRs, memória), conversas recentes (as sessões dos agentes, inclusive as de fora
  do Cadex que a página Agents mostrava), automações com liga e desliga, contas usadas ali; a aba
  Memória do painel da direita aberta junto.
- **B. Quadro e corrida.** Feita (2026-11-17, idem): o quadro e a corrida no centro conferidos no app contra os mockups 7 e 8; as páginas da execução e da automação na cara nova (OrchestrationPage), conferidas no app. Plano original: O quadro de todas as tarefas por estado, com filtros (corrida, execução,
  automações) e Nova corrida / Nova execução; a corrida no centro com as colunas do mockup 8
  (estado, tempo, custo, diff, barra do teto, Revisar e Escolher vencedora), na cara nova de
  RaceBoardView.swift; a execução como filtro do quadro, com a página dela na cara nova.
- **C. A gaveta.** Feita (2026-11-17, idem): conferida no app contra o mockup 9, e o ⌘↩ levando o terminal ao projeto. Plano original: Terminais rápidos fora de qualquer projeto, de baixo (⌃`, drawer.toggle), com
  abas, arrastar para cima, e ⌘↩ que leva um terminal da gaveta para um projeto.
- **D. Remoção.** Feita (2026-11-17): o comando da corrida passou para worktrees.new-race (o de orchestration saiu), a página do projeto lê as sessões das outras máquinas pelo gancho que era da página Agents, a corrida sem terminal aqui virou página de cartões, e a seta e o sinal da página Agents saíram (sem uso). Plano original: O apelido `orchestration.new-race`; o que a página do projeto substituiu; toda
  linha que ainda está em `sai`.
- **E. Auditoria final.** Feita (2026-11-17): comentários, specs e textos da tela sem spaces, página Agents, Accounts nem barra lateral de ícones (o `@` da paleta dizia "abas e spaces"; o histórico do git, "no painel lateral"); o atalho ⌘↩ da gaveta corrigido (cmd+enter era recusado); tools/find_unused.py passou a não contar comentário nem a mensagem do fatalError como uso, o que achou três vistas mortas; na conferência contra os mockups, a página do projeto com o painel da direita aberto cortava os rótulos das colunas e deixava os botões colados no caminho, e o "+" aparecia ao lado das páginas (corrigidos); `make perf` limpo na terceira rodada completa (as duas antes falharam cada uma numa medida diferente, a troca de tema e a CPU depois do agente, depois a pasta pessoal, e cada uma passou 3 de 3 sozinha). Plano original: Varrer `apps/macos/`, `docs/spec/`, os `CLAUDE.md`, o README e
  `tools/perf/` atrás de nomes da casca velha (sidebar de ícones, space, Tasks, Attention,
  Accounts como página, paneHeaders); tools/find_unused.py limpo; o inventário sem `sai`;
  `make check`, `make perf`; cada mockup ao lado do print do app, e o dono vê todos.
- **F. Fechamento.** Feita (2026-11-17): o README com a moldura e a tabela de atalhos de hoje, as notas abaixo, o índice, a ADR 0035 e o Windows anotado como próximo (plano 32 desde a auditoria que virou o 31). Plano original: README com a moldura nova, notas da release em inglês, o status dos planos 25 a
  30 no índice, a ADR 0035 sem pendência, e o plano do Windows com a moldura nova anotado como
  próximo.

## Como validar
- `make check` e `make perf` passam; tools/check_leftovers.py sem nenhuma linha em `sai`.
- O dono usa o Cadex com a moldura nova e aprova contra os mockups.

## Notas da release (inglês)

As da série inteira (planos 25 a 30), a moldura nova.

```markdown
## A new frame (Mac)

- **One window, four places.** On the left, the tree of your work: each project with its tasks and terminals, and each agent's state beside it. In the center, tabs and panes. On the right, the selection's panel: Changes, Files, History and Memory (⌥⌘I, ⌃⌘1…4). On top, search, where you are (project › task), the board and the bell. The icon rail and its pages are gone; everything they did is a command in ⌘K.
- **Projects instead of spaces.** A project is a repository's folder with the tabs open in it, restored when Cadex opens. Spaces from 2.2 are not carried over: open each repository again (⌃⌘N) and it stays. ⇧⌘S switches, ⌃⌘N opens one, ⌘J jumps to any project, task or terminal.
- **A home screen.** Opening Cadex with no project shows a prompt box, the Terminal, Agent, Task and Race cards, and your recent projects with their terminals' state. Write what you want and pick a card: the agent opens with your words.
- **New Task is ⌘N.** One sheet for a task and a race: the branch, the base, one agent or several (account, model, machine), and the prompt. New window moved to ⇧⌘N.
- **Dressed terminals.** Each pane's header shows the agent's state, account, cost and time, and the command the shell is running; the tab shows the same state. Cadex Night is the default theme.
- **The project's page.** Click a project's name: open tasks, this week's spend, PRs, memory, recent conversations (also those on your other machines), its automations with their switch, and the accounts used there.
- **The board and the race in the center.** The board (the title bar's button) shows every task by state, filtered by race, run or automations. A race shows its agents side by side, each with state, time, cost, diff and its cap. A run's page and an automation's history use the same cards.
- **The drawer.** Quick terminals outside any project slide up from the bottom (⌃`); ⌘↩ moves one into the project.
```
