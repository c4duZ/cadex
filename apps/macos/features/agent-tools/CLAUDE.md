# agent-tools (app macOS)

## O que eu quero
- O socket do app (app.sock), por onde as sessões que o Cadex abre falam com ele: os hooks pelo
  `cadex hook` (`../../../../core/features/agent-tools/CLAUDE.md`) e, no plano 20, os pedidos de
  comando da CLI e do MCP (`../../../../docs/adr/0022-terminal-daemon.md`,
  `../../../../docs/adr/0024-agent-tools.md`).

## O que eu não quero
- Ouvir qualquer processo: só os deste usuário (`getpeereid`) com o token de uma sessão do Cadex;
  o resto é fechado sem resposta.
- Fazer a sessão esperar: a resposta sai na hora (a permissão, plano 19 fase C, é a exceção da ADR
  0023).
- Token, login ou credencial do Claude Code: o token aqui é do Cadex, um por sessão.

## Como eu quero
- `AgentToolsServer.swift`: AgentToolsServer.shared, `start` (pasta `…/Cadex/sockets` 0700, socket
  0600, troca um velho de um travamento), `stop`, `onEvent` (no main; devolve o que o hook imprime).
  Uma linha JSON entra, uma sai (`{"ok":true}` e, se houver, `stdout`).
- A permissão (ADR 0023): `onPermission` recebe o pedido, a resposta para mandar depois (uma vez,
  no clique) e um aviso de que o hook saiu antes (`AgentToolsOnce.swift`); a conexão fica aberta
  até lá.
- `AgentSessionTokens.swift`: os tokens que o kit da sessão grava (`…/Cadex/sessions/<chave>.token`);
  um token desconhecido faz reler a pasta (sessão que acabou de abrir).
- `AgentHookEvent.swift`: o evento, o pid do `claude` e o que o Claude Code deu ao hook
  (session_id, transcript_path, cwd, source, notification_type, tool_name) e `kitSession`, a sessão
  do kit dona do token (o nome do arquivo dele), que o agente hibernado reaproveita (plano 19, fase F),
  e no PostToolUse o `edit` (AgentEdit: o arquivo e os intervalos de linhas, plano 21 fase E).
- Pedidos de comando (plano 20, fase B): `AgentCommandRequest.swift` (o id ou a lista, os argumentos,
  os pids e a sessão do kit; a resposta `AgentCommandAnswer`; a lista fechada `AgentCommandList`, que
  só uma ADR amplia); o servidor os passa a `onCommand`, que responde uma vez (pode esperar uma página).
  `AgentToolsCommands.swift`: agent-tools.open-file, -open-diff e -notify (com argumentos; pelo dono,
  o comando mais próximo dele), agent-tools.toggle e agent-tools.show-sessions;
  `AgentToolsActivity.swift`: quem usou o Cadex e o último pedido, só em memória;
  `AgentToolsPlugin.swift` e `plugin/`: o plugin de skills curtas que o kit passa por `--plugin-dir`
  (no pacote, em Resources/agent-plugin). O app acha o terminal e roda (`../../app/AgentToolsWiring.swift`).
- O app (`../../app/AgentsWiring.swift`) liga o servidor ao abrir e manda cada evento à feature
  agents (`noteHook`: o id da sessão por pid, certo depois de /clear e --resume).

## Como validar
- `make macos-test` (AgentToolsTests): socket de verdade numa pasta temporária, token certo, errado
  e ausente, token de sessão aberta depois, e o `stdout` de volta ao hook; o pedido de comando com a
  sessão do kit e os pids, a resposta, a recusa sem token; a lista do agente; o plugin.
- Conferido em 2026-11-15 com o `claude` real: SessionStart, /clear (SessionEnd e o id novo), o
  servidor desligado no meio (o Claude não esperou) e de volta com o mesmo token, SessionEnd no /exit.
