# git-history (app Windows)

## O que eu quero
- O histórico do Mac num painel: grafo com faixas e curvas, etiquetas, autor, data relativa no
  idioma da interface e sha curto; páginas de 500 ao rolar; filtro no que veio e Enter busca no repositório;
  só a branch atual; detalhes do commit com os arquivos e +/−; diff de um arquivo do commit, copiar
  sha e abrir no remoto.

## O que eu não quero
- Desenhar o grafo inteiro de uma vez: só as linhas na tela.
- Git na thread da janela, ou importar a source-control: o diff do commit sai por
  `host.zig:Host` (open_commit_diff) e o app abre o DiffDocument de lá.

## Como eu quero
- Porta de entrada: `git_history.zig` (HistoryDocument, Host, register). `document.zig`: o Document
  de um repositório (páginas, filtro, busca, só a branch atual, seleção, detalhes, recarga meio
  segundo depois de mudanças em .git por `diskChanged`); `from` acha o histórico do painel com foco.
  `feed.zig`: o que um log trouxe e as linhas mostradas.
- `worker.zig` (cópia do da source-control: feature não usa o miolo de outra) e `jobs.zig`: o log do
  núcleo só é tocado no worker; próxima página, fechar o log, detalhes e URL do remoto.
- `log.zig`: linha do log, segmentos do grafo e detalhes, puros e testados. `dates.zig`: "3 hours ago" ou "há 3 horas"
  e a data longa em en-US ou pt-BR (strings.language), no fuso do sistema.
- `view.zig` (busca, alternador, contagem, terço de baixo), `rows.zig` (colunas, etiquetas, página
  seguinte 100 linhas antes do fim, menu), `graph.zig` (retas, curvas em S em oito pedaços, ponto
  vazado no merge) e `details.zig` (mensagem, autor, pais, arquivos clicáveis).
- Comandos em `commands.zig`: git.history (sem atalho, onde a configuração diz), git.history-in-tab, history.copy-sha, history.open-remote,
  history.search, history.current-branch, history.refresh.
- Spec: `../../../../docs/spec/git-history.md`. Referência: `../../../macos/features/git-history/`.
- Altura das linhas da lista e dos arquivos por `rowPx` (densidade compacta, plano 15).

## Como validar
- `make windows-app` compila os testes (log, detalhes, datas, curva, .git); rodam na VM.
- Na VM: abrir o histórico num repositório com merges, rolar até a segunda página, buscar com Enter.
