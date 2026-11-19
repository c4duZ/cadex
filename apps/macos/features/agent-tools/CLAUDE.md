# agent-tools (app macOS)

## O que eu quero
- O socket do app (app.sock), por onde as sessões que o Cadex abre falam com ele: os hooks pelo
  `cadex hook` (`../../../../core/features/agent-tools/CLAUDE.md`) e, no plano 20, os pedidos de
  comando da CLI e do MCP (`../../../../docs/adr/0022-terminal-daemon.md`,
  `../../../../docs/adr/0024-agent-tools.md`).

## O que eu não quero
- Ouvir qualquer processo: só os deste usuário (`getpeereid`) com o token de uma sessão do Cadex,
  ou, no pedido do kit sem token, de dentro de um terminal do Cadex (a ancestralidade lida do sistema,
  nunca a lista de pids do pedido); o resto é fechado sem resposta ou recusado.
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
  e no PostToolUse o `edit` (AgentEdit: o arquivo e os intervalos de linhas, plano 21 fase E); no
  PreToolUse do AskUserQuestion, `questions` (AgentAskedQuestion: a pergunta, os rótulos das opções
  e o multiSelect; plano 26 D2, o hook que `../../app/AgentsAttention.swift` põe no kit).
- Pedidos de comando (plano 20, fase B): `AgentCommandRequest.swift` (o id ou a lista, os argumentos,
  os pids, a sessão do kit e o CADEX_DISPATCH_ID que o `cadex` mandou; a resposta
  `AgentCommandAnswer`; a lista fechada `AgentCommandList`, que só uma ADR amplia, com os sete da
  orquestração da ADR 0033); a sessão e o despacho seguem no CommandRequest até o comando; o servidor os passa a `onCommand`, que responde uma vez (pode esperar uma página).
  `AgentToolsCommands.swift`: agent-tools.open-file, -open-diff e -notify (com argumentos; pelo dono,
  o comando mais próximo dele), agent-tools.toggle e agent-tools.show-sessions;
  `AgentToolsActivity.swift`: quem usou o Cadex e o último pedido, só em memória;
  `AgentToolsPlugin.swift` e `plugin/`: o plugin de skills curtas (`cadex`, `cadex-task` e
  `cadex-orchestration`) que o kit passa por `--plugin-dir`
  (no pacote, em Resources/agent-plugin). O app acha o terminal e roda (`../../app/AgentToolsWiring.swift`).
- O kit do `claude` digitado (plano 22, fase C): `AgentKitRequest.swift` lê o pedido do
  `cadex claude` (`"kit":true`, sem token), a ancestralidade de quem conectou (LOCAL_PEERPID e o
  pai de cada um pelo sysctl) e `comesFrom(shells:)`; o servidor o passa a `onKit`, que responde na
  hora com `AgentKitAnswer` (`args`, `unset`, `path_first`, ou a recusa). O app confere os shells dos
  terminais e monta o kit (`../../app/TypedClaudeWiring.swift`).
- `onDue` (plano 24, fase E, `../../../../docs/adr/0034-scheduled-automations.md`): o pedido
  `{"v":1,"due":true}` do `cadex automations due`, sem token e só local (getpeereid): "confira a
  agenda"; não diz o que rodar.
- `onTerminals` (plano 39 B): o pedido `{"v":1,"terminals":true}` do `cadex attach`, sem token e só
  local (getpeereid, o dono no SSH é o mesmo usuário): as abas abertas com o nome da sessão no daemon,
  o projeto, a aba, a pasta e o estado do agente, e os nomes dos projetos (`onProjects`, plano 39 D,
  para o n e o c do menu); nada que o `ps` já não diga. `onNewTerminal` (plano
  39 C): `{"v":1,"new":true,"project","claude"}` do `cadex new`, só local: o app abre a aba pelo
  comando registrado e responde o id dela.
- `serveRemote` (plano 23, fase F): a conexão de outra máquina da tailnet que o listener da feature
  machines já conferiu pelo WhoIs; o mesmo protocolo, só com o token de uma sessão; o pedido do kit
  é fechado (ele confia na ancestralidade de um processo deste Mac).
- O app (`../../app/AgentsWiring.swift`) liga o servidor ao abrir e manda cada evento à feature
  agents (`noteHook`: o id da sessão por pid, certo depois de /clear e --resume).

## Como validar
- `make macos-test` (AgentToolsTests): socket de verdade numa pasta temporária, token certo, errado
  e ausente, token de sessão aberta depois, e o `stdout` de volta ao hook; o pedido de comando com a
  sessão do kit e os pids, a resposta, a recusa sem token; a lista do agente; o plugin; o pedido do
  kit aceito e recusado pela ancestralidade, sem handler recusado; de outra máquina
  (`tests/Remote.swift`), o token atendido e o kit e a falta de token fechados.
- Conferido em 2026-11-15 com o `claude` real: SessionStart, /clear (SessionEnd e o id novo), o
  servidor desligado no meio (o Claude não esperou) e de volta com o mesmo token, SessionEnd no /exit.
