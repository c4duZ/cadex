# Plano 38 — A barra lateral com Trabalho e Arquivos

Constrói a `docs/adr/0039-sidebar-with-work-and-files.md`, pela referência desenhada em
`docs/design/sidebar/6-estrutura-ideal.html` (as quatro situações, cada peça numerada com o que é e
o que o clique faz). O dono aprovou em 2026-11-19 ("pode fazer").

## O que eu quero
- Em cima, onde estou e o que está aberto aqui; à esquerda, para onde vou e quem precisa de mim; no
  centro, os terminais; embaixo, o ambiente. Cada fato numa casa só.
- Nunca perder um agente que espera: a fila no topo da barra lateral, em qualquer vista e largura, e
  o sinal subindo para o que está à vista quando o que o contém some.
- Palavras em vez de ícones onde a pessoa escolhe para onde ir.

## O que eu não quero
- Painel à direita (o dono, 2026-11-19).
- O mesmo fato em dois lugares (a conta, o projeto, os pedidos).
- Ação que não é comando (ADR 0005): cada clique novo roda um comando pelo id.
- Valor digitado: os tokens novos entram em `docs/design/work-frame/tokens.json`, com o mockup.

## Como eu quero
- [x] A. Os tokens e o mockup: a barra lateral, a fila, o seletor de vistas, as linhas da lista, o
  lugar em cima e o botão Revisar no `docs/design/work-frame/tokens.json` e num mockup .dc.html
  tirado da referência; `tools/check_design_tokens.py` passando.
  Feito: components.workSidebar e components.place, gerados em
  `apps/macos/shared/looks/DesignTokensSidebar.swift`; o mockup é WorkSidebar.dc.html (a seta das
  linhas ficou com 10 pt e o recuo das tarefas com 22, os tokens mais perto da referência).
- [ ] B. A barra lateral, vista Trabalho: a lista de projetos (avatar, nome, estado e terminais;
  aberto, o main e as tarefas com o fio guia; o aberto ou fechado guardado; o clique no nome ao
  último lugar, num item as abas dele em cima; o clique direito com o menu do projeto de hoje),
  "Novo projeto…" e o pé (Quadro, Automações, Máquinas com algum host); a ordem e o fixado de hoje
  continuam (arrastar). Ela toma o lugar do trilho e da coluna; ⌘B mostra e esconde.
- [ ] C. A fila "Precisa de você": o cartão âmbar no topo, das mesmas fontes do sino (os pedidos
  abertos), cada linha com o agente, o projeto, o pedido em frase e o tempo; o clique leva ao
  terminal; a etiqueta âmbar no projeto fechado e a marca na borda da lista rolada; a pílula na
  barra de cima com a barra lateral fechada. O sino sai da barra de cima; o feed fica no ⌘K.
- [ ] D. A vista Arquivos: o seletor "Trabalho | Arquivos" (⇧⌘1, ⇧⌘2), a árvore do lugar (o
  explorer de hoje) com o cabeçalho em palavras, e "N mudanças · ver" mostrando Mudanças na própria
  barra (o painel do git de hoje, com Commit e Abrir PR); ⇧⌘G e o branch da barra de baixo abrem
  Mudanças; Esc volta.
- [ ] E. A barra de cima: o botão da barra lateral na borda de entrada, o lugar ("projeto › tarefa
  ▾" com o menu: trocar de projeto ou tarefa com busca, voltar ao main, a página do projeto), as abas
  do lugar, "» N", "+", Revisar só numa tarefa e Buscar ⌘K no fim; saem a conta, o quadro, o sino e a
  engrenagem. A tarefa deixa de ser item da barra de abas e o "‹ projeto" sai.
- [ ] F. A barra de baixo: os itens de hoje sem a contagem de pedidos; o clique no projeto · branch
  abre Mudanças, nos agentes abre o quadro, na conta troca de conta. Sessões, Memória e o grafo do
  git saem da barra lateral para a página do projeto (e o grafo como página).
- [ ] G. A janela estreita (abaixo de 1000 pt): a faixa de 56 pt com a caixa âmbar, os quadrados dos
  projetos e, no pé, Arquivos (por cima do centro, Esc fecha) e Quadro; a barra de baixo encurtada
  com o "…". E nada aberto: os recentes na barra lateral, Novo projeto… e Abrir pasta… ⌘O, a tela de
  início no centro e a barra de baixo só com o que vale sem projeto.
- [ ] H. Fechar: o que sai (o trilho, a coluna lateral, as páginas Sessions/Memory/Git graph da
  coluna, o item de tarefa nas abas) entra no inventário da moldura em `saiu`; as specs (sidebar,
  inspector, tabs, status-bar, projects, home, agents), os CLAUDE.md, o `docs/CONTEXT.md` e a ADR 0038
  com a nota; a paridade (`MAC_ONLY`), `make check`, `make perf` só se o dono pedir, e a dist.

- Telas: WorkSidebar.dc.html (descrita em `docs/design/work-frame/screens.md`; as quatro situações em
  `docs/design/sidebar/6-estrutura-ideal.html`).
- Tokens: components.workSidebar, components.place (valores exatos em
  `docs/design/work-frame/tokens.json`).

## Como validar
- Cada fase: os testes da feature e o print da instância de teste ao lado da referência
  (`docs/design/sidebar/6-estrutura-ideal.html`), na mesma situação; o que não deu para conferir no
  app é dito.
