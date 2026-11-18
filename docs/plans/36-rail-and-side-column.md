# Plano 36 — O trilho e a coluna lateral

O dono, 2026-11-18: não gosta da coluna da direita e quer a barra lateral só à esquerda, com os
terminais ocupando o resto. O estudo e as rodadas de mockup terminaram na
`docs/adr/0038-rail-and-side-column.md`, com os mockups em `docs/design/sidebar/` (1 a 3). Ele
escolheu ainda: com tudo fechado fica a tela de início de hoje (a página Projects só abre pelo
botão no pé do trilho); o terminal aberto sem projeto fica em abas sem projeto, que aparecem quando
nenhum projeto está aceso; ⌘1 a ⌘9 continuam nas abas, contando as que a barra mostra; e a ordem
é este plano agora, a fase H do 34 depois.

## O que eu quero
- À esquerda, o trilho (56 pt) e a coluna lateral (260 pt, arrastável). A coluna da direita sai.
- O trilho com os projetos (a imagem e o nome dados pelo dono, a peça de estado, o ponto de
  terminal aberto), o "+", os ícones das páginas e, no pé, Projects, Automations e Remote (este só
  havendo host).
- A coluna lateral com as páginas do projeto escolhido, trocadas pelos ícones do trilho: Files,
  Changes, Sessions, Memory e Git graph; cada página com o pé dela; nada no topo.
- Os terminais só nas abas de cima; a tarefa como uma aba que entra e "‹ projeto" que sai; "» N"
  quando não cabe.
- Cada tela igual aos mockups.

## O que eu não quero
- A lista de terminais na coluna lateral.
- Página que pula: abrir Projects ou a página de um projeto não fecha a coluna.
- Feature importando o miolo de outra: o trilho só desenha o que o app monta (como a árvore hoje),
  e as páginas da coluna chegam do app pelas portas de entrada das features.
- Valor digitado na moldura: tokens novos em `docs/design/work-frame/tokens.json` (components.rail e
  o iconTabs de components.inspector, a coluna lateral), gerados como os de hoje.

## Como eu quero
- [x] A. O trilho e a coluna no lugar: a `sidebar` ganha o trilho (os projetos com a imagem, a peça
  de estado e o ponto de terminal aberto; o "+"; o pé com Projects e Automations) no lugar da
  árvore; a coluna da `inspector` muda para a esquerda, ao lado do trilho, com os ícones no topo
  (Files, Changes, History com o nome Git graph, Memory) e sem a linha de contexto. Clicar num
  projeto troca as abas e a coluna; Files e Changes seguem o projeto escolhido, não o `cd`. ⌘B fecha
  e abre a coluna; ⌥⌘I deixa de existir (o comando vira o mesmo do ⌘B). Os tokens novos.
  Feita em 2026-11-18: o trilho (`RailView`) e a coluna à esquerda com os ícones e a linha de
  contexto no pé; conferida com cliques de verdade numa instância de teste (o projeto B troca as
  abas e a coluna; o ícone Files troca a página; o ⌘B fecha a coluna e o trilho fica; arrastar a
  borda leva a coluna de 260 a 343 pt e a largura fica salva; o tema claro pinta trilho e coluna).
  Um arraste de teste dentro de uma lista ou do terminal deixa a janela em branco, também na dist de
  antes da fase A: é o arraste sintético numa janela sem foco, não conferido com o mouse de verdade. A árvore fica fora da tela, ainda montada
  para o sidebar.find, até a fase G; o botão da coluna na barra de título continua (abre e fecha a
  coluna).
- [x] B. Editar o projeto (o dono pediu desde o começo; vem antes de tudo o mais, 2026-11-18): o
  nome que ele quiser, não o da pasta; a imagem (uma foto ou imagem do Mac, também arrastada para o
  quadrado do trilho, um emoji, ou a letra numa cor); a cor do projeto; tudo numa folha "Edit
  project", aberta pelo clique direito no quadrado do trilho ("Edit name and image…") e pelo ⌘K, e a
  mesma folha cria um projeto pelo "+" (nome, imagem, pasta). A imagem fica copiada para a pasta do
  Cadex (Application Support), não lida da origem a cada vez, e aparece no trilho, na página
  Projects, na página do projeto e no seletor ⇧⌘S. O clique direito no quadrado, inteiro: New
  terminal, New task, Edit name and image…, Pin/Unpin, Project settings…, Show in Finder, Copy path,
  Close terminals e Remove from the sidebar, cada um um comando.
  Feita em 2026-11-18: a folha (nome, imagem com Choose Image… e Remove, emoji, cor) pelo clique
  direito e pelo ⌘K (project.edit), criando pelo "+" (project.create), a imagem solta no quadrado,
  o clique direito inteiro (com Pin/Unpin, Close Terminals e Remove from the Sidebar: o fixar veio
  para cá da fase E), a imagem no trilho, nos cartões da página Projects, no cabeçalho da página do
  projeto e no ⇧⌘S; o projeto fixado sem terminal fica no trilho e o clique abre um; os abertos não
  fixados depois de uma linha. Conferido no app: o trilho com imagem, emoji, fixado sem terminal e a
  linha; o menu; a folha; as duas páginas; o ⇧⌘S; o clique no fixado abrindo o terminal. Visto uma
  vez e não reproduzido em mais duas: o halo no projeto errado depois desse clique (a janela de
  teste estava em foco). Não conferido com o mouse: o seletor de imagem, soltar uma imagem, criar
  pela folha.
- [x] C. As páginas da coluna: os ícones das páginas saem do topo da coluna e vão para o trilho,
  abaixo dos projetos e do "+", depois de uma linha (o dono, 2026-11-18): o clique abre a coluna na
  página, mesmo fechada, e o clique no aceso a fecha; a coluna sem fileira no topo (feito em
  2026-11-18 e conferido no app: com a coluna fechada pelo ⌘B, o clique em Files a abre em Files,
  aceso). A página Sessions (feita em 2026-11-18): as conversas do projeto por quando, a busca, o
  histórico lido só enquanto ela aparece e "Reading the history…" antes da primeira leitura; o
  clique abre a página do projeto em Sessions com o resumo e o Resume; conferida no app. O Changes
  com o escopo num menu pequeno e o total ao lado (feito e conferido no app, 2026-11-18). Os pés já
  vinham da fase A (a linha de contexto no pé de cada página, com os botões dela). Os pés (Files: a pasta, criar e buscar; Changes: a checagem, Commit,
  Open PR e a branch com ↑↓; Memory: o briefing; Git graph: a branch e abrir numa aba); Changes com
  o escopo num menu pequeno, o total e o +/− de cada arquivo; a página nova Sessions (agora, hoje,
  antes; o clique mostra o resumo no centro, como na página do projeto); a ordem Files, Changes,
  Sessions, Memory, Git graph.
- [ ] D. As abas: a tarefa como aba (ícone de branch, estado, seta) que troca a barra para os
  terminais dela; "‹ projeto" volta; "» N" com a lista de todos quando não cabem; ⌘1 a ⌘9 pela
  ordem mostrada; as abas sem projeto quando nenhum projeto está aceso.
- [ ] E. Ordenar: a ordem arrastada (projetos e ícones da coluna; arrastar um aberto para cima da
  linha o fixa). A página Projects só
  pelo pé do trilho, sem editar nada, e o cartão abrindo a página do projeto (com Open terminal).
- [ ] F. Quando a coluna fecha e o pé: o quadro fecha a coluna e o segundo clique no ícone dele a
  devolve (conferir o bug que o dono viu); a janela estreita; Remote no pé (os hosts do ssh e as
  máquinas da tailnet, Connect); o item Memory da barra de status abrindo a página Memory da coluna.
- [ ] G. Fechar: as specs (sidebar, inspector, tabs, projects, home, status-bar, ssh), os CLAUDE.md,
  o inventário da moldura (`docs/design/work-frame/inventory.md`) com a árvore e a coluna da
  direita em `sai`, a paridade (`MAC_ONLY`), `make check`, `make perf` e a dist.

Fora deste plano, anotados na ADR 0038 ("Levantado junto"): o celular controlando a sessão, as
contas na barra de cima, o item Ports sozinho, o aviso do computer-use e "All sessions" na página
Projects. Cada um vira plano próprio.

- Telas: Rail.dc.html (descrita em `docs/design/work-frame/screens.md`; os estudos aprovados em
  `docs/design/sidebar/`).
- Tokens: components.rail, components.inspector (iconTabs e a largura de 260; valores exatos em
  `docs/design/work-frame/tokens.json`).

## Como validar
- Cada fase: os testes da feature, o print da instância de teste ao lado do mockup, e os cliques de
  verdade (`CADEX_PERF_CLICK`, `CADEX_PERF_HOVER`) no que a fase mexe, dizendo o que não foi
  conferido.
- No fim, `make check` e `make perf` (a coluna fechada não lê nada).
