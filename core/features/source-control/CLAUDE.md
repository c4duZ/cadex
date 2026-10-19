# source-control (núcleo)

## O que eu quero
- Status, diff, stage, unstage, descartar, commit, fetch, pull só fast-forward e push.
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
- API C em `c_api.zig` (`cadex_git_*`), listas em linhas com tab.
- Spec: `docs/spec/source-control.md`. Status: pronto (plano 6). A observação do
  repositório é a do explorer no app (as mudanças em .git chegam pelo mesmo watcher).

## Como validar
- `make core-test` (ou `zig build test` dentro de `core/`) passa, sem vazamento no alocador de teste.
- `repo_test.zig` com repositórios temporários de verdade: status, stage, unstage, commit, diff,
  renomeação com espaço no nome, pull recusado quando diverge, branches, fora do workspace recusado.
