# inspector (app macOS)

## O que eu quero
- A coluna lateral (`../../../../docs/adr/0038-rail-and-side-column.md`, plano 36 fase A; a peça Rail
  de `../../../../docs/design/work-frame/screens.md`): à esquerda, ao lado do trilho, os ícones das
  páginas no topo (o nome sob o ponteiro), a página, e no pé a linha de contexto com os botões da
  página. Era o painel da direita (`../../../../docs/spec/inspector.md`, plano 26 fase C); a spec
  muda na fase G do plano 36.

## O que eu não quero
- Esta feature conhecendo o source-control, o explorer, o git-history ou a memory: o app passa a
  view de cada aba (`../../app/InspectorWiring.swift`).
- Clique que faz a ação por conta própria: a aba e cada botão rodam um comando pelo id (ADR 0005).
- Aba lendo escondida: só a aba aberta fica sem isHidden, e com o painel fechado ele todo fica
  escondido, então a página que lê só enquanto aparece não lê.
- Valor digitado: só `DesignTokens` (`../../../../tools/check_design_literals.py`).

## Como eu quero
- `InspectorTab.swift`: a aba (id, título, ícone, comando, view, botões e o "⋯"), `InspectorAction` e
  `InspectorScope` (as palavras da linha de contexto, com comando e dica opcionais).
- `InspectorView.swift`: a porta de entrada. `show` mostra uma aba e avisa `onShow`; `setScope`
  troca as palavras da linha de contexto de uma aba (a pasta, o branch, a memória do projeto);
  `setBusy` gira o indicador; até 3 botões, o resto no "⋯" (PopupMenu de `../../shared/menus`).
  As palavras ocupam o que sobra e os botões ficam à direita.
- `InspectorEdge.swift`: a borda direita (a coluna fica à esquerda do centro), uma faixa de 5 pt com o cursor de redimensionar; arrastar
  pede a largura (`onResize`), e o app a limita (Settings.inspectorWidths) e salva ao soltar
  (inspector.width). `reorder` põe as páginas na ordem arrastada no trilho (plano 36 E;
  inspector.order), que os inspector.tab-N seguem.
- `InspectorParts.swift`: a aba como ícone num quadro de 40×30, acesa com o fundo escolhido
  (components.inspector.iconTabs), e o botão de ícone de 24 pt do pé, aceso sob o ponteiro como os
  da barra de título.
- Status: fase C1 no código (o painel, as abas com as páginas de antes, ⌥⌘I, o botão da barra de
  título, inspector.visible e inspector.tab salvos). C2a a C2d feitas: as abas no desenho e a borda arrastável.
  Plano 36 fase A: a coluna à esquerda, os ícones no topo e a linha de contexto no pé; a regra da
  janela estreita saiu (a nova vem na fase F). Fase C: `tabsOnTop` falso tira a fileira de ícones
  (o app usa assim: os ícones foram para o trilho, o dono em 2026-11-18); `pages` dá as abas ao
  trilho.

## Como validar
- `make macos-test` passa: as abas na ordem, uma página à vista e as outras escondidas, a linha de
  contexto (o nome da aba ou as palavras do app, três botões e o "⋯"), o clique na aba rodando o
  comando dela.
