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
- **B. Quadro e corrida.** Feita (2026-11-17, idem): o quadro e a corrida no centro conferidos no app contra os mockups 7 e 8; a página de execução na cara nova fica para a fase D. Plano original: O quadro de todas as tarefas por estado, com filtros (corrida, execução,
  automações) e Nova corrida / Nova execução; a corrida no centro com as colunas do mockup 8
  (estado, tempo, custo, diff, barra do teto, Revisar e Escolher vencedora), na cara nova de
  RaceBoardView.swift; a execução como filtro do quadro, com a página dela na cara nova.
- **C. A gaveta.** Feita (2026-11-17, idem): conferida no app contra o mockup 9, e o ⌘↩ levando o terminal ao projeto. Plano original: Terminais rápidos fora de qualquer projeto, de baixo (⌃`, drawer.toggle), com
  abas, arrastar para cima, e ⌘↩ que leva um terminal da gaveta para um projeto.
- **D. Remoção.** O apelido `orchestration.new-race`; o que a página do projeto substituiu; toda
  linha que ainda está em `sai`.
- **E. Auditoria final.** Varrer `apps/macos/`, `docs/spec/`, os `CLAUDE.md`, o README e
  `tools/perf/` atrás de nomes da casca velha (sidebar de ícones, space, Tasks, Attention,
  Accounts como página, paneHeaders); tools/find_unused.py limpo; o inventário sem `sai`;
  `make check`, `make perf`; cada mockup ao lado do print do app, e o dono vê todos.
- **F. Fechamento.** README com a moldura nova, notas da release em inglês, o status dos planos 25 a
  30 no índice, a ADR 0035 sem pendência, e o plano do Windows com a moldura nova anotado como
  próximo.

## Como validar
- `make check` e `make perf` passam; tools/check_leftovers.py sem nenhuma linha em `sai`.
- O dono usa o Cadex com a moldura nova e aprova contra os mockups.
