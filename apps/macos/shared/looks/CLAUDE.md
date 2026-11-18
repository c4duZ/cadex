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
  `DesignTokensCenter.swift` e `DesignTokensPages.swift`: os tokens dos mockups da moldura nova, gerados
  por `../../../../tools/design/build_tokens.py` de `../../../../docs/design/work-frame/tokens.json`
  (não editar à mão). Valores em pontos de desenho: quem usa passa por `pt`, `rowHeight` e `font`.
- `DesignTokensTheme.swift`: a moldura no tema (2026-11-17): cada cor com receita segue o fundo e o
  texto do tema ativo (`applyTheme`; no Cadex Night, os valores dos mockups); as cores de estado
  ficam iguais em todo tema. `repaint` troca, numa janela já montada, cada cor de token pela nova
  (camadas, textos, ícones, botões) e redesenha tudo, sem refazer as views.
- `FrameSheet.swift` e `FrameFields.swift` (plano 31 B): a folha da moldura (o fundo escurecido, o
  painel com as medidas da Nova tarefa, o título, o que vai acontecer, o formulário e o rodapé com
  Cancelar e o botão principal; Esc e ⌘↩) e os controles do sistema sem moldura dentro da caixa do
  pedido (campo, popup, caixa de combinação, área de texto, checkbox), com o rótulo de seção em
  cima. As folhas da orquestração usam (`../../app/FormSheetWiring.swift`), no lugar do alerta do
  sistema.
- `UILooks.swift`: o app chama UILooks.configure uma vez, antes de montar qualquer tela. As telas
  pedem `font(_:weight:)` (tamanho do desenho × zoom × fontSize/13, na família escolhida com o
  mesmo peso), `monospaced`/`monospacedDigits` (código curto e números), `pt` (larguras, margens,
  ícones × zoom) e `rowHeight` (alturas × zoom, × 0,85 no compacto, em ponto inteiro).

## Como validar
- `make macos-test` passa: zoom 1,25 dá fonte 13 → 16,25 e 38 pt → 47,5; compacto só nas alturas.
