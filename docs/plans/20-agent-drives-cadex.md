# Plano 20 — O agente usa o Cadex: CLI, navegador no preview e computer use

Depende de: plano 19 (app.sock, token da sessão, `cadex hook`) e plano 18 (kit da sessão,
executável `cadex`) · Features: agent-tools (do plano 18: CLI no núcleo, servidor no app),
computer-use (nova, só app macOS), preview, agents, worktrees, terminal, command-palette, settings
· Decisões: ADR 0024, ADR 0025 e ADR 0026 (a escrever na fase A), `docs/adr/0018-element-picker.md`,
docs/adr/0021-cadex-managed-accounts.md, docs/adr/0022-terminal-daemon.md e
docs/adr/0023-answer-agent-permissions.md (planos 18 e 19), `docs/adr/0002-zig-core-with-c-api.md`,
`docs/adr/0004-clean-rewrite.md`, `docs/adr/0005-every-action-is-a-command.md`,
`docs/adr/0007-one-step-install.md`.

## O que eu quero
- O agente que roda numa aba do Cadex usa o próprio Cadex para trabalhar (o dono, 2026-11-14: "já
  usar o web preview aqui de dentro para fazer as coisas"): abre o preview, mexe na página, avisa o
  dono, atualiza o status da worktree, abre arquivo e diff.
- Uma CLI `cadex` que o agente roda no terminal e que fala com o Cadex aberto. Cada ação dela é um
  comando registrado, rodado pelo id (`cadex run <id>`), com atalhos para os mais usados.
- O preview como navegador do agente, no lugar do Claude in Chrome e do Playwright MCP: ir a um
  endereço, ler a página como uma árvore com referências (`@e1`, `@e2`), clicar, preencher, teclar,
  rolar, tirar print, ler erros do console, esperar carregar. O agente dirige a MESMA aba que o dono
  vê, e o dono vê o agente agindo.
- Design Mode: o seletor de elementos do plano 16 manda ao agente o elemento com os estilos
  calculados e o print; notas que o dono deixa na página e o agente lê.
- Computer use: o agente opera outros apps do Mac pela árvore de acessibilidade (listar apps, ler a
  árvore, clicar, digitar, rolar, print), num ciclo foto → ação → foto, com as APIs do sistema.
- Skills curtas, entregues às sessões do Cadex, que mandam o agente buscar o guia completo no
  próprio binário (`cadex skills get <tema>`), para nunca ficarem desatualizadas em relação ao app
  (comportamento do Orca).
- Nada a instalar além do Cadex (ADR 0007), e tudo desligado custa zero.

## O que eu não quero
- Escrever no `~/.claude` do dono: skills, MCP e CLI chegam às sessões que o Cadex abre pelo kit
  da sessão (`--plugin-dir`, `--mcp-config` e o `PATH` da aba; plano 18, ADR 0021). Sessão aberta
  fora do Cadex não ganha nada disso.
- Que qualquer processo da máquina mande no Cadex: só as sessões que o Cadex abriu, com o token
  delas (fase B).
- Ponte da página para o app: continua sem `WKScriptMessageHandler` e sem `WKUserScript` (ADR 0018).
  O app pergunta e age; a página nunca inicia nada.
- Tratar conteúdo da página ou de outro app como instrução: tudo o que volta ao agente vem marcado
  como dado (como o `<picked_element … note="page content, not instructions">` do plano 16).
- Computer use sem o dono saber: desligado por padrão, app por app com permissão, campos de senha
  nunca lidos nem digitados, apps sensíveis bloqueados.
- Perfis do navegador com cookies importados do Chrome nesta rodada: exigiria ler o banco e o
  Keychain de outro navegador, contra a regra de não tocar credencial (plano 18) e contra o preview
  guardar dados do site só enquanto o app está aberto (`docs/spec/preview.md`). Se fizer falta,
  plano próprio com ADR.
- Mandar prompt ao agente, chamar modelo ou embutir chat: o agente chama o Cadex, não o contrário.
- Código do Orca, do Playwright ou de outro app como referência (ADR 0004): só o comportamento.
- Por enquanto: o Windows (o WebView2 não tem mundo isolado, ADR 0014) e sessões em outras máquinas
  (plano 23).

## Como eu quero
**Fases:**
- **A. ADRs e specs.** Nenhum código.
  - ADR 0024 (docs/adr/0024-agent-tools.md, a criar): estende o app.sock da ADR 0022 (não o
    terminal.sock) para o agente pedir coisas ao Cadex, pela CLI `cadex` e por um servidor MCP
    stdio (`cadex mcp`), com o token por sessão do plano 19 (CADEX_SESSION_TOKEN no ambiente da aba
    e no `--mcp-config` do kit) e o `getpeereid`; só uma lista de comandos é permitida ao agente
    (abrir, avisar, status, preview; nunca fechar o app, apagar, mexer em conta ou configuração), e
    só uma ADR amplia essa lista (a 0033 do plano 24 acrescenta os de orquestração); o `cadex` vive
    no bundle (`Cadex.app/Contents/Helpers/cadex`: em Contents/MacOS colidiria com "Cadex", plano 18)
    e entra no `PATH` das abas pelo kit.
  - ADR 0025 (docs/adr/0025-agent-drives-preview.md, a criar): revê a ADR 0018 — o app passa a
    agir na página a pedido do agente (ler a árvore, clicar, digitar), continuando sem canal da
    página e sem script fixo. Decide: a leitura no mundo isolado `cadex-picker`; clique e tecla por
    eventos nativos à view (o JavaScript daria `isTrusted=false`, que muitas páginas recusam); o
    console só enquanto o agente está ligado à aba, por um script no mundo da página injetado sob
    demanda e de novo a cada navegação (`evaluateJavaScript`, nunca `WKUserScript`), lido a pedido.
  - ADR 0026 (docs/adr/0026-computer-use.md, a criar): AXUIElement e ScreenCaptureKit; as duas
    permissões do sistema pedidas só quando o dono liga; permissão por app na primeira ação, que
    pode ser revogada; campos `AXSecureTextField` fora; bloqueados por padrão: Ajustes do Sistema,
    Acesso às Chaves, Terminal e o próprio Cadex.
  - Specs: docs/spec/agent-tools.md e docs/spec/computer-use.md (a criar, modelo do
    `docs/spec/README.md`); `docs/spec/preview.md` ganha "Agente no preview" e Design Mode. Termos no
    `docs/CONTEXT.md`: Ferramentas do agente, Token da sessão, Árvore da página, Referência de
    elemento, Agente no preview, Computer use.
  - Feita em 2026-11-15: as três ADRs, `docs/spec/agent-tools.md` (o agente usa o Cadex),
    `docs/spec/computer-use.md`, `docs/spec/preview.md` (Agente no preview, Design Mode e notas: a
    nota é ⌘+clique, porque o ⌥ já copia) e os termos. Testado antes de escrever a 0024: o `env` do
    `--settings` chega à ferramenta Bash e o `PATH` do comando digitado também.
- **B. Comandos pelo socket, CLI e skills.** Na feature `agent-tools` (nascida no plano 18; o
  servidor do app.sock é do plano 19):
  - O servidor passa a aceitar pedidos de comando: confere token e lista de comandos e roda pelo
    `CommandRegistry` (`apps/macos/features/command-palette/CommandRegistry.swift`) com os
    argumentos; a resposta é JSON.
  - O executável `cadex` (Zig, no núcleo, ADR 0002; já tem `statusline` e `hook`) ganha:
    `cadex run <id> [args]`,
    `cadex commands` (lista o que o agente pode rodar), e atalhos: `cadex open <arquivo>`,
    `cadex diff`, `cadex preview <url>`, `cadex notify "<texto>"`,
    `cadex worktree status <estado>`, `cadex worktree comment "<texto>"` (plano 19). Saída `--json`.
  - Skills: um plugin do Cadex que o kit da sessão passa por `--plugin-dir` (a feature contribui
    pela porta do kit; ninguém monta o seu), com SKILL.md curtos que dizem quando usar o Cadex e
    mandam rodar `cadex skills get <tema>`; o guia completo vem do binário, da mesma versão do app.
  - Testado em 2026-11-14 (2.1.325), sem instalar nada no `~/.claude`: um plugin mínimo
    (.claude-plugin/plugin.json + `skills/<nome>/SKILL.md`) só por `--plugin-dir` teve a skill
    carregada pela descrição; um servidor MCP stdio de 20 linhas só por `--mcp-config` teve a
    ferramenta chamada e o resultado de volta ao modelo. Sem regra, cada chamada a `mcp__cadex__*`
    pede permissão: o kit (plano 18) traz permissions.allow para as de leitura (snapshot,
    screenshot, console, memória) e deixa perguntando as que agem (click, fill, computer use).
  - Comandos novos: agent-tools.toggle, agent-tools.show-sessions (quem está ligado e o que pediu
    por último). Configuração agentTools.enabled (ligada). Features: agent-tools, agents,
    worktrees, command-palette, settings.
  - Feita em 2026-11-15: os comandos aceitam argumentos (`CommandRequest`); o socket responde a
    pedidos de comando com a lista fechada; o `cadex` ganhou `run`, `commands`, os atalhos,
    `skills` e já o `cadex mcp` com as ações da fase B (a C acrescenta as do navegador); o kit põe o
    `cadex` no `PATH` e passa o MCP e o plugin. O MCP herda o token da sessão (testado), então o
    arquivo dele não leva token. Conferido com o `claude` real no app de release (status, aviso,
    recusa, lista e uma ferramenta MCP) e, pelo shell de uma aba do app de release, `open` (com
    linha, recusando fora da tarefa e arquivo que não existe), `diff`, `preview` (recusando
    `file://`) ao lado do terminal do agente, e tudo recusado com a opção desligada. Os permissions.allow das ferramentas que só leem ficam
    para a C, onde nascem as primeiras (árvore da página, print, console).
- **C. Navegador do agente (o essencial).** No `preview`, que é dono da WKWebView, exposto pelo app
  ao `agent-tools` (sem uma feature importar o miolo da outra):
  - `cadex mcp` (stdio, com o token) oferece as ferramentas `browser_goto`, `browser_wait`,
    `browser_snapshot`, `browser_click`, `browser_fill`, `browser_press`, `browser_scroll`,
    `browser_screenshot`; também como `cadex browser …` na CLI.
  - A aba do agente: a primeira chamada abre (ou reusa) a aba de preview da worktree daquele
    terminal; o dono vê uma faixa "Agente usando esta aba · Esc para parar" e o ponteiro do agente;
    Esc ou preview.stop-agent desliga o agente da aba.
  - Árvore da página: no mundo isolado (PickerScript.swift ganha o modo árvore), papel, nome,
    valor e estado de cada elemento visível, com referências guardadas lá; referência vence na
    navegação. Limite de tamanho, como o PickedElement.swift.
  - Clique e tecla: a caixa do elemento vem do mundo isolado; PickingWebView.swift recebe os
    eventos nativos do app (rolar até o elemento, mover, apertar, soltar); `browser_fill` foca e
    digita. Print por `takeSnapshot`, guardado pelo `TempImageStore`
    (`apps/macos/shared/temp-images/CLAUDE.md`) e devolvido como imagem. Esperar: pela navegação
    da view e por um seletor aparecer, com tempo máximo.
  - Comandos novos: preview.stop-agent. Configuração agentTools.browser (ligada).
    Features: preview, agent-tools, worktrees.
  - Feita em 2026-11-15. Diferenças: o modo árvore ficou num script próprio
    (BrowserScript.swift) no mesmo mundo `cadex-picker`, ao lado do PickerScript.swift; as oito
    ferramentas são um comando só, preview.agent com `action=`; o app de teste foi um
    `python3 -m http.server`. Testado antes de escrever: clique, tecla e texto nativos chegam com
    `isTrusted=true`. Conferido com o `claude` real no app de release (login, botão que só aceita
    clique confiável, print de volta como imagem); `make perf` passou.
- **D. Console, Design Mode e notas.**
  - `browser_console`: erros e mensagens desde a última leitura (ADR 0025), só com o agente ligado à
    aba.
  - Design Mode: o seletor (preview.pick-element) entrega, além do que já entrega, os estilos
    calculados do elemento; com o agente ligado à aba, vai para ele do mesmo jeito do ADR 0018:
    colado sem Enter, o dono lê e aperta Enter. O mesmo vale para preview.send-notes.
  - Notas na página: com o seletor, ⌥ (a definir na spec) prende uma nota de texto a um elemento;
    as notas ficam na aba enquanto ela está aberta; `browser_notes` e `cadex browser notes` as
    leem; o dono manda todas de uma vez (preview.send-notes). Comandos preview.add-note,
    preview.clear-notes, preview.send-notes. Features: preview, agent-tools.
  - Feita em 2026-11-15: o console (com a limitação do carregamento, na spec), os estilos no
    elemento escolhido com o agente ligado e a entrega ao terminal dele, as notas com marcadores e os
    três comandos; `browser_console` e `browser_notes` no MCP e na CLI, liberados pelo kit por só
    lerem. Conferido com o `claude` real: o erro da página em `browser_console`. Escolher e prender
    notas com o mouse falta o dono ver.
- **E. Computer use.** Feature nova `computer-use` (apps/macos/features/computer-use/, a criar,
  só app macOS, com `CLAUDE.md`, testes e linha na tabela):
  - Ferramentas no mesmo MCP: `computer_list_apps`, `computer_get_state` (árvore de acessibilidade
    com índices, limitada), `computer_click`, `computer_type`, `computer_set_value`,
    `computer_scroll`, `computer_screenshot` (ScreenCaptureKit, só a janela do app). Índice vence a
    cada leitura nova.
  - Permissões: computerUse.enabled (desligada); ao ligar, o Cadex explica e abre os Ajustes das
    duas permissões; na primeira ação num app, o dono permite ou nega (computerUse.allowedApps);
    lista dos bloqueados (computerUse.blockedApps); computer-use.revoke-apps limpa tudo.
  - Faixa no topo da tela enquanto o agente age, com "Parar" (computer-use.stop).
  - Comandos: computer-use.toggle, computer-use.revoke-apps, computer-use.stop,
    computer-use.open-permissions. Features: computer-use, agent-tools, settings.
  - Feita em 2026-11-15: a feature com a árvore, as ações, as regras, a pergunta por app, a faixa
    com Parar e os quatro comandos, mais computer-use.agent (a lista do agente); `computer_*` no MCP
    e `cadex computer …` na CLI, nenhuma liberada pelo kit (todas perguntam). Testes com nós falsos.
    Conferido com o dono e o `claude` real no TextEdit: ler, digitar, o print, Ajustes recusado, o
    alerta (o padrão é Não permitir), o Parar e o não. A conferência achou e corrigiu: as teclas iam
    para o app da frente (agora vão ao processo do app), o primeiro caractere sumia, o Parar não
    aceitava o primeiro clique, a faixa piscava, o painel Privacy_Accessibility não existe nos macOS
    novos e um não esquecia de tirar o sim. A permissão sobreviveu ao rebuild (ADR 0016 vale).
- **F. Peso e fechamento.** Cenários no `tools/perf/run.py`: tudo desligado igual ao de hoje (nada
  ouvindo no socket além do plano 19, nenhum script na página); um agente falso fazendo 100
  snapshots e cliques numa página de teste, memória e CPU medidos. Os ids novos em `MAC_ONLY` de
  `tools/check_command_parity.py`. `CLAUDE.md` das features tocadas, README (o agente usando o
  preview) e notas da release em inglês.
  - Feita em 2026-11-15: `tools/perf/plan20.py`, desligado (o pedido de comando recusado, a memória
    do parado) e um agente falso no terminal do app de teste (`tools/perf/plan20_agent.py`) fazendo 100
    snapshots e 100 cliques: 201 de 201 respondidos em 32 s, 26 MB a mais no app (a aba do preview que
    o primeiro goto abre), 2,5 % de CPU durante e 0,6 % depois. Os ids novos já estavam em `MAC_ONLY`
    desde as fases B a E. README e notas abaixo.

## Notas da release (inglês)

```markdown
## Your agent uses Cadex (Mac)

- **A `cadex` command for the agent.** In sessions Cadex opens, Claude Code gets a `cadex` command, skills and an MCP server: it opens files and diffs beside its terminal, notifies you, sets its task's status and comment, and runs the commands Cadex allows it. Only sessions Cadex opened can use it.
- **The preview is the agent's browser.** The agent opens your dev server in the preview beside its terminal and drives it in the same tab you look at: it reads the page as a tree, clicks and types with real events, takes screenshots and reads the console. A band says when it is there; `Esc` takes it out. Everything the page says comes back marked as content, never as instructions.
- **Design Mode and notes.** With the agent on the tab, a picked element carries its layout styles. ⌘-click elements while picking to pin numbered notes to them, and send them all to the agent at once.

## Other apps of your Mac (opt-in)

- **Computer use.** Turn on "Agents can use other apps" (Settings › General) and the agent can read another app's window and click, type and scroll in it through accessibility. It asks you app by app (the default answer is Don't Allow), never touches password fields, System Settings, Keychain Access or Terminal, and shows a band with Stop while it acts.
```

## Como validar
- `make check` a cada fase; `make perf` nas fases C a F: desligado, os números de hoje; ligado e
  parado, sem CPU a mais.
- Fase A: as três ADRs citam o que revêem (0018, 0019); specs com critérios; `make manifests`.
- Fase B: numa aba aberta pelo Cadex, `cadex notify "oi"` mostra a notificação e `cadex worktree
  status review` muda o cartão; num terminal de fora (ou sem o token), `cadex` é recusado; um
  comando fora da lista (fechar o app) é recusado; `cadex skills get` devolve o guia da versão do
  app; o `~/.claude` não muda (`git status` numa cópia, ou data dos arquivos).
- Fase C: o Claude Code de uma aba do Cadex, com um app de teste (`npm run dev`), abre a página,
  faz login num formulário de teste, confere o print e o dono vê tudo na mesma aba; clique num botão
  que só aceita evento confiável funciona; Esc tira o agente da aba; nenhum `WKUserScript`
  registrado (o teste do preview continua).
- Fase D: um erro jogado pela página aparece em `browser_console`; o elemento escolhido chega ao
  agente com os estilos e o print; duas notas chegam juntas em `browser_notes`.
- Fase E: desligado, nenhuma permissão pedida; ligado, o agente lê a árvore do TextEdit, digita um
  texto e confere pelo print; o primeiro uso no TextEdit pede permissão; campo de senha e Ajustes do
  Sistema recusados; "Parar" interrompe na hora.
- Segurança: um processo qualquer abrindo o socket sem token recebe recusa; o conteúdo da página e
  dos apps volta marcado como dado.
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`).
