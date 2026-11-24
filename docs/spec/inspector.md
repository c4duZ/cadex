# inspector

## Para que serve
A vista Arquivos da barra lateral (`sidebar.md`): a árvore do lugar escolhido (Files) e, discreta,
as mudanças dele (Changes), sem tirar os terminais do centro
(`../adr/0039-sidebar-with-work-and-files.md`, plano 38). Até o plano 38 era a coluna lateral, ao
lado do trilho, com cinco páginas (`../adr/0038-rail-and-side-column.md`); Sessions, Memory e o
grafo do git foram para a página do projeto (`projects.md`) e para uma página própria
(`git-history.md`).

## Comportamento
- **Abrir:** Arquivos no seletor da barra lateral (sidebar.show-files, ⇧⌘2), explorer.focus (⇧⌘E)
  para Files, git.show (⇧⌘G) para Changes, ⌃⌘1 e ⌃⌘2 (inspector.tab-1 e -2) para uma e outra, e o
  "N mudanças · ver" no fim da árvore. Cada um abre a barra lateral se ela estiver fechada. ⌘B
  (view.toggle-sidebar) fecha e abre a barra inteira; a vista e a largura voltam ao reabrir
  (inspector.visible, inspector.tab, inspector.width).
- **O que ela mostra** segue o projeto escolhido na barra lateral, ou a tarefa do terminal com
  foco; Changes e a busca não pulam de pasta enquanto você navega no shell. A árvore de Files desce
  para a subpasta do terminal com foco quando ele está numa (o terminal em `app/` mostra `app/`, com
  o nome do projeto ou da tarefa e a subpasta no cabeçalho; o dono, 2026-11-24).
- **O cabeçalho em palavras**, no topo da vista: numa tarefa, "tarefa de <projeto> · contra
  <ponto de partida>"; no main, o nome e o caminho.
- **Files** (o explorer de `explorer.md`): a árvore de arquivos da pasta do projeto ou da tarefa,
  com as ações de sempre, o M e o A alinhados à direita. A linha de ações: novo arquivo, nova pasta,
  recolher tudo; no "⋯", buscar arquivo e recarregar. No fim, "N mudanças · ver" (some sem mudança
  ou com Changes à vista).
- **Changes** (o painel de `source-control.md`), na própria barra: no topo, um menu pequeno com o
  escopo ("Last turn ▾": o que o agente mudou na última rodada, tudo da tarefa contra o ponto de
  partida, ou o que não tem commit) e o total ao lado ("N files +a −r"); um arquivo por linha com M
  (âmbar) ou A (verde), o nome, a pasta e +/−; no pé, o último resultado da checagem do projeto
  ("make check passed · 2 min ago", pelo que o shell contou, `terminal.md`) e os botões "Commit…"
  (forte quando há o que commitar) e "Open PR". Clicar num arquivo abre o diff no centro; stage,
  unstage, descartar e abrir ao lado ficam no clique direito e no ⌘K. A linha de contexto diz a
  branch com ↑ ↓ (o clique troca de branch, git.switch-branch), "Git" fora de um repositório, e numa
  tarefa "<tarefa> · against <ponto de partida>"; as ações: fetch, pull, push e revisar; no "⋯",
  trocar de branch, tudo para o stage, tudo fora do stage e atualizar; um indicador gira enquanto
  uma ação roda.
- **O que saiu daqui:** as Sessões são a seção Sessões da página do projeto (project.show-sessions);
  a Memória, a seção Memória (memory.show abre a página nela); o grafo do git abre numa aba
  (git.show-history, ⇧⌘L, roda git.history-in-tab).
- Com a barra lateral fechada, a vista Arquivos não lê nada.

## Estados
- **Sem projeto:** a barra lateral mostra os recentes, sem o seletor (`sidebar.md`, nada aberto).
- **Fora de um repositório git:** Changes mostra "Not a Git repository" e não há "N mudanças";
  Files funciona.

## Casos de borda
- Muitas mudanças (milhares de arquivos): a lista mostra os primeiros 500 e "N more", com o filtro.
- A borda arrastada além do que a janela deixa: a barra para no limite (o centro guarda 320 pt).

## Critérios de aceite
- [x] ⇧⌘2, ⌃⌘1 e ⌃⌘2 mostram Files e Changes na barra lateral; ⌘B abre e fecha.
- [x] O quadro fecha a barra e sair dele a devolve; uma página no centro não a fecha (conferido
  no app, plano 36 F).
- [x] Changes segue o projeto ou a tarefa, não o `cd`; Files mostra a subpasta do terminal.
- [x] O cabeçalho em palavras e "N mudanças · ver" abrindo Changes (conferido no app, plano 38 D).
- [ ] Com a barra fechada, nada é lido (medido no `make perf`).
