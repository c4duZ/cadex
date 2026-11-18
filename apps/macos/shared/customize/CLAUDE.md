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
  acima do primeiro título), virar a chave e `dropIndex`, a vaga sob o meio do que se arrasta.
- `CustomizeList.swift`: a lista desenhada (títulos, linhas em caixa com alça, ícone, nome, linha
  menor opcional, valor numa coluna fixa e chave); arrastar reorganiza enquanto o mouse se move,
  com a linha por cima das outras, e avisa uma vez ao soltar.
- `CustomizePage.swift`: `CustomizePage` (uma lista para arrumar: os itens da barra de status, as
  contas; quem monta recebe cada mudança) e `CustomizeColors` (`.frame`: os tokens da moldura).
  `CustomizePageView.swift`: a lista dentro de outra vista, as seções Barra de status e Agentes e
  contas da janela de configurações (plano 32 B; a janela Personalizar, com abas, saiu: o dono quis
  tudo nas configurações, 2026-11-18). Cada mudança vai na hora para o `onChange`; `refresh` mostra o
  que mudou por fora. `ThemeSwitch.swift`: a chave do app, pública, a mesma das configurações.

## Como validar
- `make macos-test` passa: seções, mover entre seções, chave, a vaga, o arrastar com eventos de
  mouse e a janela única com abas. Com CADEX_SNAPSHOT_DIR, o teste salva customize-status.png para ver sem captura de tela.
