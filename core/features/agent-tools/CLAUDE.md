# agent-tools (núcleo)

## O que eu quero
- O programa `cadex` que as sessões de agente abertas pelo Cadex rodam (`../../../docs/spec/agent-tools.md`,
  `../../../docs/adr/0021-cadex-managed-accounts.md`, `../../../docs/adr/0022-terminal-daemon.md`):
  `cadex statusline`, `cadex hook <evento>`, `cadex memory-hook <evento>` e `cadex claude` (plano 22); no plano 20 (`../../../docs/adr/0024-agent-tools.md`), os
  comandos com que o agente usa o Cadex, as skills e o servidor MCP.

## O que eu não quero
- Ler, guardar ou repassar token, login ou credencial do Claude Code; falar com a rede. (O token
  da sessão é do Cadex: vem na env que o kit põe e só vai ao socket do app.)
- Atrapalhar a sessão: erro é engolido; sem o uso gravado, a linha sai do mesmo jeito.
- Quebrar o `claude` digitado: `cadex claude` sem app, recusado ou com qualquer erro roda o `claude`
  de verdade exatamente como foi digitado, e nunca troca a conta que a aba tem (o
  CLAUDE_CONFIG_DIR dela); sem conta na aba, usa a que o app manda no kit (`config_dir`, plano 33 F).
- Depender da libghostty ou do resto do núcleo: só libc, `../../shared/fs.zig`, `../../shared/process.zig`
  e a entrada da feature memory (`../memory/memory.zig`), para o `cadex memory-hook`.

## Como eu quero
- `cli.zig`: o `main` (raiz em `../../cadex_cli.zig`, fora da pasta para poder usar shared/),
  lê a entrada com libc e escolhe o subcomando.
- `claude_wrap.zig`: o pedido de um arquivo de prompt vai depois de "--" (`argvFor`): o kit
  termina com `--mcp-config <arquivo>`, que aceita vários valores, e o Claude Code lia o pedido como
  um segundo arquivo de MCP e saía (achado pela tela de início, 2026-11-17); sem "--" a mais quando
  o dono já tem um.
- `codex_wrap.zig` (plano 29): `cadex codex`, o Codex com o pedido de um arquivo de prompt pelas
  regras do `prompt_file.zig`, depois de "--"; o `codex` de verdade pelo `findReal` do
  `claude_wrap.zig` (genérico pelo nome; CADEX_CODEX_BIN numa instância de teste). Sem kit.
- `statusline.zig`: `files` monta o arquivo da conta (`rate_limits`) e o da sessão (`context_window`,
  `cost`, `model`); `accountKey` dá o nome do arquivo da conta (todo byte que não é letra ou dígito
  ASCII vira "-", a mesma regra do SessionKit.accountKey no app); `run` grava primeiro e depois
  imprime `line`, a linha do painel do mockup (plano 28 fase C: modelo, contexto com barra, custo,
  pasta, em ANSI); a status line da conta não roda mais nas sessões do Cadex.
- `hook.zig`: `cadex hook <evento>` manda ao socket do app uma linha com o token
  (CADEX_SESSION_TOKEN), o evento, o pid do `claude` (o pai do hook) e o JSON reescrito numa linha;
  espera 200 ms (a permissão, 10 min: ADR 0023) e imprime o `stdout` da resposta. App fechado: sai
  na hora. Sempre 0.
- Plano 22, fase C: `cadex memory-hook <evento>` é o hook da memória, separado do `cadex hook` (que
  corta o PostToolUse para a revisão); o `cli.zig` só o despacha para `../memory/memory.zig`, que
  fala com o `cadex-memory` (`../memory/CLAUDE.md`). Sempre 0.
- Plano 20, fase B: `agent.zig` escolhe entre `mcp`, `skills` e os subcomandos que pedem ao app;
  `commands.zig` traduz `run`, `commands` e os atalhos (`open`, `diff`, `preview`, `notify`,
  `worktree status|comment`) em id e argumentos; `request.zig` manda ao socket do app uma linha com o
  token, o id (ou a lista), os argumentos e os pids acima do processo (o app acha o terminal do
  agente), espera até 40 s e lê `{"ok", "result"|"error"}`; `skills.zig` traz os guias de `guides/`
  embutidos no binário (`cadex skills list|get`); `mcp.zig` é o servidor MCP (JSON-RPC por linha:
  initialize, tools/list, tools/call, ping), cada ferramenta um pedido de comando. Saída 0 feito, 1
  recusado ou app fechado (o motivo no stderr), 2 uso.
- Plano 22 fase D: com a memória ligada na sessão (CADEX_MEMORY_DIR no ambiente), o `mcp.zig` junta à
  lista as ferramentas `memory_*` do engine e repassa as chamadas delas inteiras, pela entrada da
  feature memory (`../memory/mcp_proxy.zig`), não pelo app; `agent.zig` ignora o SIGCHLD porque o
  engine que o servidor sobe é filho dele.
- Plano 24, fase D2: o pedido leva o CADEX_DISPATCH_ID da sessão (`"dispatch"`), que o app confere
  contra o despacho do token; `run … spec-file=<arquivo>` lê o arquivo (comum, até 100 KB, sem
  NUL) e manda o texto como `spec=` (orchestration.spawn); o guia `guides/orchestration.md` sai por
  `cadex skills get orchestration`. `cadex claude` executa o CADEX_CLAUDE_BIN quando ele existe: o
  `claude` falso de uma instância de teste (`../../../tools/perf/fake_claude.py`), que o PATH do
  shell da aba nunca troca pelo de verdade.
- Plano 24, fase E (`../../../docs/adr/0034-scheduled-automations.md`): `automations.zig`, `cadex
  automations due`, o programa do LaunchAgent das automações: pede ao app pelo socket que confira a
  agenda (`{"v":1,"due":true}`, sem token); com o app fechado, abre o Cadex em segundo plano
  (CADEX_APP_BUNDLE com `open -g`, ou CADEX_APP_BIN com CADEX_BACKGROUND=1, numa sessão própria) e sai.
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
- Plano 22, fase C: `cadex claude <args…>` é o que a função `claude` da integração do zsh roda
  (`../../../apps/macos/features/terminal/shell-integration/zsh/.zshenv`). `claude_args.zig` decide:
  passam direto `-p`/`--print`, `-v`/`--version`, `-h`/`--help`, `--bg`, `--remote-control`,
  `--cloud`, `--desktop` e todo subcomando (`subcommands`: o `claude --help` do Claude Code 2.1.325
  mais os escondidos achados na prova), achado como a primeira palavra que não é opção, pulando o
  valor das opções que levam valor (`--x=v`, `-abc` e opções variádicas também); o resto é sessão
  interativa, e o último `--settings` do dono sai das palavras. `claude_wrap.zig` pede o kit ao
  socket do app (`{"v":1,"kit":true,"pids","config_dir","cwd","user_settings","args"}`, sem token: o
  app confere a ancestralidade), espera até 3 s, tira do ambiente o que a resposta manda (`unset`),
  põe `path_first` no PATH e executa o primeiro `claude` do PATH que não é o próprio `cadex` com
  `args` do kit antes das palavras do dono. CADEX_CLAUDE_WRAP (o pid) pega um `claude` que chama
  `cadex claude` de novo. `claude_args_check.py` (no `make manifests`) avisa, sem falhar, quando o
  `claude` instalado tem subcomando ou opção com valor que a lista não conhece.
- Plano 24, fase C (`../../../docs/adr/0033-cadex-launches-agents.md`): `prompt_file.zig` tira
  `--cadex-prompt-file <arquivo>` das palavras antes de tudo (as palavras guardadas para relançar
  não levam o prompt), lê o arquivo só se estiver na pasta dos prompts (CADEX_PROMPTS_DIR, senão
  `…/Cadex/orchestration/prompts`), for um arquivo comum deste usuário (aberto com O_NOFOLLOW e
  conferido pelo `fstat`), até 100 KB e sem NUL, apaga e o passa ao `claude` como a última palavra
  do exec (um prompt que começa com "-" ganha um espaço antes). Arquivo que não serve: `cadex
  claude` diz e sai com 127, sem abrir o `claude` sem o prompt.
- Plano 22, fase E: `cadex continue [opções] [agente] [args…]` (`continue_wrap.zig`) é o que o
  "Continue in…" (agents.continue-in-agent) digita numa aba: pede o kit como o `cadex claude`
  (o `kitFor` do `claude_wrap.zig`), lê do arquivo do `--settings` do kit o ambiente da memória (o
  token e os CADEX_MEMORY_*), põe no próprio ambiente e vira o `cadex-memory run` (o `ai-memory run`
  do upstream, `../memory/CLAUDE.md`) com as palavras do dono intactas: o launcher entende as opções
  e escolhe o agente (nenhum: a sessão mais nova). Vão dois conjuntos do kit: `--claude-kit-arg` (as
  palavras do kit) e `--codex-kit-arg` (o servidor MCP da memória por `-c mcp_servers.cadex…`, com o
  token no env dele); o launcher usa só o do agente que roda. Memória desligada (sem
  CADEX_MEMORY_BIN no kit): diz e sai.
- Plano 22, fase G: `cadex memory-agent …` só despacha para a feature memory (`../memory/agent_client.zig`).
- O build (`../../build.zig`, `addCli`) instala `zig-out/bin/cadex` só no Mac; o empacotamento o põe em
  Contents/Helpers.

## Como validar
- `make core-test`: arquivos, nome da conta, a linha do painel (com e sem as partes), JSON quebrado;
  a linha do pedido (com o despacho) e a resposta, os atalhos virando ids, o `spec-file=` lido
  (pasta e arquivo que falta recusados), os guias e o servidor MCP com um app falso;
  as decisões do `cadex claude` (`--model haiku mcp list`, `-p`, `--version`, `claude`, um prompt,
  `--resume abc`, `--settings x.json`), o pedido do kit, a resposta e o app ausente; o
  `--cadex-prompt-file` saindo das palavras nas duas grafias, o prompt inteiro e o arquivo apagado,
  e fora da pasta, link ou nome com ponto recusados e mantidos.
- Na mão, sem o app: `CADEX_APP_SOCKET=/nada PATH=<pasta com um claude falso>:$PATH core/zig-out/bin/cadex claude --model haiku mcp list`.
- Na mão: `echo '<json>' | CLAUDE_CONFIG_DIR=<pasta> CADEX_USAGE_DIR=<pasta> core/zig-out/bin/cadex statusline`.
