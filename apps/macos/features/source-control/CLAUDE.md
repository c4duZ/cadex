# source-control (app macOS)

## O que eu quero
- Painel com mudanças, stage por arquivo, commit (Cmd+Enter), push e pull, troca de branch.
- Diff lado a lado ou unificado.
- A aba de revisão (plano 21): todas as mudanças de uma worktree contra a base, num lugar só, com
  stage por trecho e por linha.

## O que eu não quero
- Ação destrutiva sem confirmação.
- Rodar git na thread principal: cada chamada ao núcleo bloqueia até o git terminar.

## Como eu quero
- Usa a feature source-control do núcleo por `GitRepository.swift` (camada fina sobre `cadex_git_*`,
  uma fila serial por repositório, porque o index.lock não deixa dois git juntos).
- `SourceControlController.swift` é a porta de entrada: acha o repositório da pasta do workspace,
  estados (sem repositório, git ausente, carregando, pronto), atualiza quando o disco muda
  (`diskChanged`, as mudanças do watcher do explorer, inclusive em .git) e faz as ações; confirma
  descartar (arquivo novo vai para a Lixeira), commit sem nada staged e publicar a branch. Avisa o
  app por closures: `onMarks` (marcas do explorer), `onOpenDiff`, `onOpenFile`.
- `SourceControlView.swift` (listas, mensagem, estados; a branch e os botões ficam no cabeçalho da
  barra lateral, que o app enche por `onBranch` e `onBusy`) e
  `SourceControlRow.swift` (linhas, cores das letras, até 1000 por lista, menu de contexto no `MenuTableView` compartilhado).
- Comandos em `SourceControlCommands.swift`: git.commit, git.stage-all, git.unstage-all, git.stage,
  git.unstage, git.discard, git.open-diff e git.open-file (com -beside e -in-tab: ao lado, em nova aba; o menu mostra só o que vale
  para a linha, em `SourceControlRow.swift`), git.reveal, git.fetch, git.pull, git.push,
  git.refresh, git.switch-branch (branches na paleta) e diff.toggle-layout. Botões, menu e ⌘Enter
  só disparam esses ids. O git.show (⇧⌘G, mostrar o painel) é registrado em `apps/macos/app/main.swift`.
- `DiffDocument.swift`: aba de diff (TabDocument) com as cores do editor, linhas de `DiffLines.swift`
  marcadas, as duas colunas rolando juntas, ou o patch numa coluna. Com `commit` no DiffRequest, o
  arquivo como aquele commit o mudou (o histórico pede pelo app).
- Revisão (plano 21, fase B2; `docs/spec/review.md`): `GitReview.swift` chama `cadex_git_review_*`
  (base, arquivos, um arquivo, o patch de stage e aplicar linhas). `ReviewLayout.swift`, puro: as
  linhas empilhadas (cabeçalho por arquivo, os números dos dois lados, regiões sem mudança recolhidas
  além das linhas de contexto, abertas uma a uma ou todas) e onde começa cada arquivo e cada mudança.
  `ReviewTextView.swift` desenha só as linhas na tela (`ReviewRowDrawing.swift`: cores do editor,
  colorido uma vez por arquivo ao aparecer, espaços visíveis, quebra de linha pela largura), marca
  linhas pelo clique (⇧ estende) e ↑ ↓. `ReviewTree.swift`: a lista à esquerda (`MenuTableView`),
  que segue o cursor. `ReviewDocument.swift`: a aba (TabDocument), lida na fila do repositório, a
  barra com a base e os totais, j/k e n/p, recolher, quebrar, espaços, trocar a base; relê ao voltar
  à aba e quando o disco muda (`loadSoon`, uma vez por rajada). `ReviewDocumentStaging.swift` e
  `ReviewStaging.swift`: o stage da mudança do cursor ou das linhas marcadas, só no arquivo do cursor:
  adicionada casa pelo número (o lado novo da revisão é o disco, como o do patch não staged),
  removida pelo texto e pelo lugar; o unstage casa pelo texto (o patch staged conta linhas do
  índice). `ReviewCommands.swift`: git.review-open, git.review-compare-worktrees, git.review-set-base
  (branches na paleta, ou um commit digitado), git.review-stage-hunk, git.review-unstage-hunk,
  git.review-stage-lines, git.review-unstage-lines, git.review-next-file (j), git.review-prev-file
  (k), git.review-next-hunk (n), git.review-prev-hunk (p), git.review-toggle-collapse,
  git.review-toggle-wrap, git.review-toggle-whitespace. As teclas de uma letra são atalhos comuns
  de comandos que ficam indisponíveis fora da revisão em foco, e a tecla segue para quem tem o foco.
  A ligação com o app (a pasta, o branch de partida da tarefa, as configurações): `../../app/ReviewWiring.swift`.
- Spec de comportamento em `docs/spec/source-control.md`. Status: pronto (plano 6).
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: status vindo do núcleo, limite de 1000 linhas, linhas do patch, painel
  num repositório temporário fazendo stage e commit; a revisão (`tests/Review.swift`): as linhas e
  as regiões recolhidas, arquivo novo e binário, as linhas marcadas virando linhas do patch, 50
  arquivos com 100 mudanças cada montados rápido, e uma tarefa de verdade contra o main com j/k e o
  stage de uma mudança.
- No app com CADEX_BACKGROUND=1: Visualizar > Mostrar o Git, um commit feito no terminal some da
  lista sozinho, e PATH sem git mostra a mensagem de instalar.
