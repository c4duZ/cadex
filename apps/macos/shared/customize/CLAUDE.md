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
- `CustomizeWindow.swift`: a janela na frente do app, centrada sobre ele, nas cores do tema
  (`CustomizeColors`); fecha com Esc, ⌘W ou o botão. Cada mudança sai na hora por `onChange` com a
  lista inteira; quem abriu tira dela o que guardar. `CustomizeToggle`, a chave na cor de destaque.

## Como validar
- `make macos-test` passa: seções, mover entre seções, chave, a vaga e o arrastar com eventos de
  mouse. Com CADEX_SNAPSHOT_DIR, o teste salva customize-status.png para ver sem captura de tela.
