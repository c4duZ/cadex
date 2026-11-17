# sidebar (app macOS)

## O que eu quero
- A árvore do trabalho, a coluna da esquerda (`../../../../docs/spec/sidebar.md`; a peça Sidebar do
  mockup, plano 27 fase B): "New task" e o filtro no topo; cada projeto dobrável com as tarefas
  (as worktrees) e os terminais da pasta dele; sob a tarefa escolhida, os terminais dela; "+ Add
  project"; no pé, Automations e Archive & history.

## O que eu não quero
- Esta feature conhecendo terminais, worktrees, projetos ou agentes: o app monta o modelo
  (`WorkTree.swift`) e a árvore só desenha e diz o que foi escolhido.
- Clique que faz a ação por conta própria: cada botão roda um comando pelo id (ADR 0005); a linha
  escolhida volta ao app por `onPick`.
- Valor digitado: só `DesignTokens` (components.sidebar; `../../../../tools/check_design_literals.py`).

## Como eu quero
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
- Ainda no código até a fase D: a fileira de ícones e as páginas de antes (`SidebarView.swift`,
  `SidebarItem.swift`, `SidebarLayout.swift`, `SidebarHeader.swift`, `SidebarIconRow.swift`,
  `SidebarIconButton.swift`, `SidebarCommands.swift`), que a janela já não mostra.
- A linha de tarefa inteira (fase B2): a idade à direita do nome, embaixo o agente, o +/− e o que
  espera em âmbar; o comentário sob o ponteiro; o clique direito pede ao app o menu (`menuFor`).
- Status: plano 27 fase B no código. A etiqueta de PR do mockup fica de fora: o app não tem de onde
  saber de um PR.

## Como validar
- `make macos-test` passa: a árvore com os projetos, as tarefas e os terminais, os terminais só sob a
  tarefa escolhida, "Add project" no fim; com CADEX_SNAPSHOT_DIR, tree.png com uma tarefa inteira; e os testes da fileira de antes até a fase D.
