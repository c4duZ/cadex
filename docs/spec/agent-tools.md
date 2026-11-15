# agent-tools

## Para que serve
O programa `cadex`, que as sessões de agente abertas pelo Cadex rodam. Não tem interface: é a ponte
entre o Claude Code e o app (`docs/adr/0021-cadex-managed-accounts.md`). Nasce com um subcomando, a
status line; os planos 19 e 20 acrescentam outros (estado da sessão, comandos para o agente usar o
Cadex).

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

## Estados
- **JSON sem `rate_limits`** (antes da primeira resposta da sessão): só o arquivo da sessão.
- **Conta sem status line própria**: não imprime nada.
- **Pasta de uso que não existe**: é criada.

## Casos de borda
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
