# tabs (app macOS)

## O que eu quero
- Abas de todos os tipos, divisões de painel no terminal, reordenar, renomear e fechar.

## O que eu não quero
- Fechar aba com processo rodando ou arquivo não salvo sem confirmar.
- Aba escondida desenhando: só a aba ativa fica na hierarquia de views.
- Lógica de terminal aqui: as abas usam o `TerminalView` pela porta de entrada da feature terminal.

## Como eu quero
- `TabsController.swift`: as abas de uma janela (abrir na pasta atual, trocar, renomear, fechar,
  ordem de uso). Abas de documento: `TabDocument.swift` é o protocolo que o editor (e depois mídia e
  preview) implementa; `open(_:)` abre ou vai para a aba da mesma identidade (o caminho), o título
  ganha "●" com mudança não salva, fechar pergunta ao documento, sair pergunta se há arquivo não
  salvo. Terminal novo abre na pasta do documento ativo. A oferta de preview de cada terminal sai por
  `onOpenPreview`. `TabList.swift`: as regras puras (ordem, ativa, recentes, mover), testadas.
- `TabBarView.swift`: a barra de abas em pílulas, desenhada à mão (clique, duplo clique renomeia,
  arrastar reordena, ×), com cores de fora (`style`); fica na barra de título da janela
  (a propriedade bar do controlador). `TabsView.swift`: só a aba ativa. `Tab.swift`: uma aba.
- Divisões: `PaneTree.swift` é a árvore pura (dividir, remover dando o espaço ao irmão, retângulos,
  ordem de leitura, vizinho por direção, proporção por caminho), testada. `PaneLayoutView.swift`
  posiciona os terminais pela árvore, divisor arrastável de 1 pt (tamanho mínimo de painel) e
  contorno discreto no painel com foco. `Tab.swift` guarda árvore, painéis e foco.
- `TabsSnapshot.swift` e `TabsRestore.swift`: o estado das abas para salvar (ordem, árvore de cada
  aba com a pasta de cada painel e as proporções, nome dado, painel com foco, documentos pela
  identidade, aba ativa) e reconstruir com shells novos; `setShown` e `closeAll` para os spaces.
  `onStateChange` avisa cada mudança; `onEmpty`, a última aba fechada (sem ele, fecha a janela).
  `TabsClosing.swift`: fechar painel, aba e janela, e `shouldClose` para vários conjuntos de abas
  (uma pergunta só ao sair, contando os spaces escondidos).
- `TabCommands.swift`: tab.new, tab.rename, tab.select-1…9, tab.previous-used,
  tab.least-recently-used, pane.close, pane.split-right, pane.split-down, pane.next, pane.previous,
  pane.focus-left/right/up/down. `CloseConfirmation.swift`: a pergunta ao fechar painel, aba ou
  janela com programa rodando.
- Spec em `../../../../docs/spec/tabs.md`. Status: abas e divisões prontas.

## Como validar
- `make macos-test` passa: `TabList` e `PaneTree` têm os testes das regras; o snapshot ida e volta
  pelo JSON e um TabsController restaurado igual.
