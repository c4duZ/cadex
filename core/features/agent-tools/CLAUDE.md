# agent-tools (núcleo)

## O que eu quero
- O programa `cadex` que as sessões de agente abertas pelo Cadex rodam (`../../../docs/spec/agent-tools.md`,
  `../../../docs/adr/0021-cadex-managed-accounts.md`, `../../../docs/adr/0022-terminal-daemon.md`):
  `cadex statusline` e `cadex hook <evento>`; o plano 20 acrescenta mais.

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
- O build (`../../build.zig`, `addCli`) instala `zig-out/bin/cadex` só no Mac; o empacotamento o põe em
  Contents/Helpers.

## Como validar
- `make core-test`: arquivos, nome da conta, status line do dono, JSON quebrado e a chamada de dentro.
- Na mão: `echo '<json>' | CLAUDE_CONFIG_DIR=<pasta> CADEX_USAGE_DIR=<pasta> core/zig-out/bin/cadex statusline`.
