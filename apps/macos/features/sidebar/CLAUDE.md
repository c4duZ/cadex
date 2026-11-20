# sidebar (app macOS)

## O que eu quero
- A barra lateral (`../../../../docs/adr/0039-sidebar-with-work-and-files.md`, plano 38; a
  referência `../../../../docs/design/sidebar/6-estrutura-ideal.html`): a fila "Precisa de você" no
  topo, o seletor "Trabalho | Arquivos" e a vista; no pé, Quadro, Automações, Máquinas e Memória. Na janela
  estreita, a faixa (o que ficou do trilho do plano 36).
- O modelo do trabalho (`WorkTree.swift`: os projetos, as tarefas e os terminais com o estado), que
  o app junta e o ⌘J e o sidebar.find leem. A árvore que o desenhava (plano 27) saiu da tela com a
  ADR 0038 e do código no plano 36 (WorkTreeView.swift e WorkTreeRows.swift).

## O que eu não quero
- Esta feature conhecendo terminais, worktrees, projetos ou agentes: o app monta o modelo
  (`WorkTree.swift`) e a barra só desenha e diz o que foi escolhido.
- Clique que faz a ação por conta própria: cada botão roda um comando pelo id (ADR 0005); a linha
  escolhida volta ao app por `onPick`.
- Valor digitado: só `DesignTokens` (components.sidebar; `../../../../tools/check_design_literals.py`).

## Como eu quero
- `WorkSidebar.swift`: o modelo (`WorkProject`: a pasta, o nome, a cor, a imagem ou o emoji, o
  estado, os terminais, os pedidos, aberto ou fechado, os lugares; `initials`, as duas letras do
  avatar; `WorkPlace`, uma linha sob o projeto (hoje um terminal, que o app dá); `WorkSidebarMode`). `WorkSidebarView.swift`: a porta de
  entrada; `show` (os projetos e o lugar aceso) redesenha só quando mudam; `onPickProject`,
  `onPickPlace`, `onToggle` (a seta), `menuFor` (o clique direito), `onMove` (arrastar a linha de um
  projeto muda a ordem), `onMode` (o seletor); `setFiles` recebe a vista de Arquivos (a coluna de
  Files e Changes do app) e `setFilesActions` os botões dela, no cabeçalho à direita do nome, `setQueue` a fila; `remoteShown` mostra Máquinas no pé. `WorkRows.swift`:
  o avatar e a linha (a seta do Phosphor, o nome, à direita o estado e os terminais, "nada aberto" ou
  a contagem âmbar dos pedidos; a linha inteira pega o clique, a seta dobra; com `onOpenPage`, o ícone da
  página do projeto aparece à direita sob o ponteiro e o clique nele abre a página (`onOpenProjectPage`); sem seta, o lugar dela
  fica, e Novo projeto… tem um + no lugar do avatar, `WorkIconSlot`, alinhado com os projetos; o avatar
  sem cor própria em line.control, visível como o com cor; o dono, 2026-11-20). `WorkSidebarParts.swift`:
  o seletor, o grupo do main e das tarefas com o fio guia, a linha do pé e a marca da borda
  (`WorkEdge`: um projeto com pedido fora da vista da lista diz o nome e o lado; o clique rola até
  ele). `WorkRequest.swift`: um pedido aberto (`WorkRequest`, quem pede, o pedido em frase, há quanto
  tempo), para a pílula da barra de cima; o cartão âmbar no topo da barra saiu na 3.1 (aparecia e
  sumia em cima dos projetos, o dono, 2026-11-20). Fase D: a vista Arquivos tem o cabeçalho em palavras (`setFilesHead`,
  `WorkFilesHead`), a vista do app no meio e, no fim, "N mudanças · ver" (`setChanges`,
  `WorkChangesLine`; some sem mudança ou com Mudanças à vista; o clique, `onShowChanges`). Tokens:
  components.workSidebar.
- `WorkSidebarMemory.swift` (plano 40 C): o modo `.memory` com a página Memória aberta: "‹ Trabalho"
  (`WorkBackRow`, sidebar.show-work; o Esc também) no lugar do seletor, a vista que o app dá
  (`setMemory`, as seções da feature memory) no lugar da lista, e no pé Memória (memory.show-panel)
  acesa com a versão à direita (`setMemoryVersion`). Tokens: components.memoryPanel.nav.
- `WorkRecents.swift` (fase G): nada aberto, `showRecents` lista os recentes (`WorkRecent`: a cara
  do projeto e quando foi usado), Novo projeto… (project.create) e Abrir pasta… (project.new, com o
  atalho que o app dá), sem o seletor; `onPickRecent` diz a pasta; o próximo `show` com projetos
  devolve o seletor e a vista.
- A faixa da janela estreita (fase G) é o `RailView` abaixo: a caixa âmbar dos pedidos no topo
  (`requests`, `RailAsking`), os quadrados e, no pé, Arquivos (sidebar.show-files) e Quadro
  (view.board).
- `Rail.swift`: o modelo puro da faixa (`RailProject`: a pasta, o nome, a cor, a imagem ou o emoji,
  o estado, se tem terminal aberto e se é fixado; `mark`, a letra até haver imagem; `badge`, o
  estado que se mostra). `RailView.swift`: a porta de entrada; `show` recebe os projetos e o
  escolhido e redesenha só quando mudam; `onPick` diz a pasta clicada; `menuFor`, o clique direito
  (as linhas vêm do app, cada uma um comando); `onDropImage`, uma imagem solta num quadrado (plano 36
  B; na lista Trabalho, a linha do projeto também aceita, o onDropImage da WorkSidebarView). O quadrado
  mostra a imagem do projeto, senão o emoji, senão a letra; os fixados primeiro e, depois de uma
  linha, os abertos não fixados. `RailParts.swift`: `RailTile` (o quadrado, o halo, a peça de
  estado, o ponto; `droppedImage`, o arquivo de imagem arrastado), `RailButton` (os do pé) e
  `RailAsking`. Tokens: components.rail. `RailDrag.swift` (plano 36 E): arrastar um quadrado passa
  dos 4 pt e vira arrasto (`RailPress`; sem laço de eventos próprio, os cliques de teste mandam o
  soltar logo depois); os outros abrem caminho ao vivo; ao soltar, `onMove` (a pasta, a ordem e se
  ficou acima da linha, fixado). Um projeto sem terminal não passa da linha para baixo.
- `WorkTree.swift`: o modelo puro (`WorkTreeProject`, `WorkTreeTask`, `WorkTreeTerminal`) e
  `WorkTreePick` (projeto, tarefa ou terminal).
- `WorkTreeFind.swift`: sidebar.find, os projetos, as tarefas e os terminais do modelo no ⌘K
  (`WorkTreeFindSource(projects:pick:)`; escolher volta ao app pelo `pick`).
- O app (`../../app/TreeWiring.swift`) junta o modelo: os projetos e as abas deles, as worktrees de
  cada projeto (o git fora da linha principal), o estado do agente de cada terminal, a conta do
  agente na pasta da tarefa; redesenha a barra quando uma aba, um projeto, uma tarefa ou um agente
  muda. Os comandos place.go e project.go (as linhas do menu do lugar, com a pasta) também. O menu de uma tarefa (`treeMenu`) está no clique direito da linha dela na barra lateral (`menuForPlace`) e no quadro.
- A faixa rola: os projetos ficam numa área que rola quando não cabem; o pé fica no lugar (a altura
  dos projetos tem prioridade abaixo da da janela, senão eles seguravam a janela aberta).
- Status: a barra lateral (plano 38) é a feature; spec em `../../../../docs/spec/sidebar.md`.

- `WorkTreeJump.swift` (plano 29 fase C): as linhas do ⌘J tiradas do modelo da árvore (`JumpRow`:
  PRECISA DE VOCÊ, com o que pede ou falhou; TERMINOU, com o terminado e o em revisão; TRABALHANDO;
  o parado fica de fora), na ordem da árvore dentro de cada grupo, e o filtro por palavras; as
  sessões de fora do Cadex entram pelo `init(session:)`. O app faz delas a lista da paleta
  (`../../app/JumpWiring.swift`).

## Como validar
- `make macos-test` passa: a lista Trabalho (as linhas, o lugar aceso, os cliques, o menu da tarefa,
  a imagem solta), o seletor, a fila, os recentes, o modo Memória; a faixa (um quadrado por projeto, o escolhido com
  o halo, a peça de estado só fora de parado, o ponto, o clique, o pé com os comandos; arrastar), o sidebar.find
  achando pelo nome no modelo, o ⌘J.
