# source-control (app macOS)

## O que eu quero
- Painel com mudanças, stage por arquivo, commit (Cmd+Enter), push e pull, troca de branch.
- Diff lado a lado ou unificado.

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
- Spec de comportamento em `docs/spec/source-control.md`. Status: pronto (plano 6).
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: status vindo do núcleo, limite de 1000 linhas, linhas do patch, painel
  num repositório temporário fazendo stage e commit.
- No app com CADEX_BACKGROUND=1: Visualizar > Mostrar o Git, um commit feito no terminal some da
  lista sozinho, e PATH sem git mostra a mensagem de instalar.
