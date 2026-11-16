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

### Rodar em outra máquina (plano 23, `docs/adr/0031-run-on-remote.md`)
- O "New Task" ganha "Run on": este Mac (o padrão), um host do `~/.ssh/config` ou uma máquina da
  tailnet (`docs/spec/machines.md`). worktrees.new-task-on abre o "New Task" já nessa escolha.
- Numa máquina remota, uma aba de terminal abre `ssh` nela e roda lá os mesmos passos: acha o
  repositório (pelo remoto `origin` do repositório daqui, na pasta que o dono informou na primeira
  vez, lembrada por máquina; sem ele, oferece clonar), `git worktree add`, os hooks de preparo do
  repositório e, por fim, `claude` na pasta da worktree, com o login do Claude do remoto. Nada é
  copiado daqui (nem `.worktreeinclude`, nem conta, nem chave): o que o remoto precisa, ele tem.
- A worktree remota aparece na lista com o nome da máquina ("corrigir-login · pc"), com status e
  comentário como as outras. A sessão aparece em Agents como "em pc"
  (`docs/spec/agents.md`).
- worktrees.open-remote-shell abre outra aba ssh na pasta da worktree remota.
- Fechar a aba não apaga a worktree remota; worktrees.remove numa remota roda o `git worktree
  remove` lá, com a mesma confirmação.
- Fica para depois (o `cadexd`): diff, editor e revisão do que está no remoto, e o estado da sessão
  por hooks.

### Ambiente descartável (plano 23, `docs/adr/0032-workspace-recipes.md`)
- Num repositório com `.cadex/environment.toml`, o "New Task" mostra a receita (imagem, máquina,
  portas) e cria, junto com a worktree, um contêiner na máquina da receita (ou na escolhida no
  "Run on"); roda o comando de preparo dentro dele e abre o agente lá dentro.
- O ambiente segue a tarefa: hibernar a tarefa (plano 19) suspende o contêiner; abrir de novo o
  retoma; worktrees.remove pergunta também se destrói o contêiner (o padrão é sim). Comandos
  worktrees.environment-up, worktrees.environment-suspend, worktrees.environment-resume e
  worktrees.environment-destroy (este com confirmação).
- A chave do Tailscale do sidecar vem do ambiente do dono na hora de subir; faltando, o Cadex diz
  qual variável falta e não sobe o sidecar.
- Subir é digitado numa aba (a saída à vista, e a chave lida pelo shell do dono, nunca pelo Cadex).
  O contêiner fica onde a worktree está: neste Mac, ou na máquina da tarefa remota pelo contexto do
  Docker dela; numa remota, os hooks de preparo não rodam (o `setup` da receita faz esse papel).
- O agente dentro do contêiner não tem os hooks do Cadex e não hiberna sozinho; o que suspende o
  ambiente é hibernar um agente do Mac na pasta da tarefa, ou o comando.
- A receita, com tudo que ela aceita:

  ```toml
  image = "ubuntu:24.04"      # ou dockerfile = "Dockerfile.dev" (só neste Mac)
  machine = "pc"              # a escolha inicial do "Run on"
  ports = [3000, 5173]
  setup = "apt-get update && apt-get install -y nodejs"
  workdir = "/work"
  [tailscale]
  name = "ubuntu-dev"
  authkey_env = "TS_AUTHKEY"  # o nome da variável, nunca a chave
  ```

### Corrida e despacho (plano 24, `docs/spec/orchestration.md`)
- A feature `orchestration` cria worktrees pelo mesmo New Task, sem a folha: uma corrida cria N do
  mesmo commit (`<tarefa>-1` … `<tarefa>-N`), e um despacho cria uma por tarefa. Os passos são os
  mesmos (`.worktreeinclude`, hooks de preparo, confiança), e o agente abre **com prompt**
  (`docs/adr/0033-cadex-launches-agents.md`) em vez de sem.
- Essas worktrees aparecem na lista como as outras, com o nome da corrida ou da execução no
  comentário. Descartar uma corrida manda as worktrees para a Lixeira pelo mesmo caminho do
  worktrees.remove, com a branch mantida até o dono apagar.

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
- Máquina remota offline ou ssh recusado: a aba mostra o erro do `ssh`, e a tarefa não aparece
  na lista até a worktree existir lá.
- Receita com erro (TOML inválido, imagem que não baixa): a worktree é criada, o ambiente não, e
  o terminal da tarefa mostra o erro com "Try Again".

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
- [ ] "New Task" em "Run on: pc" cria a worktree no PC e abre `claude` lá numa aba; a sessão
      aparece em Agents como "em pc"; fechar a aba não apaga a worktree remota.
- [ ] Uma receita de teste sobe o contêiner, o agente roda dentro dele, suspender e retomar
      preservam os arquivos, destruir remove o contêiner e pede confirmação.
