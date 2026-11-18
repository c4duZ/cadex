# Plano 31 — As telas que ficaram na casca velha

Depende de: plano 30 · Features: source-control, review, orchestration, agents, settings, shared/customize,
terminal, preview, memory · Decisões: `docs/adr/0035-work-frame.md` · Origem: a auditoria de UX de
2026-11-17 (o dono: "resolve 1 a 6"), que achou também o travamento da revisão (corrigido antes,
9df527d).

## O que eu quero
- As telas que os mockups não desenham com a cara da moldura: as mesmas peças e os mesmos tokens
  (`docs/design/work-frame/tokens.json`), nada do visual do sistema que destoa.
- O que é para ler de corpo inteiro abre no centro inteiro (página, isPage), não ao lado do terminal.

## O que eu não quero
- Inventar cara nova: cada tela usa uma peça que a moldura já tem (o cartão do quadro, a linha do
  Changes, a folha Nova tarefa, a linha das configurações, os botões do app).
- Dois jeitos de ver um diff: o diff de um arquivo e o de um commit são a revisão, aberta no arquivo.

## Como eu quero
- **A. Diff e revisão.** Feita (2026-11-18, 6c988d3), conferida no app. A revisão é página; o painel da direita fecha enquanto ela aparece (a lista
  dela é a mesma) e volta depois, como no quadro. Clicar num arquivo no Changes (ou git.open-diff*)
  abre a revisão naquele arquivo; o diff de um commit é a revisão de `sha^` a `sha`; o
  `DiffDocument` sai. Cores: color.diff.*, a lista com as medidas de components.inspector.fileRow, a
  barra com os botões do app.
- **B. Folhas.** Feita (e748bb9): a `FrameSheet` e os `FrameField` em shared/looks; Add Task, Despacho e Dependências também. New Run e New Automation como a folha Nova tarefa (a mesma moldura, campos e botões),
  no lugar do alerta do sistema.
- **C. Archive & history** feita (d33df5b): a `FramePill` subiu para shared/looks. Como página, com a linha e o cartão da moldura e os filtros em pílula (os
  do quadro).
- **D. Configurações e personalizar** feita (388a9b4): as seções e as páginas em pílulas. Com os tokens: fundo, cartões, controles (a chave da página do
  projeto, botões do app), sem "spaces" nem "Agents" nos textos.
- **E. O resto** feito (31f1a2a): e mais, uma página nunca abre ao lado de um terminal; o histórico do git, a transcrição e o briefing viraram páginas. Busca do terminal, notas do preview, transcrição, editor de comentário da revisão,
  conflito, o botão Preview do Markdown; o briefing da memória desligada diz por quê.
- **F. Fechamento** feito (2026-11-18): `make check` e `make perf` passando (76 medidas; a revisão abre em 0,7 s e gasta menos CPU que antes), cada tela conferida no app e posta ao lado da de antes. Inventário, specs, manifestos, `make check`, `make perf`, cada tela conferida no
  app.

## Como validar
- `make check` a cada fase; `make perf` no fim.
- Cada tela da auditoria capturada de novo no app, antes e depois.
