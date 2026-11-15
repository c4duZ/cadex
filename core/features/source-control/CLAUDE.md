# source-control (núcleo)

## O que eu quero
- Status, diff, stage, unstage, descartar, commit, fetch, pull só fast-forward e push.
- O diff de revisão (plano 21): uma worktree inteira contra uma base, ou duas pontas, e o stage e
  unstage de algumas linhas.
- Listar e trocar de branch, saber o upstream e quantos commits à frente e atrás.

## O que eu não quero
- Reimplementar o git: tudo passa pelo binário git do usuário.
- Ação destrutiva (descartar, push) sem o app pedir confirmação antes.
- Comando git sem tempo limite.

## Como eu quero
- Porta de entrada: `source_control.zig`. `git.zig` roda o git pelo executor de `core/shared/process.zig`:
  só em pasta autorizada, 30 s (rede: 2 min), GIT_TERMINAL_PROMPT=0 (senha pedida num terminal que
  não existe travaria até o limite), GIT_OPTIONAL_LOCKS=0, LC_ALL=C, sem editor nem pager; acha a
  raiz do repositório e diz se o git existe (CADEX_GIT_MISSING). No Windows, git fora do PATH é
  procurado onde o Git for Windows instala (`git.zig:installedGit`).
- `status.zig`: porcelain v2 com -z e --branch (branch, upstream, à frente/atrás, cada caminho com
  as letras do índice e da árvore; nomes com espaço, acento e aspas chegam inteiros).
- `actions.zig`: stage, unstage (antes do primeiro commit, rm --cached), descartar (só rastreados;
  novo vai para a Lixeira pelo app), commit pela entrada padrão, fetch, pull só fast-forward (recusa
  divergência com mensagem em português), push sem nunca forçar (publish cria o upstream), branches
  locais e remotas sem par local, trocar de branch, init. Cada ação devolve a mensagem do git ou nada.
- `diff.zig`: os dois lados (HEAD/índice ou índice/disco) e o patch, com aviso de binário e de lado
  acima de 2 MB; `commitSides`, um arquivo como um commit o mudou (para o histórico, da git-history).
- `review.zig` (plano 21): `defaultBase`, o merge-base de HEAD com o branch de partida da tarefa (o
  New Task grava o nome, não o commit), senão com a branch padrão (origin/HEAD, main, master);
  `files`, os arquivos mudados contra a base (commitados, staged, não staged e, com a árvore, os
  novos que o git não conhece, com a contagem de linhas) ou entre duas pontas; `fileSides`, um
  arquivo contra a base, com o patch de "tudo novo" para o arquivo que o git não conhece. Base e
  ponta nunca começam com "-" (não viram opção do git).
- `partial.zig` (plano 21): `filter` recorta o patch nas linhas escolhidas (pelo índice da linha no
  patch; no stage, `+` não escolhida sai e `-` não escolhida vira contexto; no unstage, o
  contrário) e `apply` manda ao `git apply --cached --recount` (e `--reverse`); `patchOf` dá o patch
  de onde escolher, fazendo `add -N` no arquivo novo antes. Nunca toca o disco.
- `conflict.zig` (plano 21, fase C): os blocos de conflito pelos marcadores que o git deixa
  (`<<<<<<<`, `|||||||` do diff3 quando houver, `=======`, `>>>>>>>`; "=======" sozinho na linha,
  os outros com rótulo opcional), resolver um bloco com a nossa, a deles ou as duas, a primeira linha
  com marcador sobrando e `markResolved` (recusa com marcador; grava atômico, mantendo o modo, e faz
  o `git add`). blob, no `diff.zig`: os bytes inteiros de uma versão (commit, índice, ou os estágios `:1`
  `:2` `:3` de um conflito), até 21 MB, para a imagem e as três vias.
- API C em `c_api.zig` (`cadex_git_*`, e `cadex_git_review_*` para o diff de revisão e o stage
  parcial, `cadex_git_show_blob` e `cadex_git_conflict_*`/`cadex_git_mark_resolved` para a fase C),
  listas em linhas com tab.
- Spec: `docs/spec/source-control.md`. Status: pronto (plano 6). A observação do
  repositório é a do explorer no app (as mudanças em .git chegam pelo mesmo watcher).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- `repo_test.zig` com repositórios temporários de verdade: status, stage, unstage, commit, diff,
  renomeação com espaço no nome, pull recusado quando diverge, branches, fora do workspace recusado.
- `review_test.zig`: a worktree de uma tarefa contra onde saiu do main (commit, rename staged,
  edição não staged, arquivo novo, main andando depois), duas pontas, uma linha entrando e saindo do
  índice e uma linha de um arquivo novo; um conflito de merge de verdade (os três estágios, o bloco,
  recusado com marcador, resolvido e no stage).
