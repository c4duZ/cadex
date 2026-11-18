# sidebar (app macOS)

## O que eu quero
- O trilho (plano 36 fase A; `../../../../docs/adr/0038-rail-and-side-column.md`; a peça Rail de
  `../../../../docs/design/work-frame/screens.md`): na borda esquerda, os projetos com a marca, o
  halo do escolhido (do mesmo tamanho; o anel branco o deixava mais grosso, o dono, 2026-11-18), a peça de estado e o ponto de terminal aberto; o "+" (project.new); no pé,
  Projects (project.show-all) e Automations (orchestration.show-automations), aceso o da página aberta.
- A árvore do trabalho (fora da tela desde a ADR 0038; ainda junta o que o sidebar.find lista, até a
  fase G do plano 36), a coluna da esquerda (`../../../../docs/spec/sidebar.md`; a peça Sidebar do
  mockup, plano 27 fase B): "New task" e o filtro no topo; cada projeto dobrável com as tarefas
  (as worktrees) e os terminais da pasta dele; sob a tarefa escolhida, os terminais dela; "+ Add
  project"; no pé, Projects (project.show-all, com o número) e Automations
  (orchestration.show-automations, com "N ligada"), aceso o da página aberta (`footChosen`; plano 34 B:
  o Archive & history virou a aba Sessões de cada projeto).

## O que eu não quero
- Esta feature conhecendo terminais, worktrees, projetos ou agentes: o app monta o modelo
  (`WorkTree.swift`) e a árvore só desenha e diz o que foi escolhido.
- Clique que faz a ação por conta própria: cada botão roda um comando pelo id (ADR 0005); a linha
  escolhida volta ao app por `onPick`.
- Valor digitado: só `DesignTokens` (components.sidebar; `../../../../tools/check_design_literals.py`).

## Como eu quero
- `Rail.swift`: o modelo puro do trilho (`RailProject`: a pasta, o nome, a cor, o estado e se tem
  terminal aberto; `mark`, a letra até haver imagem; `badge`, o estado que se mostra) e `RailFoot`.
  `RailView.swift`: a porta de entrada; `show` recebe os projetos e o escolhido e redesenha só quando
  mudam; `onPick` diz a pasta clicada; `footLit` acende o pé; `menuFor`, o clique direito (as linhas
  vêm do app, cada uma um comando); `onDropImage`, uma imagem solta num quadrado (plano 36 B). O
  quadrado mostra a imagem do projeto, senão o emoji, senão a letra; o "+" roda project.create; os
  fixados primeiro e, depois de uma linha, os abertos não fixados (o pinned de RailProject).
  `setPages` põe os ícones das páginas da coluna (`RailPage`) abaixo do "+", depois de uma linha;
  `pageLit` acende o da página aberta; o clique roda o comando da página, e no aceso o
  `toggleCommand` (view.toggle-sidebar), como a barra de atividades do VS Code (ADR 0038 revista). `RailParts.swift`: `RailTile` (o
  quadrado, o halo, a peça de estado, o ponto) e `RailButton` (o "+" e os do pé). Tokens:
  components.rail. `RailDrag.swift` (plano 36 E): arrastar um quadrado ou um ícone de página passa
  dos 4 pt e vira arrasto (`RailPress`; sem laço de eventos próprio, os cliques de teste mandam o
  soltar logo depois); os outros abrem caminho ao vivo; ao soltar, `onMove` (a pasta, a ordem e se
  ficou acima da linha, fixado) ou `onMovePages` (os ids). Um projeto sem terminal não passa da linha
  para baixo.
- `WorkTree.swift`: o modelo puro (`WorkTreeProject`, `WorkTreeTask`, `WorkTreeTerminal`) e
  `WorkTreePick` (projeto, tarefa ou terminal).
- `WorkTreeView.swift`: a porta de entrada. `show` recebe os projetos e o escolhido e redesenha só
  quando mudam; o cabeçalho do projeto dobra e desdobra; o topo roda worktrees.new-task e
  sidebar.find, "+ Add project" roda project.new, o pé roda orchestration.show-automation-history e
  agents.show-history; `automationsDetail` é a linha das automações.
- `WorkTreeRows.swift`: as linhas (o cabeçalho do projeto, a linha de tarefa com o `StateGlyph`, o
  nome em negrito quando há novidade e o agente embaixo, a linha de terminal com o ponto e a nota,
  "+ Add project" e as do pé) e `WorkTreeRow`, a linha que se aperta, escolhida com o fundo e a
  linha de dentro.
- `WorkTreeFind.swift`: sidebar.find, os projetos, as tarefas e os terminais da árvore no ⌘K.
- O app (`../../app/TreeWiring.swift`) junta o modelo: os projetos e as abas deles, as worktrees de
  cada projeto (o git fora da linha principal), o estado do agente de cada terminal, a conta do
  agente na pasta da tarefa; redesenha quando uma aba, um projeto, uma tarefa ou um agente muda.
- A fileira de ícones e as páginas de antes saíram no plano 27 fase D.
- A tarefa escolhida leva os terminais dela dentro da caixa, sob a linha do agente (o mockup); cada
  terminal da pasta do projeto é uma linha como a de tarefa, em duas linhas: o estado, o nome (o
  programa, ou "Terminal" num shell) e a idade; embaixo o agente e a conta, ou a pasta, e o que espera.
- A linha de tarefa inteira (fase B2): a idade à direita do nome, embaixo o agente, o +/− e o que
  espera em âmbar; o comentário sob o ponteiro; o clique direito pede ao app o menu (`menuFor`).
- Status: plano 27 fases B e D no código. A etiqueta de PR do mockup fica de fora: o app não tem de onde
  saber de um PR.

- `WorkTreeJump.swift` (plano 29 fase C): as linhas do ⌘J tiradas do modelo da árvore (`JumpRow`:
  PRECISA DE VOCÊ, com o que pede ou falhou; TERMINOU, com o terminado e o em revisão; TRABALHANDO;
  o parado fica de fora), na ordem da árvore dentro de cada grupo, e o filtro por palavras; as
  sessões de fora do Cadex entram pelo `init(session:)`. O app faz delas a lista da paleta
  (`../../app/JumpWiring.swift`).

## Como validar
- `make macos-test` passa: o trilho (um quadrado por projeto, o escolhido com o halo, a peça de estado
  só fora de parado, o ponto, o clique, o pé com os comandos e aceso); a árvore com os projetos, as tarefas e os terminais, os terminais só sob a
  tarefa escolhida, "Add project" no fim; com CADEX_SNAPSHOT_DIR, tree.png com os dados do Sidebar.dc.html no tamanho dele (292×826), para pôr sobre o mockup.
