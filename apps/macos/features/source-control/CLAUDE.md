# source-control (app macOS)

## O que eu quero
- A aba Changes do painel da direita (plano 26 fase C2; `../../../../docs/spec/inspector.md`): Last
  turn, Task e Uncommitted, um arquivo por linha com a letra, a pasta e +/−, Commit… e Open PR; stage
  por arquivo no clique direito, push e pull, troca de branch.
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
- `SourceControlView.swift`: a aba, na cara da peça Inspector (o seletor, a lista, o pé com Commit…
  e Open PR, os estados; a branch e os botões ficam na linha de contexto do painel, que o app enche
  por `onBranch` e `onBusy`). `ChangesScope.swift`: as três listas e `ChangesRow` (até 500, com a
  entrada do status pelo caminho, para stage, descartar e o diff). `SourceControlChanges.swift`: a
  leitura da lista na fila do repositório depois de cada status (contra HEAD; contra a base da
  tarefa, `taskStart`; a última rodada filtra pelos arquivos que o app diz, `lastTurnFiles`; sem HEAD
  ainda, os arquivos do status sem números), o clique (o diff sem commit, ou a revisão), o Commit…
  (a mensagem numa folha; nada no stage, tudo entra) e o Open PR (`onOpenPullRequest`).
  `ChangesRowView.swift`: a linha, o seletor e o menu de contexto no `MenuTableView` compartilhado.
- Comandos em `SourceControlCommands.swift`: git.commit, git.open-pr, git.changes-last-turn,
  git.changes-task, git.changes-uncommitted (os três do seletor), git.stage-all, git.unstage-all, git.stage,
  git.unstage, git.discard, git.open-diff e git.open-file (com -beside e -in-tab: ao lado, em nova aba; o menu mostra só o que vale
  para a linha, em `ChangesRowView.swift`), git.reveal, git.fetch, git.pull, git.push,
  git.refresh, git.switch-branch (branches na paleta) e diff.toggle-layout. Botões, seletor e menu
  só disparam esses ids. O git.show (⇧⌘G, mostrar o painel) é registrado em `apps/macos/app/main.swift`.
- `DiffDocument.swift`: aba de diff (TabDocument) com as cores do editor, linhas de `DiffLines.swift`
  marcadas, as duas colunas rolando juntas, ou o patch numa coluna. Com `commit` no DiffRequest, o
  arquivo como aquele commit o mudou (o histórico pede pelo app).
- Revisão (plano 21, fase B2; `docs/spec/review.md`): `GitReview.swift` chama `cadex_git_review_*`
  (base, arquivos, um arquivo, o patch de stage e aplicar linhas); ReviewTally (público, plano 24)
  conta arquivos e linhas de uma worktree contra o ponto de partida, para o quadro da corrida. `ReviewLayout.swift`, puro: as
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
- Imagem e conflito (plano 21, fase C): `GitConflict.swift` chama `cadex_git_show_blob` e
  `cadex_git_conflict_*`. `ImageDiffView.swift`: as duas versões de uma imagem (NSImage, pelo
  ImageIO) lado a lado, deslizando uma barra ou sobrepostas com a opacidade num controle, e os
  tamanhos embaixo; acima de 20 MB só os tamanhos. Aparece na aba de diff (`DiffDocument.swift`, no
  lugar de "arquivo binário") e na revisão, como uma linha alta com a vista por cima
  (`ReviewTextView.swift`). `ConflictDocument.swift`: o arquivo com U em três colunas (base, a nossa
  e a deles, os estágios `:1` `:2` `:3`) e o resultado editável embaixo, os blocos pintados; a
  nossa, a deles e as duas agem no bloco do cursor; marcar resolvido grava e faz o stage, recusado com
  marcador sobrando (o cursor vai à linha). Abre pelo painel (DiffRequest.conflict) e pela revisão
  (clique direito no arquivo U). `ConflictCommands.swift`: git.accept-ours, git.accept-theirs,
  git.accept-both, git.mark-resolved e git.review-image-mode; os botões da barra só rodam os ids.
- A porta da revisão para os comentários (plano 21, fase D), sem saber deles: `ReviewAnnotation.swift`
  (ReviewAnnotation, a nota que o app prende sob uma linha, ou no topo do arquivo quando
  desatualizada, e abre a região recolhida em que cai; ReviewLineSelection, as linhas marcadas com o
  texto e 3 linhas em volta) e `ReviewDocumentNotes.swift` (a seleção, os textos de cada arquivo, a
  nota do cursor, onde ancorar o popover, o botão da barra, `announce`). A aba desenha a nota numa
  caixa, mostra "+" na margem ao passar sobre uma linha (apertar e arrastar ali pede um comentário
  das linhas) e avisa por onLoaded, onAnnotation e onCommentRequest. A autoria (fase E) também
  chega de fora: `lineMarks` (arquivo → linha nova → sessão) vira uma barra fina na borda e a sessão
  no tooltip; `marksStopped` põe "autoria parada" no cabeçalho do arquivo.
- Spec de comportamento em `docs/spec/source-control.md`. Status: pronto (plano 6).
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: status vindo do núcleo, limite de 1000 linhas, linhas do patch, painel
  num repositório temporário fazendo stage e commit; a revisão (`tests/Review.swift`): as linhas e
  as regiões recolhidas, arquivo novo e binário, as linhas marcadas virando linhas do patch, 50
  arquivos com 100 mudanças cada montados rápido, e uma tarefa de verdade contra o main com j/k e o
  stage de uma mudança; a fase C (`tests/Conflict.swift`): um conflito de verdade resolvido pela aba
  (recusado com marcador, a deles, resolvido e no stage) e uma imagem mudada na revisão e no diff,
  com o modo trocando.
- No app com CADEX_BACKGROUND=1: Visualizar > Mostrar o Git, um commit feito no terminal some da
  lista sozinho, e PATH sem git mostra a mensagem de instalar.
