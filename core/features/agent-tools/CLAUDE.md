# agent-tools (núcleo)

## O que eu quero
- O programa `cadex` que as sessões de agente abertas pelo Cadex rodam (`../../../docs/spec/agent-tools.md`,
  `../../../docs/adr/0021-cadex-managed-accounts.md`, `../../../docs/adr/0022-terminal-daemon.md`):
  `cadex statusline` e `cadex hook <evento>`; no plano 20 (`../../../docs/adr/0024-agent-tools.md`), os
  comandos com que o agente usa o Cadex, as skills e o servidor MCP.

## O que eu não quero
- Ler, guardar ou repassar token, login ou credencial do Claude Code; falar com a rede. (O token
  da sessão é do Cadex: vem na env que o kit põe e só vai ao socket do app.)
- Atrapalhar a sessão: erro é engolido, a status line do dono roda mesmo sem o uso gravado.
- Depender da libghostty ou do resto do núcleo: só libc e `../../shared/fs.zig` e `../../shared/process.zig`.

## Como eu quero
- `cli.zig`: o `main` (raiz em `../../cadex_cli.zig`, fora da pasta para poder usar shared/),
  lê a entrada com libc e escolhe o subcomando.
- `statusline.zig`: `files` monta o arquivo da conta (`rate_limits`) e o da sessão (`context_window`,
  `cost`); `accountKey` dá o nome do arquivo da conta (todo byte que não é letra ou dígito ASCII
  vira "-", a mesma regra do SessionKit.accountKey no app); `run` grava primeiro e depois roda a
  status line do dono (`ownerCommand`, do settings.json da conta) pelo `/bin/sh`, com 10 s e 64 KB.
  `CADEX_STATUSLINE` marca a chamada de dentro, que não faz nada.
- `hook.zig`: `cadex hook <evento>` manda ao socket do app uma linha com o token
  (CADEX_SESSION_TOKEN), o evento, o pid do `claude` (o pai do hook) e o JSON reescrito numa linha;
  espera 200 ms (a permissão, 10 min: ADR 0023) e imprime o `stdout` da resposta. App fechado: sai
  na hora. Sempre 0.
- Plano 20, fase B: `agent.zig` escolhe entre `mcp`, `skills` e os subcomandos que pedem ao app;
  `commands.zig` traduz `run`, `commands` e os atalhos (`open`, `diff`, `preview`, `notify`,
  `worktree status|comment`) em id e argumentos; `request.zig` manda ao socket do app uma linha com o
  token, o id (ou a lista), os argumentos e os pids acima do processo (o app acha o terminal do
  agente), espera até 40 s e lê `{"ok", "result"|"error"}`; `skills.zig` traz os guias de `guides/`
  embutidos no binário (`cadex skills list|get`); `mcp.zig` é o servidor MCP (JSON-RPC por linha:
  initialize, tools/list, tools/call, ping), cada ferramenta um pedido de comando. Saída 0 feito, 1
  recusado ou app fechado (o motivo no stderr), 2 uso.
- Fase C e D: `cadex browser goto|snapshot|click|fill|press|scroll|wait|screenshot|console|notes` e as ferramentas
  `browser_*` do MCP viram o comando preview.agent com `action=`; o print volta ao agente como imagem
  (o PNG em base64) e o caminho.
- Fase E: `cadex computer apps|state|click|type|set|scroll|screenshot` e as ferramentas `computer_*`
  viram computer-use.agent com `action=` (`../../../docs/spec/computer-use.md`); o print da janela
  também volta como imagem.
- Plano 21, fase E (`../../../docs/adr/0027-local-authorship.md`): `edits.zig` corta o PostToolUse
  antes do socket: a sessão, a pasta, a ferramenta, o arquivo e os intervalos de linhas escritas,
  tirados do `structuredPatch` (o `newStart` e as linhas `+`); um Write sem patch (o que cria)
  marca o arquivo inteiro, o que reescreve traz patch; nunca o arquivo (`originalFile`) nem o texto
  das linhas.
- O build (`../../build.zig`, `addCli`) instala `zig-out/bin/cadex` só no Mac; o empacotamento o põe em
  Contents/Helpers.

## Como validar
- `make core-test`: arquivos, nome da conta, status line do dono, JSON quebrado e a chamada de dentro;
  a linha do pedido e a resposta, os atalhos virando ids, os guias e o servidor MCP com um app falso.
- Na mão: `echo '<json>' | CLAUDE_CONFIG_DIR=<pasta> CADEX_USAGE_DIR=<pasta> core/zig-out/bin/cadex statusline`.
