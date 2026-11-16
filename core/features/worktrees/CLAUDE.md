# worktrees (núcleo)

## O que eu quero
- A worktree de uma tarefa pelo `git` do usuário (`../../../docs/spec/worktrees.md`, plano 19 fase D):
  o branch que o nome vira, as worktrees do repositório, criar uma com os arquivos fora do git que
  o `.worktreeinclude` pede, e tirar uma só quando nada se perde.

## O que eu não quero
- Reimplementar o git, nem rodar fora de pasta autorizada: tudo pelo executor da source-control.
- Perder trabalho: worktree com mudança, ou branch com commit que nenhum outro branch tem, não sai.

## Como eu quero
- Porta de entrada: `worktrees.zig`. `tasks.zig`: `branchName` (letras e dígitos ASCII em minúsculas,
  acento tirado, o resto como "-", até 60), `list` (`git worktree list --porcelain`), `create`
  (`git worktree add -b`, só com a pasta-mãe autorizada), `whatWouldBeLost` (o `status` e os
  commits só desse branch) e `remove` (`git worktree remove` e, se pedido, `git branch -d`, que
  recusa branch não juntado); `prune` (`git worktree prune`, depois de a pasta de uma worktree
  descartada ser apagada pelo app, plano 24) e `deleteBranch` (`git branch -D`, com a confirmação no
  app; nome começando com "-" recusado).
- `include.zig`: o `.worktreeinclude` no formato do `.gitignore` (âncora, pasta, "!", a última linha
  vence) aplicado ao que o git não rastreia (`git ls-files --others --directory`); copia com
  `../../shared/fs.zig` (clone no APFS) e conta as linhas que não casaram com nada.
- API C em `c_api.zig` (`cadex_worktrees_*`), declarada em `../../include/cadex.h`.

## Como validar
- `make core-test`: o nome do branch, e num repositório de verdade a tarefa criada com o `.env` e
  uma pasta copiados, a lista, o que se perderia (mudança, commit só dela), a remoção recusada com
  mudança e aceita depois do merge, e a pasta fora do workspace recusada; a pasta sumida esquecida
  pelo `prune` com a branch ficando, e a branch apagada depois.
