# session-kit (app macOS)

## O que eu quero
- A única peça que monta o que uma sessão do Claude Code aberta pelo Cadex recebe: `--settings`,
  `--plugin-dir`, `--mcp-config` e o ambiente da aba
  (`../../../../docs/adr/0021-cadex-managed-accounts.md`, plano 18 fase B).
- Fica em shared antes de ter dois usuários porque os planos 19 a 24 (worktrees, review, memória,
  orquestração) acrescentam itens a ela pela porta de contribuição; hoje só a feature agents a usa.

## O que eu não quero
- Escrever na configuração de conta nenhuma (.claude.json, settings.json): o kit só passa
  argumentos e arquivos próprios.
- Token, login ou credencial.
- Feature importando outra para contribuir: cada uma chama `contribute` pelo app.

## Como eu quero
- `SessionKit.swift`: SessionKit.shared; `claudeCommand` (com `session:`, retoma uma sessão do kit e
  o token dela, para o agente hibernado voltar conhecido pelo app; os argumentos de cada sessão ficam
  ao lado do token, `arguments(of:)`, para ele voltar com o mesmo comando) devolve o comando digitado no terminal
  (`[env -u …] [CLAUDE_CONFIG_DIR=…] claude --settings … [--plugin-dir …] [--mcp-config …] args`),
  escrevendo antes os arquivos. O ambiente perde CLAUDECODE e CLAUDE_CODE_* herdados (um
  CLAUDE_CODE_CHILD_SESSION herdado desligou o transcript, 2026-11-14) e, na conta padrão, um
  CLAUDE_CONFIG_DIR solto. `contribute`/`withdraw` com um `SessionKitPart`. `findTools` acha o `cadex`
  em Contents/Helpers ou, no `make run`, em `core/zig-out/bin`. `accountKey` é a regra do nome do
  arquivo de uso, igual à do `cadex statusline`.
- `SessionKitFiles.swift`: em `~/Library/Application Support/Cadex/kit`, um `session-<chave>.json`
  por sessão (0600, apagado depois de 2 dias) com a status line do Cadex (com o `padding` da do
  dono), o token da sessão na `env` (que chega aos hooks, teste de 2026-11-15; nunca digitado no
  terminal), os hooks do plano 19 (`cadex hook <evento>` em SessionStart, Stop, Notification,
  PermissionRequest, SessionEnd e CwdChanged, com `hooksEnabled` = agents.stateHooks) e o que as
  features contribuem; o token também num arquivo `…/Cadex/sessions/<chave>.token` (0600, 30 dias),
  que o socket do app lê (objetos se
  juntam, listas se somam: hooks de duas features no mesmo evento rodam os dois); e, para contas que
  não são a padrão, `mcp-<conta>.json` (0600) com os `mcpServers` do .claude.json da conta padrão,
  lidos sem escrever.
- `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` na `env` do `--settings` (`synchronizedOutput`): o terminal respeita
  o modo DEC 2026 (plano 19, fase E) e, com ele, o Claude Code manda cada redesenho num bloco
  (testado em 2026-11-15). Sem `preferredNotifChannel`: os avisos
  de agente já vêm pelos hooks e pelo 7501, e o terminal mostra o OSC 777 de qualquer programa (o
  dono, 2026-11-15). O `cadex` no PATH da aba
  entra com o primeiro subcomando que o agente usa (plano 20).

## Como validar
- `make macos-test` (SessionKitTests): comando por conta, ambiente limpo, status line com o padding
  do dono, MCP só para as outras contas e com 0600, contribuições somadas, aspas só quando precisa.
