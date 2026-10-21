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
- `compact` (a página Git History da barra lateral): só o grafo e a descrição, sem títulos de
  coluna, autor, data, sha, caixa de seleção e contagem. A descrição nunca quebra linha (com
  etiquetas, quebrava por cima da linha de baixo; print do dono, 2026-10-21); os detalhes ficam um
  embaixo do outro. O separador entre a lista e os detalhes tem 1 pt fixo: sem isso, na página
  estreita ele tomou a altura toda e a lista ficou com zero (conferido no app, 2026-10-21).
- `HistoryView.swift` (busca, lista, detalhes embaixo), `HistoryRows.swift` (células reaproveitadas
  só das linhas na tela, etiquetas, datas em português, menu de contexto no `MenuTableView` compartilhado), `HistoryGraphView.swift`
  (uma linha do grafo: retas, curvas nas bifurcações e merges, ponto vazado no merge) e
  `HistoryDetailsView.swift` (mensagem, autor, pais, arquivos com +/−; clicar abre o diff).
- Comandos em `HistoryCommands.swift`: git.history (sem atalho, onde a configuração diz), git.history-in-tab, history.copy-sha, history.open-remote,
  history.search, history.current-branch, history.refresh. O menu e a caixa de seleção só disparam
  esses ids.
- Spec: `docs/spec/git-history.md`. Status: pronto (plano 6, fase E).
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: linha do log e detalhes lidos, e a aba num repositório temporário com
  merge (grafo, detalhes, filtro, busca, commit novo no topo).
- No app com CADEX_BACKGROUND=1: Visualizar > Abrir o histórico do git, num repositório com merges.
