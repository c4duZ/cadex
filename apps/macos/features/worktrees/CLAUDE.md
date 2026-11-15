# worktrees (app macOS)

## O que eu quero
- As tarefas de um repositório (`../../../../docs/spec/worktrees.md`, plano 19 fase D): New Task cria a
  worktree e o branch, copia os arquivos fora do git, roda os hooks de preparo e abre o agente;
  cada tarefa tem status e comentário; sair só sem perder trabalho.

## O que eu não quero
- Reimplementar o git: tudo pelo núcleo (`../../../../core/features/worktrees/CLAUDE.md`).
- Guardar status ou comentário no git: é nota do Cadex.
- Escrever no .claude.json: a confiança da pasta é o próprio Claude Code que pergunta.

## Como eu quero
- `WorktreesCore.swift`: a camada fina sobre `cadex_worktrees_*` (e a raiz do repositório, o branch
  atual e a autorização da pasta).
- `WorktreesStore.swift`: as notas em `…/Cadex/worktrees.json`: por tarefa o status (a fazer, em
  andamento, em revisão, pronto), o comentário, o ponto de partida e a data; por repositório os hooks
  já vistos e se a aba da confiança já foi mostrada.
- `WorktreesController.swift`: WorktreesController.shared. `plan` (branch único, pasta
  `<repo>.worktrees/<branch>` ou worktrees.root, ponto de partida, o que pede um sim: autorizar a
  pasta, hooks novos, a confiança), `make`, `tasks`, `note` (para o grupo em Agents),
  `whatWouldBeLost`, `remove`, `setStatus`, `setComment`.
- `WorktreesView.swift`: a página Tasks (lê só enquanto aparece). `WorktreesCommands.swift`:
  worktrees.new-task, -open, -remove, -set-status, -set-comment e -edit-setup-hooks, com as listas
  no ⌘K; o que pergunta e abre abas é do app (`../../app/WorktreesWiring.swift`).

## Como validar
- `make macos-test` (WorktreesTests): num repositório de verdade, o plano, a tarefa criada com o
  `.env`, as notas que voltam depois de reabrir, a segunda tarefa sem pedir nada, a remoção recusada
  com mudança e aceita sem ela.
