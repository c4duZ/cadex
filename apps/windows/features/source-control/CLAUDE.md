# source-control (app Windows)

## O que eu quero
- A página Git do painel lateral do Mac: branch com ↑/↓ do upstream, listas Conflitos, Staged e
  Mudanças com as letras coloridas, stage/unstage por arquivo e "tudo", descartar, mensagem com
  Ctrl+Enter, fetch/pull/push com indicador e a mensagem do git, troca de branch na paleta,
  "Inicializar repositório" e, sem git, o link do Git for Windows.
- O diff num painel: lado a lado ou o patch (diff.toggle-layout), binário e grande avisados.

## O que eu não quero
- Git na thread da janela: cada `cadex_git_*` bloqueia até o git acabar (até 2 min no push).
- Ação destrutiva sem pergunta; dois git ao mesmo tempo no mesmo repositório (index.lock).
- Importar o miolo de outra feature: o app liga tudo pelo `host.zig:Host`.

## Como eu quero
- Porta de entrada: `source_control.zig` (SourceControl, Host, DiffRequest, DiffDocument, register,
  draw). O app cria com `controller.zig:create`, chama `setFolder` (pasta do workspace ou do
  terminal com foco), `diskChanged` (mudanças do disco, .git incluída), `frame` a cada quadro
  (aplica o que o git terminou e desenha a pergunta aberta) e `draw` onde a página aparece.
- `worker.zig`: uma thread por dono, jobs em ordem (SRWLOCK e CONDITION_VARIABLE); o resultado
  volta na thread da janela e o `Host.post_redraw` (PostMessage) acorda o quadro. `jobs.zig`: achar
  o repositório, status, ações e branches, cada um com cópias do que precisa.
- `repository.zig`: camada fina sobre `cadex_git_*` (mensagem curta, até 4000 caminhos por chamada,
  caminho absoluto com `\`). `status.zig`: status do núcleo e as linhas, até 1000 por lista, puros e
  testados. `selection.zig`: seleção por caminho, sobrevive ao refresh.
- `panel.zig` (topo, mensagem, estados), `change_list.zig` (linhas, + e − ao passar o mouse,
  Ctrl+clique, menu de contexto, teclado), `question.zig` (descartar, commit de tudo, publicar a
  branch; arquivo novo vai para a Lixeira pelo Host), `branches.zig` (a lista da paleta),
  `opening.zig` (diff, abrir, revelar).
- `diff_document.zig` (Document com worker próprio; `from` acha o diff do painel com foco),
  `diff_view.zig` (colunas com número de linha, rolagem proporcional) e `diff_lines.zig` (linhas
  marcadas pelo patch, testado).
- Comandos em `commands.zig`: git.commit, git.stage-all, git.unstage-all, git.stage, git.unstage,
  git.discard, git.open-diff e git.open-file (com -beside e -in-tab; o menu de `change_list.zig` mostra só o
  que vale para a linha), git.reveal, git.fetch, git.pull, git.push,
  git.refresh, git.switch-branch e diff.toggle-layout. O git.show (mostrar a página) é do app.
- Spec: `../../../../docs/spec/source-control.md`. Referência: `../../../macos/features/source-control/`.
- Altura das linhas das mudanças por `rowPx` (densidade compacta, plano 15).

## Como validar
- `make windows-app` compila os testes (status, linhas, seleção, diff, caminhos); rodam na VM.
- Na VM, com o Git for Windows: stage, commit com Ctrl+Enter, descartar arquivo novo (Lixeira),
  push sem upstream pergunta, e PATH sem git mostra o link.
