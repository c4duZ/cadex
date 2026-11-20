# sidebar

## Para que serve
A barra lateral: à esquerda do centro, para onde vou e quem precisa de mim. No topo, a fila
"Precisa de você"; embaixo dela, duas vistas com nome, **Trabalho** (os projetos e os terminais de cada um, antes o main e as
tarefas) e **Arquivos** (a árvore do lugar, com Mudanças discreta no fim); no pé, o que é de todos os
projetos (`../adr/0039-sidebar-with-work-and-files.md`, plano 38; a referência desenhada em
`../design/sidebar/6-estrutura-ideal.html`; tokens components.workSidebar em
`../design/work-frame/tokens.json`). Os terminais ficam só nas abas de cima (`tabs.md`); onde se
está fica no lugar, no começo da barra de cima. Ela tomou o lugar do trilho e da coluna lateral
(`../adr/0038-rail-and-side-column.md`); do trilho ficou só a faixa da janela estreita.

## Comportamento
- **Mostrar e esconder:** ⌘B (view.toggle-sidebar) e o botão da barra lateral, o primeiro da barra
  de cima, aceso com ela aberta. Aberta ou fechada, volta assim ao reabrir. sidebar.show (⇧⌘J) só
  abre.
- **Largura:** 248 pt; arrastar a borda direita muda (de 240 a 640 pt, deixando ao centro pelo menos
  320) e fica salva.
- **A fila "Precisa de você"**, presa no topo em qualquer vista: um cartão âmbar que só aparece com
  pedido aberto (permissão, pergunta) de algum agente, com "PRECISA DE VOCÊ" e o número. Cada linha
  diz quem pede, o projeto, o pedido em frase ("quer rodar `npm install stripe`", "quer usar Edit:
  App.swift", ou a própria pergunta) e há quanto tempo ("agora", "3m"). O clique leva ao terminal do
  agente, onde está o diálogo do próprio Claude (agents.go-to-request). É a mesma fonte do quadro de
  atenção (`agents.md`), que abre da fila (agents.show-attention) com a lista e o feed.
- **O seletor "Trabalho | Arquivos"**, na largura toda, com palavras: Trabalho (sidebar.show-work,
  ⇧⌘1) é o padrão, Arquivos (sidebar.show-files, ⇧⌘2) o segundo.
- **Trabalho:** "PROJETOS" e, por projeto, uma linha com a seta (dobra e desdobra; aberto ou
  fechado fica no arquivo dos projetos), o avatar (a imagem, senão o emoji, senão duas letras sobre
  a cor do projeto), o nome e, à direita: a peça de estado e quantos terminais; "nada aberto" sem
  terminal; ou, com o projeto dobrado e algum agente dele esperando você, a etiqueta âmbar com o
  número de pedidos (o único âmbar da lista, a mesma conta da fila).
  - Desdobrado, embaixo dele presos por um fio guia: um item por terminal aberto no projeto (o
    nome que a aba usa: o agente, o comando que roda ou a pasta), com o estado; o de uma tarefa vem
    com o nome dela antes ("kite-fix · Claude"). O aceso é o terminal com foco; o clique vai a ele.
    Até 2026-11-20 eram o main (o nome do branch e quantos terminais) e as tarefas; o dono queria ver
    os terminais.
  - O clique no nome vai ao último lugar usado no projeto (sem terminal, abre um na pasta dele; uma
    página no centro dá lugar aos terminais); num item, põe as abas dele em cima (`tabs.md`).
  - O clique direito num projeto: New Terminal, New Task…, Edit Name and Image…, Pin ou Unpin,
    Project Settings…, Show in Finder, Copy Path, Close Terminals e Remove from the Sidebar (fecha e
    solta; nada do disco sai). Cada um é um comando que age naquele projeto. Soltar uma imagem na
    linha a faz a imagem do projeto, como nos quadrados da faixa. Numa tarefa, o menu
    dela (o estado, hibernar, revisar, remover…), o mesmo do quadro.
  - **Ordem:** os fixados primeiro, na ordem do dono, depois os abertos não fixados. Arrastar a
    linha de um projeto muda a ordem ao soltar (sem deslizar ao vivo); fica no arquivo dos projetos.
  - "Novo projeto…" no fim abre a folha de projeto novo (project.create): a pasta, o nome, a imagem
    ou o emoji e a cor; o projeto criado nasce fixado.
  - **A marca da borda:** um projeto dobrado com pedido, rolado para fora da vista da lista, aparece
    numa marca na borda do lado em que está ("▼ cadex · 1 pedido abaixo"); o clique rola até ele.
- **Arquivos:** o cabeçalho em palavras (numa tarefa, "tarefa de cadex · contra main"; no main, o
  nome e o caminho), a árvore do lugar (o explorer, `explorer.md`, com a linha dele de ações; detalhes
  em `inspector.md`) e, no fim, "N mudanças · ver" quando há arquivo mudado. O clique mostra
  **Mudanças** na própria barra (o painel do git, `source-control.md`, com Commit e Abrir PR); ⇧⌘G
  (git.show) e o projeto · branch da barra de baixo também. Para voltar à árvore, Arquivos no
  seletor, ⌃⌘1 ou o Esc com o foco na barra (com o foco num terminal, o Esc é dele).
- **Pé**, fixo e separado da lista: Quadro (view.board), Automações (orchestration.show-automations)
  e Máquinas (os hosts do `~/.ssh/config` e as máquinas da tailnet numa lista, remote.show; escolher
  conecta numa aba), esta só quando há algum host, e Memória (memory.show-panel, plano 40).
- **Com a página Memória aberta** (plano 40 C): a barra troca o conteúdo, sem segunda coluna. A
  fila fica no topo; "‹ Trabalho" no lugar do seletor (sidebar.show-work; o Esc com o foco na barra
  faz o mesmo; o centro continua na página); as seções do painel no lugar da lista (a busca e os
  três grupos, `memory.md`); no pé, Memória acesa com "ai-memory 3.5.0" à direita. Fechar a aba da
  página volta a barra ao Trabalho.
- **Terminais sem projeto:** os da pasta pessoal não viram projeto na lista; enquanto se está neles,
  nenhum lugar fica aceso (`tabs.md`, abas sem projeto).
- **Com a barra fechada,** quem espera aparece na pílula da barra de cima ("checkout-copy precisa
  de você", ou "2 precisam de você"); o clique faz o mesmo que a fila.
- **O quadro** e as páginas no centro mantêm a barra lateral (o quadro a fechava até 2026-11-20).
- A barra não lê nada a cada tecla: muda com os avisos que já existem (estado dos agentes pelos
  hooks, pedidos abertos ou respondidos, abas abertas ou fechadas, projetos editados).
- Toda ação da barra é comando e está no ⌘K (ADR 0005): as vistas, trocar de projeto (⇧⌘S), ir ao
  pedido, fixar, editar, criar, o quadro, as automações, as máquinas. sidebar.find (⌘K) e o ⌘J acham
  qualquer projeto, tarefa ou terminal pelo nome.

### Janela estreita (abaixo de 1000 pt)
- A barra lateral vira a faixa de 56 pt: no topo, a caixa âmbar com o número de pedidos (o clique
  roda agents.go-to-request); os quadrados dos projetos (a imagem, o emoji ou a letra sobre a cor,
  o halo no escolhido, a peça de estado, o ponto com terminal aberto); no pé, Arquivos
  (sidebar.show-files) e Quadro. As tarefas ficam no menu do lugar.
- Num quadrado: o clique escolhe o projeto, o clique direito traz o menu do projeto, arrastar muda a
  ordem, e soltar uma imagem a faz a imagem do projeto.
- Ficar estreita fecha a barra lateral; alargar a devolve na vista em que estava (se o dono não a
  abriu ou fechou no meio).
- Aberta à mão na janela estreita (⌘B, Arquivos da faixa), ela fica por cima do centro, ao lado da
  faixa, e o Esc a fecha.

## Estados
- **Nada aberto** (nenhum projeto): a barra mostra "RECENTES" com a cara de cada projeto (o avatar,
  o nome e há quanto tempo foi usado: "4m", "1d"), "Novo projeto…" (project.create) e "Abrir
  pasta…" (project.new) com o atalho que o keymap dá a ele (⌃⌘N por padrão), sem o seletor de
  vistas. O clique num recente o abre com as abas que tinha. O centro mostra a tela de início
  (`home.md`), que não fecha a barra.
- **Projeto fixado sem terminal:** a linha fica, com "nada aberto"; o clique abre um terminal.
- **Sem host SSH nem máquina da tailnet:** o pé sem Máquinas.
- **Nenhum pedido aberto:** sem fila, sem pílula, sem caixa âmbar na faixa.

## Casos de borda
- Muitos projetos: a lista rola; a fila, o seletor e o pé ficam no lugar, e a marca da borda diz
  quem espera fora da vista.
- Nome sem letra nem número: o avatar mostra "•".
- Imagem que some do disco: o avatar volta ao emoji ou às letras.
- Recente cuja pasta sumiu: não aparece na lista.

## Critérios de aceite
- [x] A lista de projetos com o avatar, a seta, os terminais com o fio guia, o terminal com foco aceso,
  escolher outro projeto, arrastar e salvar a ordem (conferido no app, plano 38 B).
- [x] A fila no topo com um pedido e a pílula com a barra fechada (conferido no app com um pedido
  falso, CADEX_PERF_REQUEST).
- [ ] A marca da borda com um agente de verdade esperando num projeto fora da vista (só no teste).
- [x] Arquivos com o cabeçalho, a contagem e "ver" abrindo Mudanças (conferido num repositório com
  dois arquivos mudados).
- [x] O Esc voltando de Mudanças para a árvore, com o foco na barra (com o foco num terminal, o Esc
  é dele).
- [x] Abaixo de 1000 pt a faixa no lugar da barra; alargar a devolve; nada aberto com os recentes
  (conferido no app nas três situações).
- [x] Soltar uma imagem num projeto da lista (no teste; os quadrados da faixa também).
