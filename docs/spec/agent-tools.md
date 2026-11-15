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
  reinicia) num arquivo por conta, e o `context_window` e o `cost` da sessão num arquivo por sessão,
  em `~/Library/Application Support/Cadex/usage` (ou `CADEX_USAGE_DIR`). A conta é a pasta em
  `CLAUDE_CONFIG_DIR`, ou `~/.claude` sem ela. Cada arquivo é escrito inteiro e trocado de uma vez.
- Depois roda a status line que o dono já tinha na conta (`statusLine.command` do `settings.json`
  dela), pelo `/bin/sh`, com o mesmo JSON, e imprime o que ela imprimir. O `--settings` do kit
  substitui a status line da conta na sessão; é assim que ela continua aparecendo igual.
- Nunca lê token, login ou credencial, e não sai para a rede.
- Sem subcomando, ou com um desconhecido, mostra o uso e sai com 2.

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
  (`browser_*`, `preview.md`) e as do computer use (`computer_*`, `computer-use.md`).
- `cadex skills get <tema>`: o guia completo de um tema (o preview, a tarefa, o computer use), da
  mesma versão do app; `cadex skills list` lista os temas. As skills do plugin do kit são curtas:
  dizem quando usar o Cadex e mandam rodar `cadex skills get`.
- A lista do agente (só ela é aceita): os atalhos acima, preview.reload, preview.back,
  preview.forward, as ferramentas do navegador e as do computer use. Nunca: fechar o app, janelas
  ou abas, apagar, git que muda o repositório, conta, token, configuração ou permissão. Só uma ADR
  amplia a lista.
- O que volta de uma página ou de outro app vem marcado como conteúdo, não instrução.
- Configuração agentTools.enabled (ligada): desligada, o kit não põe `PATH`, MCP nem skills, e o
  socket recusa pedidos de comando (os hooks seguem). agent-tools.toggle liga e desliga;
  agent-tools.show-sessions mostra as sessões ligadas e o último pedido de cada uma.
- O kit libera no Claude Code (`permissions.allow`) as ferramentas MCP que só leem (árvore da
  página, print, console, notas); as que agem perguntam ao dono na primeira vez.

## Estados
- **JSON sem `rate_limits`** (antes da primeira resposta da sessão): só o arquivo da sessão.
- **Conta sem status line própria**: não imprime nada.
- **Pasta de uso que não existe**: é criada.

- **App fechado:** `cadex run` e os atalhos dizem "Cadex is not running" e saem com 1; o MCP responde
  o mesmo erro a cada ferramenta.
- **agentTools.enabled desligada:** "Agent tools are off in Cadex" (saída 1).

## Casos de borda
- Sem token, token de uma sessão que já não existe, ou outro usuário no socket: recusado sem
  resposta (o `cadex` diz "not a session opened by Cadex", saída 1).
- Comando fora da lista (fechar o app, apagar): "not allowed for agents", saída 1; nada roda.
- Argumento demais ou faltando: o erro diz o que o comando espera.
- JSON quebrado: nada é gravado; a status line do dono roda do mesmo jeito.
- Status line do dono quebrada, lenta ou muda: o uso já foi gravado antes; ela tem 10 s e 64 KB de
  saída; falhando, a linha fica vazia e a sessão não sente.
- A status line do dono chama o próprio `cadex statusline`: a chamada de dentro não faz nada
  (`CADEX_STATUSLINE`), sem laço.
- `session_id` com caractere estranho (barra, ponto): o arquivo da sessão não é gravado.

## Critérios de aceite
- [x] Com o JSON de uma sessão, grava o arquivo da conta com o `rate_limits` e o da sessão com
      contexto e custo, e imprime a saída da status line do dono (teste do núcleo e na mão,
      2026-11-14).
- [x] Numa sessão real aberta com o comando do kit, o cartão da conta mostra os mesmos números do
      `/usage` (bhband, Claude Code 2.1.325, 2026-11-14: 3% e 56%, reinícios iguais).
- [x] A status line do dono aparece igual numa sessão aberta pelo Cadex (mesma sessão).
- [ ] Numa aba aberta pelo Cadex, `cadex notify "oi"` mostra a notificação e `cadex worktree status
      review` muda o status da tarefa; num terminal de fora (sem o token), `cadex` é recusado.
- [ ] Um comando fora da lista (fechar o app) é recusado e nada acontece.
- [ ] `cadex skills get preview` devolve o guia da mesma versão do app.
- [ ] O `~/.claude` do dono não muda (datas dos arquivos antes e depois).
- [ ] O Claude Code de uma sessão do Cadex chama `mcp__cadex__cadex_notify` e o dono vê a notificação.
