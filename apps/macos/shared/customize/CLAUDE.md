# customize (compartilhado do app)

## O que eu quero
- A janela Customize de todo o app: mostrar, esconder e arrastar coisas para o lugar, com a cara do
  protótipo aprovado pelo dono em 2026-10-21 e das configurações. Usada pela barra lateral (os
  ícones) e pela barra de status (os itens, em Left e Right).

## O que eu não quero
- Cada feature com a própria lista de personalizar: duas já usam esta.
- Popover do sistema, chave azul ou anel de foco (o dono recusou em 2026-10-21).

## Como eu quero
- `CustomizeLayout.swift`: o modelo (`CustomizeRow`, `CustomizeEntry` com títulos de seção) e as
  regras puras: as seções, mover uma linha (passando por um título ela muda de seção; nada sobe
  acima do primeiro título), virar a chave e `dropIndex`, a vaga sob o meio do que se arrasta
  (também usada pela fileira de ícones da barra lateral).
- `CustomizeList.swift`: a lista desenhada (títulos, linhas em caixa com alça, ícone, nome, linha
  menor opcional, valor numa coluna fixa e chave); arrastar reorganiza enquanto o mouse se move,
  com a linha por cima das outras, e avisa uma vez ao soltar.
- `CustomizeWindow.swift`: uma janela só para o app (`shared`), como a de configurações, com uma aba
  por `CustomizePage` (Sidebar, Status Bar; o dono pediu uma janela com abas, 2026-10-21). Por cima
  do app em tela cheia, na mesma mesa (fullScreenAuxiliary e moveToActiveSpace, a lição das
  configurações); centrada sobre a janela de onde abriu; fecha com Esc, ⌘W ou o botão. Cada mudança
  vai na hora para o `onChange` da aba aberta, com a lista inteira; `refresh` mostra o que mudou por
  fora; `recolor` repinta na troca de tema. O desenho é o das configurações: abas no topo, título
  da página em 20 pt, legenda, linhas em caixa com cantos de 8 pt e borda de 1 pt (o dono pediu as
  duas janelas iguais, 2026-10-21). `CustomizeColors` vem do tema, pelo app, nunca do destaque da
  janela (que a cor do space troca); `ThemeSwitch`, a chave do app na cor de destaque, pública: as configurações usam a mesma.

## Como validar
- `make macos-test` passa: seções, mover entre seções, chave, a vaga, o arrastar com eventos de
  mouse e a janela única com abas. Com CADEX_SNAPSHOT_DIR, o teste salva customize-status.png para ver sem captura de tela.
