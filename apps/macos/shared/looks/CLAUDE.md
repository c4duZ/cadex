# looks (compartilhado do app)

## O que eu quero
- Zoom, densidade (compacta ou normal) e fonte da interface, separados da fonte do terminal, como
  o Zed (plano 15, fase D: appearance.uiZoom, appearance.density, appearance.uiFont,
  appearance.uiFontSize).
- Quem nunca mexe nisso vê o app igual: zoom 1, densidade normal e fonte do sistema em 13 pt
  devolvem cada medida do desenho sem mudança.

## O que eu não quero
- Refazer o layout das telas com o app aberto: vale ao abrir o Cadex, como o idioma; as
  configurações oferecem "Reabrir agora" (o dono, 2026-10-20).
- Zoom no terminal ou no código do editor: eles têm a fonte do terminal.
- Fonte ou medida principal da interface fixa no código, fora de UILooks.

## Como eu quero
- `TitleBarHold.swift`: nada clicável da barra de título move a janela; abas e botões da barra a
  travam enquanto o ponteiro está neles (o macOS decide mover a janela antes de o app ver o clique).
- `DesignTokens.swift` e os arquivos de peças `DesignTokensChrome.swift`, `DesignTokensColumns.swift`,
  `DesignTokensCenter.swift`, `DesignTokensPages.swift`, `DesignTokensSidebar.swift` (a barra lateral e o lugar do plano 38) e `DesignTokensMemory.swift` (a página Memória do plano 40): os tokens dos mockups da moldura nova, gerados
  por `../../../../tools/design/build_tokens.py` de `../../../../docs/design/work-frame/tokens.json`
  (não editar à mão). Valores em pontos de desenho: quem usa passa por `pt`, `rowHeight` e `font`.
- `DesignTokensTheme.swift`: a moldura no tema (2026-11-17): cada cor com receita segue o fundo e o
  texto do tema ativo (`applyTheme`; no Cadex Night, os valores dos mockups); as cores de estado
  ficam iguais em todo tema. `repaint` troca, numa janela já montada, cada cor de token pela nova
  (camadas, textos, ícones, botões) e redesenha tudo, sem refazer as views; o texto de um campo é lido
  antes de trocar a cor dele (lido depois, a cor nova era trocada de novo). `glass` (a janela
  translúcida) deixa os chãos (`grounds`) quase transparentes, cada um com o seu alfa; texto e ícone
  na cor de um chão ficam com a cor sólida; `solid` dá a cor sem vidro (o fundo de uma janela opaca,
  como a das configurações) e `didChange` avisa quem monta as cores uma vez. `Glass.swift`: o vidro
  das janelas à parte (⌘K, menus, popovers, configurações): Glass.dress põe o fosco e a cor na
  opacidade da janela debaixo das subviews de uma caixa, ou a cor sólida sem vidro; o app dá a
  opacidade (Glass.set), o vidro forte (`strong`, `tint` a pelo menos 62%) e a cor da borda com brilho
  (`glow`); o que flutua fica 10 pontos acima (`panelTint`). `WindowBlur.swift`: o desfoque de fundo
  de janela do macOS (CGSSetWindowBackgroundBlurRadius, procurado na hora; sem ele, nada), que o vidro
  forte usa no lugar do fosco do sistema, na janela e nos painéis à parte; só numa janela com barra de
  título (`blursWindow`: o macOS desfoca o retângulo inteiro e só corta os cantos dela; nos painéis
  sem moldura arredondados ficava um quadrado desfocado em volta, e eles guardam o fosco recortado
  nos cantos da caixa, `roundedMask`; o dono, 2026-11-27); numa janela adiada, que só
  ganha número ao aparecer, a camada de vidro tenta de novo nas voltas seguintes (as configurações
  mostravam o terminal nítido atrás, 2026-11-27).
- `FrameSheet.swift` e `FrameFields.swift` (plano 31 B): a folha da moldura (o fundo escurecido, o
  painel com as medidas da Nova tarefa, o título, o que vai acontecer, o formulário e o rodapé com
  Cancelar e o botão principal; Esc e ⌘↩) e os controles do sistema sem moldura dentro da caixa do
  pedido (campo, popup, caixa de combinação, área de texto, checkbox), com o rótulo de seção em
  cima. As folhas da orquestração usam (`../../app/FormSheetWiring.swift`), no lugar do alerta do
  sistema.
- `FramePill.swift` (plano 31 C): a pílula de filtro do quadro (components.board.filters.pill), que
  o quadro e o arquivo de conversas usam.
- `UILooks.swift`: o app chama UILooks.configure uma vez, antes de montar qualquer tela. As telas
  pedem `font(_:weight:)` (tamanho do desenho × zoom × fontSize/13, na família escolhida com o
  mesmo peso), `monospaced`/`monospacedDigits` (código curto e números), `pt` (larguras, margens,
  ícones × zoom) e `rowHeight` (alturas × zoom, × 0,85 no compacto, em ponto inteiro).

## Como validar
- `make macos-test` passa: zoom 1,25 dá fonte 13 → 16,25 e 38 pt → 47,5; compacto só nas alturas.
