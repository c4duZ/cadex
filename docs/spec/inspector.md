# inspector

## Para que serve
A coluna lateral: à esquerda do centro, logo depois do trilho, o que se sabe do projeto ou da
tarefa escolhida, em cinco páginas (Files, Changes, Sessions, Memory, Git graph), sem tirar os
terminais do centro (`../adr/0038-rail-and-side-column.md`, que tirou a coluna da direita da
`../adr/0035-work-frame.md`; mockup e texto em `../design/work-frame/screens.md`, seções Inspector
e Rail).

## Comportamento
- **Abrir e fechar:** os ícones das páginas no trilho (`sidebar.md`) abrem a coluna na página; o
  clique no ícone aceso a fecha. ⌘B (view.toggle-sidebar) e o botão da
  barra de título abrem e fecham; o botão fica aceso com ela aberta. O trilho fica sempre.
- **Largura:** 260 pt por padrão; arrastar a borda direita muda (de 240 a 640 pt, deixando ao
  centro pelo menos 320) e fica salva. Aberta ou fechada, a página e a largura voltam ao reabrir.
- **Fecha sozinha:** com o quadro aberto (volta quando o quadro sai: o segundo clique no ícone dele,
  ou o Esc), numa janela abaixo de 1000 pt (volta ao alargar, se o dono não a abriu ou fechou no
  meio) e na tela de início, sem projeto (volta quando um aparece). Uma página no centro (Projects,
  a página do projeto, a revisão) não a fecha, para nada pular.
- **Páginas, sem fileira no topo:** os ícones delas ficam no trilho, na ordem do dono
  (inspector.order). ⌃⌘1 a ⌃⌘5 (inspector.tab-1…5) vão às páginas nessa ordem; cada uma tem também
  o comando dela: explorer.focus (⇧⌘E) abre Files, git.show (⇧⌘G) Changes, project.sessions-column
  Sessions, memory.show Memory, git.show-history (⇧⌘L) Git graph.
- **O que a coluna mostra** segue o projeto escolhido no trilho, ou a tarefa do terminal com foco;
  nunca o `cd` de um terminal (Files e Changes não pulam de pasta enquanto você navega no shell).
- **Pé de cada página:** a linha de contexto, com as palavras à esquerda (a pasta em Files, com o
  caminho na dica; a branch em Changes, com ↑ ↓, e o clique troca de branch, git.switch-branch, ou
  "Git" fora de um repositório; numa tarefa, "<tarefa> · against <ponto de partida>") e até 3
  botões à direita (o resto no "⋯"), cada um rodando um comando:
  - Files: novo arquivo, nova pasta, recolher tudo; no "⋯", buscar arquivo e recarregar.
  - Changes: fetch, pull, push e revisar; no "⋯", trocar de branch, tudo para o stage, tudo fora do
    stage e atualizar; um indicador gira enquanto uma ação roda.
  - Sessions: no "⋯", todas as sessões na página do projeto.
  - Memory: tudo no "⋯", pelo nome: o que o agente vai ver, organizar o histórico com IA,
    reindexar, o histórico da memória, pausar ou retomar o agente de memória e atualizar.
  - Git graph: abrir o histórico numa aba.
- **Files** (o explorer de `explorer.md`): a árvore de arquivos da pasta do projeto ou da tarefa,
  com as ações de sempre.
- **Changes** (o painel de `source-control.md`): no topo, um menu pequeno com o escopo ("Last turn
  ▾": o que o agente mudou na última rodada, tudo da tarefa contra o ponto de partida, ou o que não
  tem commit) e o total ao lado ("N files +a −r"); um arquivo por linha com M (âmbar) ou A (verde),
  o nome, a pasta e +/−; no pé, o último resultado da checagem do projeto ("make check passed · 2 min
  ago", pelo que o shell contou, `terminal.md`) e os botões "Commit…" e "Open PR". Clicar num arquivo
  abre o diff no centro; stage, unstage, descartar e abrir ao lado ficam no clique direito e no ⌘K.
- **Sessions:** as conversas do projeto escolhido em Today, This week e Earlier, a mais nova
  primeiro, com a busca (no título e na nota: a conta, a tarefa, quando). O clique abre a página do
  projeto em Sessões nela, com o resumo e Retomar (`projects.md`). O histórico só é lido enquanto a
  página aparece; na primeira leitura, "Reading the history…".
- **Memory** (a página de `memory.md`): a busca, o que os agentes aprenderam hoje, a wiki por tipo
  e o tamanho do briefing; o clique numa página ou sessão abre a página do projeto na seção dela.
- **Git graph** (o histórico de `git-history.md`): cada commit em duas linhas, o grafo e a
  descrição sobre o autor, a idade e o hash curto; o clique abre os arquivos dele embaixo, o clique
  num arquivo abre o diff no centro; a dica completa sob o ponteiro; Show Commit Details in a Tab,
  Copy SHA e Open on Remote no clique direito e no ⌘K. Feito na primeira vez que a página aparece.
- Página que ninguém abriu não lê nada; com a coluna fechada, nenhuma lê.

## Estados
- **Sem projeto:** a coluna fica fechada (a tela de início ocupa o centro).
- **Fora de um repositório git:** Changes e Git graph mostram "Not a Git repository"; Files,
  Sessions e Memory funcionam.
- **Memória desligada** (memory.enabled): Memory explica o que está desligado e tem o botão para
  ligar.
- **Projeto sem conversas:** Sessions diz "No sessions in this project yet".

## Casos de borda
- Muitas mudanças (milhares de arquivos): a lista mostra os primeiros 500 e "N more", com o filtro.
- A borda arrastada além do que a janela deixa: a coluna para no limite (o centro guarda 320 pt).

## Critérios de aceite
- [x] Os ícones do trilho abrem a coluna na página; o aceso fecha; ⌘B e ⌥⌘I abrem e fecham.
- [x] O quadro fecha a coluna e sair dele a devolve; uma página no centro não a fecha (conferido
  no app, plano 36 F).
- [x] Abaixo de 1000 pt a coluna fecha (conferido numa janela de 900 pt).
- [x] Files e Changes seguem o projeto ou a tarefa, não o `cd`.
- [x] Sessions lista as conversas do projeto e o clique abre a página dele.
- [ ] Com a coluna fechada, nada é lido (medido no `make perf`).
