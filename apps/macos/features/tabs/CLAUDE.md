# tabs (app macOS)

## O que eu quero
- Abas de todos os tipos, divisões de painel no terminal, reordenar, renomear e fechar.

## O que eu não quero
- Fechar aba com processo rodando ou arquivo não salvo sem confirmar.
- Aba escondida desenhando: só a aba ativa fica na hierarquia de views.
- Lógica de terminal aqui: as abas usam o `TerminalView` pela porta de entrada da feature terminal.

## Como eu quero
- `TabsController.swift`: as abas de uma janela (abrir na pasta atual, trocar, renomear, fechar,
  ordem de uso). `TabList.swift`: as regras puras (ordem, ativa, recentes, mover), testadas.
- `TabBarView.swift`: a barra desenhada à mão (clique, duplo clique renomeia, arrastar reordena, ×).
  `TabsView.swift`: barra em cima e a aba ativa embaixo. `Tab.swift`: uma aba.
- `TabCommands.swift`: tab.new, pane.close, tab.rename, tab.select-1…9, tab.previous-used,
  tab.least-recently-used. `CloseConfirmation.swift`: a pergunta ao fechar com programa rodando.
- Spec em `../../../../docs/spec/tabs.md`. Status: abas prontas; divisões a fazer.

## Como validar
- `make macos-test` passa.
