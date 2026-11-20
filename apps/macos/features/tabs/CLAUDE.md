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
  `PaneHeaderView.swift`: o cabeçalho de todo painel (plano 28 fase B, components.pane.header: o
  estado, o nome, de onde é e, à direita, o custo e o tempo; +, maximizar e ✕ só ao passar o
  ponteiro; issue #1); o que um agente acrescenta vem do app por TabsController.paneDetail Plano 33 E: PaneDetail.accountSwitch deixa o clique no detalhe (onde fica a conta) abrir a lista
  que o app dá (TabsController.paneAccountMenu).
  (`PaneDetail`, guardado pelo app e só lido aqui); posto pelo `PaneLayoutView.swift`, que também mostra só o painel maximizado (`zoomed`);
  Um documento cuja barra é o cabeçalho (`barIsHeader`, o preview) fica sem o cabeçalho do painel e
  com os cantos da caixa. `TabsPaneHeaders.swift` diz o que cada um mostra e liga os botões aos comandos pelo `runCommand`
  (pane.close, pane.zoom; o menu do + vem do app em `paneMenu`). Arrastar o cabeçalho move o
  painel: `PaneDragBoard.swift` mostra cada painel como janela cinza que desliza ao vivo, a etiqueta
  de `PaneDragChip.swift` segue o ponteiro e `PaneDrop.swift` decide onde cai, no layout do começo
  (diagonais, centro e cabeçalho trocam); os painéis de verdade só mudam ao soltar.
  `PanePressRecognizer.swift`: o clique num documento dá o foco ao painel sem tomar o clique. Título
  e ícone da aba vêm do painel com foco; "●" se qualquer painel tem mudança não salva. A oferta de preview de cada terminal sai por
  `onOpenPreview`. `TabList.swift`: as regras puras (ordem, ativa, recentes, mover), testadas.
- `TabBarView.swift`: a barra de abas desenhada à mão (dica de cada aba e do × por HoverTip.hover,
  do menus compartilhado), na cara da moldura nova (plano 26, fase A; components.tab): cada aba da
  largura do título (até maxTitle; todas encolhem juntas até minWidth quando não cabem), 30 pt,
  raio 7, com a peça de estado antes do nome quando algo roda e sem ícone nenhum fora disso, como o
  mockup TitleBar (os ícones de terminal e de arquivo deixavam a fileira mais cheia que o desenho,
  2026-11-17), a ativa no fundo de etiqueta e as outras sem fundo,
  sem linha embaixo, × só ao passar o mouse
  (clique, duplo clique renomeia, clique do meio fecha, arrastar reordena ao vivo em
  `TabBarDrag.swift`, com a janela travada enquanto isso), com cores de fora (`style`); fica na barra de título da janela
  (a propriedade bar do controlador). `TabsView.swift`: só a aba ativa. `Tab.swift`: uma aba.
- Divisões: `PaneTree.swift` é a árvore pura (dividir, remover dando o espaço ao irmão, retângulos,
  ordem de leitura, vizinho por direção, proporção por caminho), testada. `PaneLayoutView.swift`
  posiciona os painéis pela árvore, cada um na caixa de `PaneChrome.swift` (cantos, linha, o anel do
  foco, os sem foco a 92%), com 8 pt em volta e entre as caixas; o vão pega o mouse numa
  `DividerHandle` por cima de tudo (o cursor de redimensionar não briga com o do terminal) e mostra
  uma barra curta sob o ponteiro (tamanho mínimo de painel); o terminal com o respiro do mockup, a
  barra de rolagem dele na borda da caixa e o cartão do pé (`footCard`) onde o mockup Pane o põe. `balanced()` na árvore deixa
  do mesmo tamanho os painéis numa direção, a cada divisão e fechamento. `Tab.swift` guarda árvore, painéis e foco.
- `TabsSnapshot.swift` e `TabsRestore.swift`: o estado das abas para salvar (ordem, árvore de cada
  aba com a pasta de cada terminal ou a identidade de cada documento e as proporções, nome dado,
  painel com foco, aba ativa) e reconstruir com shells novos e os documentos feitos pelo app
  (`restore(_:makeDocument:)`; documento sumido ao lado de outros vira terminal na pasta dele). O
  item `.document` do plano 7 ainda é lido, como aba de um painel; `setShown` e `closeAll` para os spaces.
  O painel guarda também o Claude que roda nele ou hibernou (`.pane(folder:session:agent:)`,
  `PaneAgent`: a conversa, a pasta, a conta e a sessão do kit com as flags); ao restaurar, o app o
  traz de volta pelo `restoreAgent` do TabsController (o dono, 2026-11-20).
  Com `keepsSessions` (a janela principal, terminal.keepSessions), o painel guarda o nome do shell no
  daemon (`.pane(folder:session:)`) e o restore religa por ele; `closeAll(keepingSessions:)` solta
  esses shells em vez de encerrar, e a pergunta ao fechar a janela ou sair não conta programa que
  segue rodando no daemon (plano 19, fase E2).
  `onStateChange` avisa cada mudança; `onEmpty`, a última aba fechada (sem ele, fecha a janela).
  `TabsClosing.swift`: fechar painel, aba e janela, e `shouldClose` para vários conjuntos de abas
  (uma pergunta só ao sair, contando os spaces escondidos); `hasRunningProgram` para o manter acordado.
- `TabsListing.swift` (plano 39 B): `listedTerminals`, cada painel de terminal na ordem das abas
  com o título da aba (o `cadex attach` os lista).
- `TabsTerminals.swift`: `agentTerminals` (um agente conhecido pelo título, depois qualquer
  terminal com programa rodando; em cada grupo o último terminal clicado primeiro, em qualquer
  aba, pela lista recentTerminals que o onFocus de cada terminal alimenta; nunca clicados depois;
  shell parado nunca) e `focus(_:)`, para o elemento escolhido no preview. A ordem é
  `AgentCandidate`, pura e testada.
- `TabSource.swift`: as abas como lista da paleta (TabCommands.source, o `@` do app).
- Clique direito numa aba: seleciona e mostra `contextMenu` (as entradas vêm do app, por comandos).
  `markOf` (plano 35 I): o app diz o sinal discreto de uma aba de terminal (a memória pausada na
  sessão dela, o ícone de pausa; senão outra tela na sessão, plano 39 A, o ícone do telefone), desenhado depois do título no texto terciário
  (`TabBarView.swift`, Item.mark, com espaço para ele na largura); `refreshTabBar` o redesenha.
  Cada aba guarda a cor de trabalho (`color`, no snapshot), `activeColor`/`setActiveColor`.
- `TabCommands.swift`: tab.new, tab.rename, tab.select-1…9, tab.previous-used,
  tab.least-recently-used, pane.close, pane.zoom (⇧⌘↩), pane.split-right, pane.split-down, pane.next, pane.previous,
  pane.focus-left/right/up/down. `CloseConfirmation.swift`: a pergunta ao fechar painel, aba ou
  janela com programa rodando.
- Spec em `../../../../docs/spec/tabs.md`. Status: abas, divisões e documentos em painéis prontos
  (plano 8).
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

- Plano 29, revisão contra os mockups: `TabCommandLooks.swift` (o nome do comando na aba e no
  cabeçalho, o estado de um comando, "Terminals · N", "running 38 s" e a etiqueta "Open :5173 in
  preview", `PaneHeaderOffer` no `PaneHeaderView.swift`), `TabsCommandClock.swift` (um relógio de
  1 s só enquanto um painel mostra "running", que também move a árvore por onCommandTick) e
  `TabsGroups.swift` (a barra só com as abas do grupo da aba ativa, pelo `groupOf` do app, e
  "Review" no fim de uma tarefa; ⌘1…⌘9 e arrastar pela ordem mostrada).
- `TabsDrawer.swift` e `TabsMove.swift` (plano 30 C): a vista da gaveta (as abas dela, "+", a dica,
  a borda que muda a altura) e mover um terminal entre conjuntos de abas com o shell vivo
  (`takeFocusedTerminal`, `adopt`); `plainPanes`, painel sozinho sem caixa nem cabeçalho.
- `TabsLanes.swift` (plano 30 B): `splitRight(cwd:)`, o nome de uma aba e a faixa sobre os painéis
  dela (Tab.banner, que o TabsView põe em cima); o cabeçalho de duas linhas com a barra do teto
  (`PaneLane` no PaneDetail) e TerminalView.footBar, a barra no pé do painel.
- TabDocument.isPage (plano 30): uma página nunca abre ao lado de um terminal, só na própria aba
  (`TabsDocuments.swift`, plano 31 E: a revisão, o histórico, a transcrição, o briefing, o arquivo).
  Uma página sozinha na aba ocupa o centro inteiro, sem caixa nem
  cabeçalho (`PaneLayoutView.swift`). `TabsExtra`: os itens do fim da barra que rodam um comando
  ("Review" de uma tarefa), dados pelo app em `extrasOf`. Plano 34 A: uma página nunca aparece na
  barra (`TabsGroups.swift`: `isPageTab`, `shownIDs` sem páginas e pelo grupo do último terminal
  usado, `showsPage`); abrir uma página fecha a outra (uma por vez); `leavePage` volta ao terminal
  de antes (o Esc do app, `../../app/PageWiring.swift`).
- `TabAgentTitle.swift` (plano 19; plano 25 fase D): o estado do agente como `GlyphState` da peça
  única de estado (`../../shared/state-glyph/`): trabalhando, precisa de você, pronto, falhou, e
  hibernado como parado ("Hibernando" na dica); o `TabBarView` põe o sinal antes do nome da aba
  (uma `StateGlyphView` por aba com estado, 9 na ativa e 7 nas outras, parada e desenhada enquanto
  uma aba é arrastada) e o título em negrito quando o agente terminou sem você ver; os sinais de
  texto de antes (◐ ● ✓ ✕ ☾) saíram do título. A frase do que ele faz na dica; o nome da aba é o dado
  à mão ou o da pasta (o projeto ou a tarefa), nunca o título que o agente escreve ("Claude", o nome
  da conversa; o dono, 2026-11-18).

- Plano 36 fase D (`../../../../docs/adr/0038-rail-and-side-column.md`): `TabsBarOverflow.swift`. Um
  `TabsExtra` com `group` vai às abas daquele grupo em vez de rodar um comando (`enterGroup`: a
  usada por último nele): a tarefa como item da barra do projeto, com o estado dela antes do nome, e
  "‹ projeto" (`leading`, antes das abas) na barra da tarefa. A barra de título diz quanto espaço a
  faixa tem (TabBarView.room); quando as abas não cabem nem no menor tamanho, as que sobram vão para
  "» N" no fim, uma lista para escolher, e a ativa fica sempre à mostra.

## Como validar
- `make macos-test` passa: `TabList` e `PaneTree` têm os testes das regras; o snapshot ida e volta
  pelo JSON e um TabsController restaurado igual; com um `FakeDocument`, as regras de abrir ao lado,
  foco por painel, fechar perguntando e o spaces.json do plano 7 lido igual.
