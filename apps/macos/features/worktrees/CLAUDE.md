# worktrees (app macOS)

## O que eu quero
- As tarefas de um repositório (`../../../../docs/spec/worktrees.md`, plano 19 fase D): New Task cria a
  worktree e o branch, copia os arquivos fora do git, roda os hooks de preparo e abre o agente;
  cada tarefa tem status e comentário; sair só sem perder trabalho.

## O que eu não quero
- Reimplementar o git: tudo pelo núcleo (`../../../../core/features/worktrees/CLAUDE.md`). A
  exceção é o "Rodar em" (plano 23): o git de outra máquina, que o núcleo daqui não alcança, roda lá
  pelo ssh do dono.
- Guardar status ou comentário no git: é nota do Cadex.
- Escrever no .claude.json: a confiança da pasta é o próprio Claude Code que pergunta.

## Como eu quero
- `WorktreesCore.swift`: a camada fina sobre `cadex_worktrees_*` (e a raiz do repositório, o branch
  atual e a autorização da pasta).
- `WorktreesStore.swift`: as notas em `…/Cadex/worktrees.json`: por tarefa o status (a fazer, em
  andamento, em revisão, pronto), o comentário, o ponto de partida e a data; por repositório os hooks
  já vistos e se o aviso da confiança já foi mostrado.
- `WorktreesController.swift`: WorktreesController.shared. `plan` (branch único, pasta
  `<repo>.worktrees/<branch>` ou worktrees.root, ponto de partida, o que pede um sim: autorizar a
  pasta, hooks novos, a confiança), `make`, `tasks`, `note` (para o grupo em Agents),
  `whatWouldBeLost`, `remove`, `setStatus` (avisa `onStatusChange`: o app passa "review" à memória
  como marco de consolidação, plano 22 fase F), `setComment`.
- worktrees.set-status e -set-comment também aceitam `status=` e `comment=` do agente (plano 20): da
  tarefa do terminal dele (`taskOf`, só uma worktree de tarefa, nunca o repositório), sem lista.
- `WorktreesView.swift`: a página Tasks (lê só enquanto aparece). `WorktreesCommands.swift`:
  worktrees.new-task, -open, -remove, -set-status, -set-comment e -edit-setup-hooks, com as listas
  no ⌘K; o que pergunta e abre abas é do app (`../../app/WorktreesWiring.swift`).
- "Rodar em" outra máquina (plano 23, fase C; `../../../../docs/adr/0031-run-on-remote.md`, o
  mínimo): `RemoteTaskScript.swift` (puro: o script que acha ou clona o repositório lá, busca o
  origin e faz `git worktree add` a partir do `base` do origin, branch único como aqui, e imprime
  `CADEX_TASK_PATH`/`CADEX_TASK_BRANCH`; o de remover; a aba com os hooks e `claude` por um shell de
  login; tudo entre aspas simples), `RemoteTasks.swift` (`RemoteTask`, `RunTarget` e o
  `RemoteTaskRunner`: `ssh -o BatchMode=yes`, nunca pergunta; o 255 do ssh vira "conecte numa aba"
  ou "não respondeu") e `WorktreesRemote.swift` (`makeRemote` e `removeRemote`: a tarefa só entra na
  lista quando a worktree existe lá; a pasta do repositório por máquina fica lembrada). As notas
  ganham `remote` e `remoteFolders`, lidas com `decodeIfPresent` (um arquivo de antes continua
  valendo inteiro). A página Tasks mostra a remota com o nome da máquina; worktrees.new-task-on e
  worktrees.open-remote-shell, e worktrees.remove lista as remotas também.

## Como validar
- `make macos-test` (WorktreesTests): num repositório de verdade, o plano, a tarefa criada com o
  `.env`, as notas que voltam depois de reabrir, a segunda tarefa sem pedir nada, a remoção recusada
  com mudança e aceita sem ela; o "Rodar em" com um ssh falso que roda o comando aqui
  (`tests/Remote.swift`): a worktree feita "lá", o nome único, sem repositório (pergunta antes de
  clonar), a remoção recusada com mudança, as falhas do ssh, a aba com os hooks e o claude.
