# worktrees

## Para que serve
Cada tarefa num repositório vira uma worktree do git com branch e agente próprios: começar uma é um
comando, e o Cadex mostra em que pé cada uma está (`docs/plans/19-agent-sessions-and-worktrees.md`).

## Comportamento
### Nova tarefa
- "New Task" (worktrees.new-task, no ⌘K) pede o nome da tarefa e mostra o branch que ele vira
  ("Corrigir login" → `corrigir-login`) e o ponto de partida (o branch atual, que fica gravado para
  a revisão do plano 21). Confirmado:
  1. cria a worktree e o branch pelo `git` do dono, em worktrees.root (padrão: ao lado do
     repositório, em `<repo>.worktrees/<branch>`);
  2. copia para lá os arquivos fora do git que o `.worktreeinclude` do repositório lista (`.env` e
     afins; mesmo formato do `.gitignore`);
  3. roda os hooks de preparo do repositório (`pnpm install`, `direnv allow`…) num terminal da
     tarefa, com a saída à vista;
  4. abre o agente sem prompt, na conta do projeto ou na ativa (`docs/adr/0021-cadex-managed-accounts.md`).
- A pasta das worktrees pode cair fora dos diretórios autorizados (feature `workspace`): na primeira
  tarefa de um repositório, o Cadex pede para autorizá-la, uma vez; recusar deixa escolher outra raiz.
- Confiança do Claude Code: numa pasta nunca aberta, o diálogo "trust this folder" segura o agente.
  Numa worktree, a confiança que vale é a do repositório principal: aceitar na aba de uma tarefa
  grava a confiança do repositório e cobre todas as tarefas dele, as de antes e as de depois; aceitar
  só em `<repo>.worktrees/` não cobre as worktrees (testado em 2026-11-15, Claude Code 2.1.325).
  Repositório já confiado não pergunta nada. Na primeira tarefa de um repositório, o Cadex explica
  isso numa folha, sem abrir aba a mais. O Cadex não escreve no `.claude.json`.
- A conversa não é copiada entre worktrees: de dentro de uma worktree, `claude --resume <id>` acha a
  conversa do repositório, e a memória automática é uma só (teste de 2026-11-14).

### Status e comentário
- Cada worktree tem um status (a fazer, em andamento, em revisão, pronto) e um comentário curto do que
  está fazendo agora, guardados pelo Cadex (nunca no git). Mudados por worktrees.set-status e
  worktrees.set-comment (o agente também, pelo canal do plano 20).
- Aparecem na lista de worktrees e no título do grupo do projeto em Agents › Sessions.

### Hooks de preparo
- Por repositório, nas configurações (worktrees.setupHooks: comandos em ordem). Antes de rodarem pela
  primeira vez num repositório, o Cadex os mostra e pede confirmação (worktrees.edit-setup-hooks
  muda a lista).

### Outros comandos
- worktrees.open: a worktree vira o workspace da janela, com o terminal da tarefa.
- worktrees.remove: tira a worktree (e, se pedido, o branch), com confirmação; mudanças não salvas
  ou não enviadas impedem e o Cadex diz quais.

## Estados
- **Repositório sem worktree de tarefa**: a lista diz "No tasks yet" e oferece New Task.
- **Preparando**: a tarefa aparece "setting up" enquanto copia e roda os hooks; um hook que falha
  deixa a tarefa criada, com o terminal mostrando o erro e "Run Setup Again".
- **Fora de um repositório git**: New Task explica que precisa de um repositório.
- **Sem git instalado**: a feature some, como a source-control.

## Casos de borda
- Nome que vira branch existente: o Cadex sugere outro (`corrigir-login-2`) e mostra antes.
- `.worktreeinclude` citando arquivo que não existe: pula e conta no fim.
- Worktree apagada por fora (`git worktree remove`, pasta apagada): sai da lista, sem erro.
- Repositório com worktrees criadas fora do Cadex: aparecem na lista, sem status até alguém dar um.
- Hook de preparo que espera entrada: o terminal da tarefa recebe as teclas, como qualquer terminal.

## Critérios de aceite
- [ ] New Task num repositório com `.worktreeinclude` e um hook de preparo cria a worktree e o
      branch, copia o `.env`, roda o hook e abre o agente na conta do projeto. (Conferido por partes
      em 2026-11-15: núcleo e app num repositório de verdade, e o comando "hooks && claude" com o
      `claude` real; falta o clique no app, visto pelo dono.)
- [x] A pasta das worktrees fora do workspace pede autorização uma vez.
- [x] Depois de aceitar a confiança na primeira tarefa, a segunda abre sem diálogo.
- [x] Remover com mudanças não salvas é recusado e diz quais arquivos.
- [x] Status e comentário voltam iguais depois de reabrir o app.
- [x] Testes do núcleo com um repositório falso, sem vazamento (`make core-test`).
