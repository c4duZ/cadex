# session-kit (app macOS)

## O que eu quero
- A única peça que monta o que uma sessão do Claude Code aberta pelo Cadex recebe: `--settings`,
  `--plugin-dir`, `--mcp-config` e o ambiente da aba
  (`../../../../docs/adr/0021-cadex-managed-accounts.md`, plano 18 fase B).
- Fica em shared antes de ter dois usuários porque os planos 19 a 24 (worktrees, review, memória,
  orquestração) acrescentam itens a ela pela porta de contribuição; hoje a usam agents,
  agent-tools, review e memory (`../../features/memory/`).

## O que eu não quero
- Escrever na configuração de conta nenhuma (.claude.json, settings.json): o kit só passa
  argumentos e arquivos próprios.
- Token, login ou credencial.
- Feature importando outra para contribuir: cada uma chama `contribute` pelo app.

## Como eu quero
- `SessionKit.swift`: SessionKit.shared; `claudeCommand` (com `cwd:`, a pasta da sessão quando quem
  abre sabe; com `session:`, retoma uma sessão do kit e
  o token dela, para o agente hibernado voltar conhecido pelo app; os argumentos de cada sessão ficam
  ao lado do token, `arguments(of:)`, para ele voltar com o mesmo comando) devolve o comando digitado no terminal
  (`[env -u …] [CLAUDE_CONFIG_DIR=…] claude --settings … [--plugin-dir …] [--mcp-config …] args`),
  escrevendo antes os arquivos. O ambiente perde CLAUDECODE e CLAUDE_CODE_* herdados (um
  CLAUDE_CODE_CHILD_SESSION herdado desligou o transcript, 2026-11-14) e, na conta padrão, um
  CLAUDE_CONFIG_DIR solto. `contribute`/`withdraw` com um `SessionKitPart`. `findTools` acha o `cadex`
  em Contents/Helpers ou, no `make run`, em `core/zig-out/bin`. `accountKey` é a regra do nome do
  arquivo de uso, igual à do `cadex statusline`. `sessionEnvironment` (plano 24, fase B): variáveis
  só daquela sessão, na `env` do `--settings` (o CADEX_DISPATCH_ID de um despacho da
  orchestration), nunca digitadas; os nomes do kit vencem as delas.
- `SessionKitLaunch.swift` (plano 22, fase C): `launch` devolve o kit em pedaços (`SessionKitLaunch`:
  a sessão, os nomes a tirar do ambiente, a pasta primeira no PATH e `--settings`/`--plugin-dir`/
  `--mcp-config`); `claudeCommand` é esses pedaços compostos. `typedLaunch` é o kit do `claude`
  digitado numa aba (`cadex claude`), na conta da aba: o `--settings` do dono (arquivo, relativo à
  pasta da aba, ou JSON) entra no arquivo do kit por `mergeOwner` (vale o do dono, menos a
  `statusLine`; `hooks` somados por evento, os do kit primeiro; no `env`, os `CADEX_*` do kit
  ficam); recusa o arquivo do próprio kit (o comando que o Cadex digita passa pela mesma função) e
  o que não lê.
- `SessionKitFiles.swift`: em `~/Library/Application Support/Cadex/kit` (CADEX_KIT_DIR numa
  instância de teste, plano 24), um `session-<chave>.json`
  por sessão (0600, apagado depois de 2 dias) com a status line do Cadex (a linha do painel, plano 28 fase C)
  e o tema "-ansi" do Claude quando o app o pede (`claudeTheme`, escuro ou claro pelo tema do Cadex), o token da sessão na `env` (que chega aos hooks, teste de 2026-11-15; nunca digitado no
  terminal), os hooks do plano 19 (`cadex hook <evento>` em SessionStart, Stop, Notification,
  PermissionRequest, SessionEnd e CwdChanged, com `hooksEnabled` = agents.stateHooks) e o que as
  features contribuem; o token também num arquivo `…/Cadex/sessions/<chave>.token` (0600, 30 dias),
  que o socket do app lê (objetos se
  juntam, listas se somam: hooks de duas features no mesmo evento rodam os dois; os hooks
  contribuídos ficam com agents.stateHooks desligada, que só vale para os do kit; o `perAccount` de
  uma parte recebe a pasta da conta da sessão e junta o que devolve, como a workspace da memória por
  conta; o `perSession` recebe a conta e a pasta da sessão, só quando ela é conhecida, como a pasta
  da memória automática do Claude por projeto); e, para contas que
  não são a padrão, `mcp-<conta>.json` (0600) com os `mcpServers` do .claude.json da conta padrão,
  lidos sem escrever.
- `CLAUDE_CODE_FORCE_SYNC_OUTPUT=1` na `env` do `--settings` (`synchronizedOutput`): o terminal respeita
  o modo DEC 2026 (plano 19, fase E) e, com ele, o Claude Code manda cada redesenho num bloco
  (testado em 2026-11-15). Com agentTools.enabled (`agentToolsOnPath`), a pasta do `cadex` vai primeiro no `PATH` do
  comando, e o app contribui com o `cadex mcp` e o plugin de skills (plano 20). Sem `preferredNotifChannel`: os avisos
  de agente já vêm pelos hooks e pelo 7501, e o terminal mostra o OSC 777 de qualquer programa (o
  dono, 2026-11-15). O `cadex` no PATH da aba
  entra com o primeiro subcomando que o agente usa (plano 20).

## Como validar
- `make macos-test` (SessionKitTests): comando por conta, ambiente limpo, status line do Cadex, o
  tema pedido, MCP só para as outras contas e com 0600, contribuições somadas (com agents.stateHooks desligada
  também) e por conta, aspas só quando precisa; os pedaços iguais ao comando composto, o
  `--settings` do dono juntado num arquivo só e as recusas; o `perSession` com a pasta da sessão
  (aberta pelo Cadex ou o `claude` digitado) e sem nada quando ela não é conhecida; a variável de
  uma sessão só nela, fora do comando, e sem trocar o token do kit.
