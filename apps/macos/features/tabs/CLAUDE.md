# tabs (app macOS)

## O que eu quero
- Abas divididas em painéis, cada painel com um terminal ou um documento; reordenar, renomear e
  fechar.

## O que eu não quero
- Fechar aba com processo rodando ou arquivo não salvo sem confirmar.
- Aba escondida desenhando: só a aba ativa fica na hierarquia de views.
- Lógica de terminal aqui: as abas usam o `TerminalView` pela porta de entrada da feature terminal.

## Como eu quero
- `TabsController.swift`: as abas de uma janela (abrir na pasta atual, trocar, renomear, fechar,
  ordem de uso). Documentos: `TabDocument.swift` é o protocolo que editor, mídia, preview, diff e
  histórico implementam; um painel (`Pane` em `Tab.swift`) guarda um terminal ou um documento.
  `TabsDocuments.swift`: `open(_:)` abre numa aba nova ou vai para o painel da mesma identidade (o
  caminho); `activeTerminal`/`activeDocument` são os do painel com foco; `document(identity:)` e
  `allDocuments` procuram em todos os painéis. O título ganha "●" com mudança não salva, fechar
  pergunta ao documento, sair pergunta se há arquivo não salvo. Terminal novo abre na pasta do
  painel com foco (a do arquivo, num documento). `open(_:beside:keeping:)` abre ao lado pelas regras
  da spec (o painel que já o mostra, troca do painel de documento sem mudança não salva, encostado
  num lado com metade da aba, divisão à direita, nova aba sem espaço); `keeping` é o documento que
  pediu, que não é trocado. Encostado (issue #5): Tab.dockedPane é um documento num lado da
  divisão de fora; `PaneTree.balanced(keeping:)` reequilibra só o outro lado; o lado vem de
  documentsOnLeft (tabs.documentSide, que o app define).
  `PaneHeaderView.swift`: o cabeçalho de cada painel com 2+ painéis (nome, ⋯, maximizar, ✕; issue
  #1), posto pelo `PaneLayoutView.swift`, que também mostra só o painel maximizado (`zoomed`);
  `TabsPaneHeaders.swift` diz o que cada um mostra e liga os botões aos comandos pelo `runCommand`
  (pane.close, pane.zoom, as divisões). tabs.paneHeaders vem do app em PaneLooks.paneHeaders.
  `PanePressRecognizer.swift`: o clique num documento dá o foco ao painel sem tomar o clique. Título
  e ícone da aba vêm do painel com foco; "●" se qualquer painel tem mudança não salva. A oferta de preview de cada terminal sai por
  `onOpenPreview`. `TabList.swift`: as regras puras (ordem, ativa, recentes, mover), testadas.
- `TabBarView.swift`: a barra de abas desenhada à mão (dica de cada aba e do × por HoverTip.hover,
  do menus compartilhado), cada aba da largura do título (72 a 200 pt),
  com o ícone do que mostra (terminal; arquivo pelo tipo e cor do `FileIcons`, como na árvore;
  histórico; página web), a ativa com fundo neutro e × ao passar o mouse
  (clique, duplo clique renomeia, clique do meio fecha, arrastar reordena), com cores de fora (`style`); fica na barra de título da janela
  (a propriedade bar do controlador). `TabsView.swift`: só a aba ativa. `Tab.swift`: uma aba.
- Divisões: `PaneTree.swift` é a árvore pura (dividir, remover dando o espaço ao irmão, retângulos,
  ordem de leitura, vizinho por direção, proporção por caminho), testada. `PaneLayoutView.swift`
  posiciona os painéis pela árvore, divisor de 1 pt que pega o mouse a 6 pt e engrossa sob o
  ponteiro (tamanho mínimo de painel), e escurece os painéis sem foco (PaneLooks.unfocusedDim, tabs.unfocusedDim, que o app define). `balanced()` na árvore deixa
  do mesmo tamanho os painéis numa direção, a cada divisão e fechamento. `Tab.swift` guarda árvore, painéis e foco.
- `TabsSnapshot.swift` e `TabsRestore.swift`: o estado das abas para salvar (ordem, árvore de cada
  aba com a pasta de cada terminal ou a identidade de cada documento e as proporções, nome dado,
  painel com foco, aba ativa) e reconstruir com shells novos e os documentos feitos pelo app
  (`restore(_:makeDocument:)`; documento sumido ao lado de outros vira terminal na pasta dele). O
  item `.document` do plano 7 ainda é lido, como aba de um painel; `setShown` e `closeAll` para os spaces.
  `onStateChange` avisa cada mudança; `onEmpty`, a última aba fechada (sem ele, fecha a janela).
  `TabsClosing.swift`: fechar painel, aba e janela, e `shouldClose` para vários conjuntos de abas
  (uma pergunta só ao sair, contando os spaces escondidos); `hasRunningProgram` para o manter acordado.
- `TabsTerminals.swift`: `agentTerminals` (um agente conhecido pelo título, depois qualquer
  terminal com programa rodando; em cada grupo o último terminal clicado primeiro, em qualquer
  aba, pela lista recentTerminals que o onFocus de cada terminal alimenta; nunca clicados depois;
  shell parado nunca) e `focus(_:)`, para o elemento escolhido no preview. A ordem é
  `AgentCandidate`, pura e testada.
- `TabSource.swift`: as abas como lista da paleta (TabCommands.source, o `@` do app).
- Clique direito numa aba: seleciona e mostra `contextMenu` (as entradas vêm do app, por comandos).
  Cada aba guarda a cor de trabalho (`color`, no snapshot), `activeColor`/`setActiveColor`.
- `TabCommands.swift`: tab.new, tab.rename, tab.select-1…9, tab.previous-used,
  tab.least-recently-used, pane.close, pane.zoom (⇧⌘↩), pane.split-right, pane.split-down, pane.next, pane.previous,
  pane.focus-left/right/up/down. `CloseConfirmation.swift`: a pergunta ao fechar painel, aba ou
  janela com programa rodando.
- Spec em `../../../../docs/spec/tabs.md`. Status: abas, divisões e documentos em painéis prontos
  (plano 8).
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: `TabList` e `PaneTree` têm os testes das regras; o snapshot ida e volta
  pelo JSON e um TabsController restaurado igual; com um `FakeDocument`, as regras de abrir ao lado,
  foco por painel, fechar perguntando e o spaces.json do plano 7 lido igual.
