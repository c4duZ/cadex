# sidebar (app macOS)

## O que eu quero
- O trilho (plano 36 fase A; `../../../../docs/adr/0038-rail-and-side-column.md`; a peça Rail de
  `../../../../docs/design/work-frame/screens.md`): na borda esquerda, os projetos com a marca, o
  halo do escolhido (do mesmo tamanho; o anel branco o deixava mais grosso, o dono, 2026-11-18), a peça de estado e o ponto de terminal aberto; o "+" (project.new); no pé,
  Projects (project.show-all) e Automations (orchestration.show-automations), aceso o da página aberta,
  e Remote (remote.show, `remoteShown`: só com algum host SSH ou máquina da tailnet; plano 36 F).
- O modelo do trabalho (`WorkTree.swift`: os projetos, as tarefas e os terminais com o estado), que
  o app junta e o ⌘J e o sidebar.find leem. A árvore que o desenhava (plano 27) saiu da tela com a
  ADR 0038 e do código no plano 36 (WorkTreeView.swift e WorkTreeRows.swift).

## O que eu não quero
- Esta feature conhecendo terminais, worktrees, projetos ou agentes: o app monta o modelo
  (`WorkTree.swift`) e o trilho só desenha e diz o que foi escolhido.
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
- `WorkTreeFind.swift`: sidebar.find, os projetos, as tarefas e os terminais do modelo no ⌘K
  (`WorkTreeFindSource(projects:pick:)`; escolher volta ao app pelo `pick`).
- O app (`../../app/TreeWiring.swift`) junta o modelo: os projetos e as abas deles, as worktrees de
  cada projeto (o git fora da linha principal), o estado do agente de cada terminal, a conta do
  agente na pasta da tarefa; redesenha o trilho quando uma aba, um projeto, uma tarefa ou um agente
  muda. O menu de uma tarefa (o clique direito da árvore) está no item dela na barra de cima.
- O trilho rola: os projetos e o "+" ficam numa área que rola quando não cabem; os ícones das
  páginas e o pé ficam no lugar (a altura dos projetos tem prioridade abaixo da da janela, senão
  eles seguravam a janela aberta).
- Status: o trilho (plano 36) é a feature; spec em `../../../../docs/spec/sidebar.md`.

- `WorkTreeJump.swift` (plano 29 fase C): as linhas do ⌘J tiradas do modelo da árvore (`JumpRow`:
  PRECISA DE VOCÊ, com o que pede ou falhou; TERMINOU, com o terminado e o em revisão; TRABALHANDO;
  o parado fica de fora), na ordem da árvore dentro de cada grupo, e o filtro por palavras; as
  sessões de fora do Cadex entram pelo `init(session:)`. O app faz delas a lista da paleta
  (`../../app/JumpWiring.swift`).

## Como validar
- `make macos-test` passa: o trilho (um quadrado por projeto, o escolhido com o halo, a peça de estado
  só fora de parado, o ponto, o clique, o pé com os comandos e aceso; arrastar), o sidebar.find
  achando pelo nome no modelo, o ⌘J.
