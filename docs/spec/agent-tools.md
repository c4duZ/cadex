# agent-tools

## Para que serve
O programa `cadex`, que as sessões de agente abertas pelo Cadex rodam. Não tem interface: é a ponte
entre o Claude Code e o app (`docs/adr/0021-cadex-managed-accounts.md`). Nasce com um subcomando, a
status line; os planos 19 e 20 acrescentam outros (estado da sessão, comandos para o agente usar o
Cadex: `docs/adr/0024-agent-tools.md`).

## Comportamento
### `cadex statusline`
- É o comando da status line que o kit da sessão põe no `--settings` das sessões que o Cadex abre.
  O Claude Code o chama a cada mensagem, com um JSON na entrada.
- Do JSON, guarda o `rate_limits` da conta (a sessão de 5 h e a semana, com a porcentagem e quando
  reinicia) num arquivo por conta, e o `context_window`, o `cost` e o `model` da sessão num arquivo
  por sessão,
  em `~/Library/Application Support/Cadex/usage` (ou `CADEX_USAGE_DIR`). A conta é a pasta em
  `CLAUDE_CONFIG_DIR`, ou `~/.claude` sem ela. Cada arquivo é escrito inteiro e trocado de uma vez.
- Depois imprime a linha do painel do mockup (plano 28 fase C), uma só: o modelo, o contexto com a
  barra, o custo e a pasta ("Opus  context ━━──────── 5%  US$ 0.31  orchestration-e"), nas cores
  ANSI que o tema do Cadex dá. A status line que a conta tinha (`statusLine.command`) não roda nas
  sessões que o Cadex abre: o `--settings` do kit a substitui. Num `claude` aberto fora do Cadex, a
  da conta continua.
- Nunca lê token, login ou credencial, e não sai para a rede.
- Sem subcomando, ou com um desconhecido, mostra o uso e sai com 2.

### `cadex codex` (plano 29)
- `cadex codex [palavras…] --cadex-prompt-file <arquivo>`: o Codex com o pedido do dono, lido do
  arquivo que o Cadex escreveu (as mesmas regras do `cadex claude`: só da pasta dos prompts, só deste
  usuário, apagado depois de lido) e passado ao `codex` depois de "--", como uma palavra do exec,
  nunca num comando de shell. Sem kit: o Codex não tem hooks nem status line que o Cadex leia.
  CADEX_CODEX_BIN aponta um `codex` falso numa instância de teste.

### `cadex hook <evento>` (plano 19)
- É o comando dos hooks que o kit da sessão põe nas sessões que o Cadex abre. Lê o JSON que o Claude
  Code dá ao hook e manda ao socket do app (`…/Cadex/sockets/app.sock`) o token da sessão, o evento,
  o pid do `claude` e o JSON.
- Nunca faz a sessão esperar: 200 ms pela resposta; com o app fechado, sai na hora. A exceção é a
  permissão (`docs/adr/0023-answer-agent-permissions.md`), que espera o clique do dono.
- Imprime o que o app mandar imprimir (a decisão de uma permissão) e sai sempre com 0.

### O agente usa o Cadex (plano 20, `docs/adr/0024-agent-tools.md`)
- Só nas sessões que o Cadex abre: o comando que abre o agente põe a pasta do `cadex`
  (Contents/Helpers do app) no `PATH`, o `--mcp-config` do kit registra `cadex mcp`, o `--plugin-dir`
  traz as skills, e o token está no `env` do `--settings`, que chega à ferramenta Bash e ao servidor
  MCP (testado em 2026-11-15); o arquivo do MCP, um por conta, nunca leva o token. Uma sessão aberta fora do Cadex não tem o `cadex` no `PATH` nem o token.
- `cadex run <id> [chave=valor…]` pede ao app que rode o comando `<id>` com os argumentos; responde
  com o resultado (texto, ou JSON com `--json`) e sai com 0, ou com o erro e sai com 1.
  `cadex commands` lista o que o agente pode rodar, com os argumentos de cada um.
- Atalhos:
  - `cadex open <arquivo>[:linha]` (agent-tools.open-file): abre no Cadex, ao lado do terminal do
    agente, na linha dada.
  - `cadex diff [arquivo]` (agent-tools.open-diff): o diff do arquivo, ou o da tarefa inteira.
  - `cadex preview <endereço>` (preview.open com o endereço): abre ou reusa a aba de preview da tarefa.
  - `cadex notify "<texto>"` (agent-tools.notify): uma notificação do macOS e uma linha no feed, com o
    nome da conversa; o clique leva ao terminal do agente.
  - `cadex worktree status <todo|doing|review|done>` e `cadex worktree comment "<texto>"`
    (worktrees.set-status e worktrees.set-comment com o argumento): da tarefa do terminal do agente,
    sem lista nenhuma na tela.
- Recebendo argumentos, um comando da lista do agente não abre lista nem pergunta nada na tela:
  age direto, ou recusa com o motivo (arquivo fora da tarefa, status desconhecido).
- `cadex mcp`: servidor MCP pela entrada e saída padrão, com as mesmas ações como ferramentas
  (`cadex_open`, `cadex_diff`, `cadex_notify`, `cadex_worktree_status`, …), as do navegador
  (`browser_*`, `preview.md`) e as do computer use (`computer_*`, `computer-use.md`). As instruções
  que ele dá ao começar dizem qual navegador usar, pela escolha do dono em Configurações › O que os
  agentes podem usar (agentTools.webBrowser, padrão "cadex"): o preview do Cadex ao lado do terminal,
  onde o dono vê e intervém, nunca Playwright nem navegador escondido; o Claude in Chrome; o Claude
  in Chrome ou o Playwright; ou nada. Outro app vai sempre pelas `computer_*` do Cadex, com o
  computer use ligado; desligado, não dizem nada dele (o dono, 2026-11-24).
- `cadex skills get <tema>`: o guia completo de um tema (o preview, a tarefa, o computer use), da
  mesma versão do app; `cadex skills list` lista os temas. As skills do plugin do kit são curtas:
  dizem quando usar o Cadex e mandam rodar `cadex skills get`.
- A lista do agente (só ela é aceita): os atalhos acima, preview.reload, preview.back,
  preview.forward, preview.agent (as ferramentas do navegador) e as do computer use. Nunca: fechar o app, janelas
  ou abas, apagar, git que muda o repositório, conta, token, configuração ou permissão. Só uma ADR
  amplia a lista.
- Ampliada pela `docs/adr/0033-cadex-launches-agents.md` (plano 24) com os de reporte:
  orchestration.report-done, orchestration.report-heartbeat, orchestration.ask,
  orchestration.send-message, orchestration.inbox e orchestration.spawn, aceitos só de uma sessão
  de despacho (o app acha o despacho pela sessão do token; o CADEX_DISPATCH_ID que o `cadex` manda
  só é conferido contra ele, e outro é recusado) ou do coordenador da execução, e só sobre a
  execução dela; sem ela, "this session is not a task of a Cadex run", saída 1. orchestration.retry
  só do coordenador. Aprovar portão, parar despacho e mexer em automação continuam fora. O kit
  libera esses comandos (`Bash(cadex run orchestration.<id>:*)`) e `cadex skills get` sem o Claude
  Code perguntar ao dono a cada um (plano 24 D2). `spec-file=<arquivo>` manda o texto do arquivo
  como `spec=`, lido pelo `cadex` (até 100 KB, sem NUL); o guia é `cadex skills get orchestration`
  e a skill curta `cadex-orchestration` vai no plugin do kit.
- `cadex claude --cadex-prompt-file <arquivo>` (plano 24): lê o prompt do arquivo que o Cadex
  gravou, apaga o arquivo e o passa ao `claude` como um argumento do exec, sem shell no meio.
- O que volta de uma página ou de outro app vem marcado como conteúdo, não instrução.
- Configuração agentTools.enabled (ligada): desligada, o kit não põe `PATH`, MCP nem skills, e o
  socket recusa pedidos de comando (os hooks seguem). agent-tools.toggle liga e desliga;
  agent-tools.show-sessions mostra as sessões ligadas e o último pedido de cada uma.
- O kit libera no Claude Code (`permissions.allow`) as ferramentas MCP que só leem (árvore da
  página, print, console, notas); as que agem perguntam ao dono na primeira vez.

### Pelo telefone (plano 39, `docs/plans/39-terminals-from-the-phone.md`)
O dono, no telefone, entra por SSH no Mac pela tailnet e usa o `cadex` de um terminal que não é aba
do Cadex (sem token: vale porque é o mesmo usuário do Mac, e só para estes comandos).
- `cadex` sem argumentos: o menu numerado de projetos e abas; um número entra numa aba, `n` abre um
  terminal no projeto, `c` abre o Claude.
- `cadex attach [id]`: entra numa aba aberta no Cadex, com a tela de antes, ao vivo; o Mac continua
  mostrando a mesma aba e os dois digitam. O tamanho é o menor dos dois e volta quando o telefone
  sai. Ctrl+\ e depois `d` sai sem fechar nada. A aba no Mac mostra uma marca enquanto há alguém de
  fora.
- `cadex new <projeto> [claude]`: abre a aba no Cadex do Mac pelo comando registrado (com memória,
  hooks e status, como um clique) e entra nela. Com o app fechado, abre o app antes.
- `cadex share <arquivo>`: devolve um link da tailnet (com token, por uma hora) que abre o arquivo no
  Safari do telefone, numa página com o nome, o arquivo à vista e Baixar: HTML funcionando (com o que
  carrega da pasta dele), imagem, PDF, vídeo, áudio, Word, Excel, PowerPoint (pelo Quick Look do
  iPhone), Markdown renderizado e texto ou código. Sem argumento, lista os links que ainda valem.
  Nada escuta fora do IP do Tailscale; sem Tailscale, diz isso e sai.

## Estados
- **JSON sem `rate_limits`** (antes da primeira resposta da sessão): só o arquivo da sessão.
- **JSON sem modelo, contexto ou custo**: a linha fica sem a parte que falta; sem nenhuma, vazia.
- **Pasta de uso que não existe**: é criada.

- **App fechado:** `cadex run` e os atalhos dizem "Cadex is not running" e saem com 1; o MCP responde
  o mesmo erro a cada ferramenta.
- **agentTools.enabled desligada:** "Agent tools are off in Cadex" (saída 1).

## Casos de borda
- Sem token, token de uma sessão que já não existe, ou outro usuário no socket: recusado sem
  resposta (o `cadex` diz "not a session opened by Cadex", saída 1).
- Comando fora da lista (fechar o app, apagar): "not allowed for agents", saída 1; nada roda.
- Argumento demais ou faltando: o erro diz o que o comando espera.
- JSON quebrado: nada é gravado e a linha fica vazia; a sessão não sente.
- `session_id` com caractere estranho (barra, ponto): o arquivo da sessão não é gravado.

## Critérios de aceite
- [x] Com o JSON de uma sessão, grava o arquivo da conta com o `rate_limits` e o da sessão com
      contexto, custo e modelo, e imprime a linha do painel (teste do núcleo; a linha, plano 28
      fase C, 2026-11-17).
- [x] Numa sessão real aberta com o comando do kit, o cartão da conta mostra os mesmos números do
      `/usage` (bhband, Claude Code 2.1.325, 2026-11-14: 3% e 56%, reinícios iguais).
- [ ] Numa sessão aberta pelo Cadex, a status line é a linha do painel, em uma linha (plano 28 fase C).
- [x] Numa aba aberta pelo Cadex, `cadex notify "oi"` avisa o dono e `cadex worktree status review`
      muda o status da tarefa; num terminal de fora (sem o token), `cadex` é recusado. (2026-11-15, o
      `claude` real numa instância de teste do app de release: "the task is review", "the owner was
      notified", e o app gravou o status; a notificação na tela, sem captura, não vista.)
- [x] Um comando fora da lista (fechar o app) é recusado e nada acontece ("app.quit is not allowed
      for agents", saída 1).
- [x] `cadex skills get preview` devolve o guia da mesma versão do app (os guias vêm do binário).
- [x] O `~/.claude` do dono não muda (datas dos arquivos antes e depois do teste).
- [x] O Claude Code de uma sessão do Cadex chama uma ferramenta `mcp__cadex__*` e o app age
      (`cadex_worktree_comment`: o comentário gravado).
- [ ] Plano 39: do telefone, `cadex attach` entra numa aba com o Claude aberto no Mac, o que se digita
      lá aparece no Mac e o Mac não perde a aba; `cadex new cadex claude` abre uma aba que aparece no
      Mac; `cadex share` de um HTML, um PDF, uma imagem e um .docx abre cada um no Safari pela
      tailnet, e nada abre pelo IP da rede local.
