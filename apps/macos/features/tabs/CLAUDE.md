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
  painel com foco (a do arquivo, num documento). A oferta de preview de cada terminal sai por
  `onOpenPreview`. `TabList.swift`: as regras puras (ordem, ativa, recentes, mover), testadas.
- `TabBarView.swift`: a barra de abas desenhada à mão, cada aba da largura do título (72 a 200 pt),
  com o ícone do que mostra (terminal; arquivo pelo tipo e cor do `FileIcons`, como na árvore;
  histórico; página web), a ativa com fundo neutro e × ao passar o mouse, como no Terax
  (clique, duplo clique renomeia, clique do meio fecha, arrastar reordena), com cores de fora (`style`); fica na barra de título da janela
  (a propriedade bar do controlador). `TabsView.swift`: só a aba ativa. `Tab.swift`: uma aba.
- Divisões: `PaneTree.swift` é a árvore pura (dividir, remover dando o espaço ao irmão, retângulos,
  ordem de leitura, vizinho por direção, proporção por caminho), testada. `PaneLayoutView.swift`
  posiciona os terminais pela árvore, divisor de 1 pt que pega o mouse a 6 pt e engrossa sob o
  ponteiro (tamanho mínimo de painel), e escurece os painéis sem foco. `balanced()` na árvore deixa
  do mesmo tamanho os painéis numa direção, a cada divisão e fechamento. `Tab.swift` guarda árvore, painéis e foco.
- `TabsSnapshot.swift` e `TabsRestore.swift`: o estado das abas para salvar (ordem, árvore de cada
  aba com a pasta de cada terminal ou a identidade de cada documento e as proporções, nome dado,
  painel com foco, aba ativa) e reconstruir com shells novos e os documentos feitos pelo app
  (`restore(_:makeDocument:)`; documento sumido ao lado de outros vira terminal na pasta dele). O
  item `.document` do plano 7 ainda é lido, como aba de um painel; `setShown` e `closeAll` para os spaces.
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
