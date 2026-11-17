# inspector (app macOS)

## O que eu quero
- O painel da direita (`../../../../docs/spec/inspector.md`, plano 26 fase C): as abas Changes,
  Files, History e Memory com "⌥⌘I", a linha de contexto com os botões da aba, e a página dela,
  na cara da peça Inspector (`../../../../docs/design/work-frame/screens.md`, components.inspector).

## O que eu não quero
- Esta feature conhecendo o source-control, o explorer, o git-history ou a memory: o app passa a
  view de cada aba (`../../app/InspectorWiring.swift`).
- Clique que faz a ação por conta própria: a aba e cada botão rodam um comando pelo id (ADR 0005).
- Aba lendo escondida: só a aba aberta fica sem isHidden, e com o painel fechado ele todo fica
  escondido, então a página que lê só enquanto aparece não lê.
- Valor digitado: só `DesignTokens` (`../../../../tools/check_design_literals.py`).

## Como eu quero
- `InspectorTab.swift`: a aba (id, título, comando, view, botões e o "⋯"), `InspectorAction` e
  `InspectorScope` (as palavras da linha de contexto, com comando e dica opcionais).
- `InspectorView.swift`: a porta de entrada. `show` mostra uma aba e avisa `onShow`; `setScope`
  troca as palavras da linha de contexto de uma aba (a pasta, o branch, a memória do projeto);
  `setBusy` gira o indicador; até 3 botões, o resto no "⋯" (PopupMenu de `../../shared/menus`).
  As palavras ocupam o que sobra e os botões ficam à direita.
- `InspectorEdge.swift`: a borda esquerda, uma faixa de 5 pt com o cursor de redimensionar; arrastar
  pede a largura (`onResize`), e o app a limita (Settings.inspectorWidths) e salva ao soltar
  (inspector.width).
- `InspectorParts.swift`: o nome da aba (sublinhada a aberta) e o botão de ícone de 24 pt, aceso
  sob o ponteiro como os da barra de título.
- Status: fase C1 no código (o painel, as abas com as páginas de antes, ⌥⌘I, o botão da barra de
  título, inspector.visible e inspector.tab salvos). C2a a C2d feitas: as abas no desenho, a borda arrastável e
  a janela estreita (abaixo de 1000 pt, abrir o painel recolhe a barra lateral, e fechá-lo a devolve).

## Como validar
- `make macos-test` passa: as abas na ordem, uma página à vista e as outras escondidas, a linha de
  contexto (o nome da aba ou as palavras do app, três botões e o "⋯"), o clique na aba rodando o
  comando dela.
