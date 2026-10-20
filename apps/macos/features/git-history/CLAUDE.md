# git-history (app macOS)

## O que eu quero
- Histórico com grafo de commits, busca, arquivos de cada commit e link para o remoto.

## O que eu não quero
- Desenhar o grafo inteiro de uma vez em repositório grande.
- Importar a source-control: o diff de um arquivo sai por `onOpenDiff` e o app abre a aba de diff.

## Como eu quero
- Usa a feature git-history do núcleo por `HistoryLog.swift` (camada fina sobre `cadex_history_*`,
  uma fila por log; também o modelo: commit, linha do grafo, detalhes).
- `HistoryDocument.swift` é a porta de entrada: a aba (TabDocument) de um repositório; páginas
  pedidas conforme a lista rola, filtro no que já veio, Enter busca no repositório, só a branch
  atual, detalhes e URL do remoto do commit selecionado, recarga quando algo muda em .git
  (`diskChanged`, vindo do watcher do explorer pelo app).
- `HistoryView.swift` (busca, lista, detalhes embaixo), `HistoryRows.swift` (células reaproveitadas
  só das linhas na tela, etiquetas, datas em português, menu de contexto no `MenuTableView` compartilhado), `HistoryGraphView.swift`
  (uma linha do grafo: retas, curvas nas bifurcações e merges, ponto vazado no merge) e
  `HistoryDetailsView.swift` (mensagem, autor, pais, arquivos com +/−; clicar abre o diff).
- Comandos em `HistoryCommands.swift`: git.history (⇧⌘H), history.copy-sha, history.open-remote,
  history.search, history.current-branch, history.refresh. O menu e a caixa de seleção só disparam
  esses ids.
- Spec: `docs/spec/git-history.md`. Status: pronto (plano 6, fase E).

## Como validar
- `make macos-test` passa: linha do log e detalhes lidos, e a aba num repositório temporário com
  merge (grafo, detalhes, filtro, busca, commit novo no topo).
- No app com CADEX_BACKGROUND=1: Visualizar > Abrir o histórico do git, num repositório com merges.
