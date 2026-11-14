# Plano 22 — Memória: o AI Memory dentro do Cadex

Depende de: plano 20 (servidor MCP e skills do Cadex), plano 19 (app.sock, `cadex hook`,
worktrees) e plano 18 (kit da sessão, contas, histórico e o índice de texto compartilhado); não
depende do 21: os hooks que a memória usa ela mesma contribui ao kit · Features: memory (nova),
agents, agent-tools, markdown, git-history, explorer, sidebar, settings, command-palette ·
Decisões: ADR 0028 e ADR 0029 (a escrever na fase A), `docs/adr/0004-clean-rewrite.md`,
`docs/adr/0005-every-action-is-a-command.md`, `docs/adr/0007-one-step-install.md`,
`docs/adr/0019-agents-observe-only.md` e as ADRs 0021 a 0027 dos planos 18 a 21.

## O que eu quero
- O projeto lembra: decisões, armadilhas, conceitos e o que cada sessão fez passam de uma sessão
  para a próxima, de uma conta para outra e do Claude para o Codex. É o que o Orca não tem e o
  akitaonrails/ai-memory tem (o dono, 2026-11-14: "Orca + Cadex + AI Memory").
- A memória organizada com IA de verdade, sem colocar token em lugar nenhum: quem pensa é o Claude
  do próprio usuário, na sessão aberta ou numa sessão nova pelo CLI na mesma conta (o dono,
  2026-11-14: "ele abriu uma sessão nova pelo CLI").
- Ver e editar a memória no Cadex como Markdown, com o histórico do git, e saber de onde cada
  memória veio: a sessão e o momento em que nasceu.
- Ver exatamente o que o agente vai receber ao começar uma sessão (o briefing).
- Uma memória para todas as contas do mesmo projeto, quando o dono quiser; separada, quando as
  contas forem de clientes diferentes.
- Leve: cada parte desligável, e desligada custa zero.

## O que eu não quero
- Código do ai-memory copiado ou traduzido. O dono pediu "pegar o repo do Fábio Akita e trazer para
  cá"; isso bate na ADR 0004 (só comportamento) e o repositório é Rust, o Cadex é Zig e Swift. Ou
  o Cadex usa o ai-memory instalado como programa à parte, ou refaz o comportamento descrito na doc
  dele, ou uma ADR abre exceção explícita, como a auditoria do ai-usagebar no plano 17. A fase A
  decide.
- O Cadex chamando modelo, guardando chave de API ou usando o token da assinatura. O provedor
  `anthropic-oauth` do ai-memory usa o token do `claude setup-token`, e a própria doc dele o chama
  de "unofficial and against Anthropic's usage policies": fora.
- Proxy, endpoint falso "compatível com OpenAI" na frente do `claude -p` ou qualquer coisa que
  transforme a assinatura numa API: a Usage Policy de 2026-11-12 proíbe "route requests through
  consumer subscriptions".
- Escrever no `~/.claude` do dono: hooks, MCP, skills e `autoMemoryDirectory` chegam por
  `--settings`, `--mcp-config` e `--plugin-dir` das sessões que o Cadex abre (ADR 0021). O
  `ai-memory install-hooks` não roda na conta do dono.
- Ordens no briefing: contexto injetado entra como lembrete do sistema e fica no transcript; texto
  imperativo pode disparar a defesa contra injeção. Fatos, não ordens.
- Editar transcript no lugar ou montar histórico à mão para o `--resume`: a cadeia `parentUuid` é
  frágil e o resume perde mensagens em silêncio.
- Consolidar a cada turno: gasta o plano. Só em marcos.
- Ação só em botão ou menu: cada uma é um comando com id (ADR 0005).

## Como eu quero
**Fases:**
- **A. Decisão, ADRs e spec.**
  - ADR 0028 (docs/adr/0028-project-memory.md, a criar): a memória do projeto e de onde ela vem.
    Registra as três saídas e a escolha do dono:
    - **A — ai-memory instalado:** o Cadex acha o binário e o serviço dele (`127.0.0.1:49374`),
      põe os hooks e o MCP dele no `--settings` e no `--mcp-config` das sessões do Cadex e mostra a
      wiki dele (`~/Library/Application Support/ai-memory/wiki`). Rápido; é dependência, contra a
      ADR 0007, então fica opcional: sem ele instalado, a página explica e nada pesa.
    - **B — nativo:** o comportamento descrito na doc dele refeito no Cadex (fases C a F abaixo).
    - **Exceção:** traduzir o código, só com ADR explícita do dono.
    Recomendação: A primeiro, para aprender o que importa no uso; B depois, com o que ficou.
    Revê também a ADR 0023 (plano 19), que só deixa o Cadex falar com o agente para responder
    permissão com clique do dono: a consolidação na sessão (fase E) manda o agente consolidar por
    um Stop com `block`, sem clique, nos marcos que o dono ligou em memory.consolidateInSession.
    Reescreve a linha do `CLAUDE.md` da raiz "IA embutida no app" para: "O Cadex não roda modelo
    nem guarda chave: quando a memória precisa de IA, quem pensa é o Claude Code do usuário, na
    sessão ou numa sessão nova pelo CLI na mesma conta".
  - ADR 0029 (docs/adr/0029-memory-agent.md, a criar): o agente de memória de fundo, um
    `claude -p` novo na conta, desligado por padrão (fase F). Revê a ADR 0019 ("não inicia
    agente") e a linha "launcher de agentes" do `CLAUDE.md` da raiz **só para o agente de memória**
    (a ADR 0033 do plano 24 generaliza depois). E fixa, uma vez, a posição sobre os termos, que a
    ADR 0033 cita: uso automatizado da assinatura, sem o dono disparando, é zona cinzenta pelos
    Consumer Terms §3(7) ("automated or non-human means" fora de chave de API ou permissão
    explícita); por isso vem desligado, com teto de gasto, e o Cadex sugere chave de API
    (`apiKeyHelper`) como alternativa.
  - Mapa das fases por caminho: B só no caminho A; C e D só no caminho B; E, F e G nos dois (no
    A, a página G mostra a wiki do ai-memory e o agente F escreve nela pelas ferramentas dele).
  - Spec docs/spec/memory.md (a criar): pastas, briefing, página, chaves, estados; termos
    "Memória do projeto", "Briefing", "Handoff", "Consolidação" e "Agente de memória" no
    `docs/CONTEXT.md`.
- **B. Caminho A: ai-memory ao lado (se o dono escolher A).**
  - Achar o `ai-memory` no PATH e o status do serviço (`ai-memory status --json`); ponto verde,
    amarelo ou vermelho na página Memory.
  - Descobrir, pela doc e por uma pasta de conta descartável (comportamento, nunca código), os
    comandos de hook e a entrada MCP que o `install-hooks` e o `install-mcp --session-aware`
    gerariam, e passá-los no `--settings` e no `--mcp-config` das sessões do Cadex.
  - A wiki dele aberta nas features `markdown` e `git-history`; a API só de leitura `/api/v1`
    (busca, sessões, handoffs) com o token local dele, só se precisar.
  - Configuração memory.provider (`none`, `ai-memory`, `cadex`). Features: memory, agents,
    markdown, git-history.
- **C. Memória nativa: pastas, captura e índice (caminho B).** Feature nova `memory`, só app macOS
  por enquanto (apps/macos/features/memory/, a criar, com `CLAUDE.md`, testes e linha na tabela
  da raiz); desce para o núcleo quando o Windows precisar, como a ADR 0019 fez com as leituras.
  - Pasta por projeto: `~/Library/Application Support/Cadex/memory/<repo>/` (a criar) com wiki/
    em git (decisions/, gotchas/, concepts/, sessions/, handoffs/, _rules/), auto/ e
    raw/events.jsonl.
  - `autoMemoryDirectory` de cada conta aponta para auto/ pelo kit da sessão (plano 18): o Claude
    continua escrevendo o MEMORY.md dele lá (200 linhas ou 25 KB entram em cada sessão), e o
    Cadex indexa e versiona. memory.shareAcrossAccounts (ligada): desligada, cada conta tem a sua
    auto/. Testado em 2026-11-14 (2.1.325): o `autoMemoryDirectory` pelo `--settings` funciona, a
    memória salva numa sessão volta numa sessão nova, e o Claude grava `originSessionId` em cada
    memória (a ligação memória → sessão vem pronta). A memória automática é uma por repositório,
    a mesma para as worktrees dele.
  - **O Cadex é dono do índice MEMORY.md.** No mesmo teste, 4 sessões simultâneas (2 contas)
    salvaram 4 memórias: os 4 arquivos de tópico existem, mas o MEMORY.md ficou com 1 entrada (a
    última gravação venceu). Acontece com o próprio Claude Code sempre que duas sessões do mesmo
    repositório salvam juntas; compartilhar entre contas só aumenta a chance. Depois de cada
    gravação na pasta (o vigia de auto/), o Cadex reconstrói o MEMORY.md a partir dos arquivos de
    tópico (frontmatter `name`/`description`), dentro do limite de 200 linhas / 25 KB, sem apagar
    entrada escrita à mão.
  - Captura sem IA: a feature memory contribui ao kit da sessão os hooks que ela precisa e que os
    planos 19 e 21 não garantem (UserPromptSubmit, SubagentStop, PreCompact, PostCompact com
    `compact_summary`, e PostToolUse mesmo com review.authorship desligado); Stop e SessionEnd já
    vêm do plano 19. Todos pelo `cadex hook` ao app.sock; o comando grava numa fila local e nunca
    espera o app.
  - Índice pela peça compartilhada do plano 18 (apps/macos/shared/text-index/, a criar: SQLite do
    sistema com FTS5), num banco próprio da memória, reconstruível a partir da wiki. No SessionEnd,
    página `sessions/<id>.md` por regras (sem modelo) e handoff aberto.
  - Configuração memory.enabled (desligada até o dono ligar). Features: memory, agents, settings.
- **D. Briefing e ferramentas (caminho B).**
  - SessionStart (fontes startup, resume, clear, compact, fork): `additionalContext` de até 10 mil
    caracteres com o handoff aberto, as páginas fixadas e _rules/, decisões e armadilhas recentes,
    em frases de fato. UserPromptSubmit: no máximo 3 trechos achados pela busca. SubagentStart: um
    resumo menor. PreCompact: checkpoint em sessions/, que volta no SessionStart `compact`.
    Testado em 2026-11-14 com `/compact`: o texto que o PreCompact imprime entra no resumo (o
    PostCompact recebeu o `compact_summary` com ele) e `exit 2` cancela a compactação (sem
    `compact_boundary`, PostCompact não roda, o motivo volta ao usuário). Falta conferir com a
    compactação automática (`trigger: auto`) antes do rollover.
  - No servidor MCP do Cadex (`cadex mcp`, plano 20): `memory_search`, `memory_read`,
    `memory_write`, `memory_handoff_begin`, `memory_handoff_claim`, `memory_session_events`
    (o que foi capturado de uma sessão). Escrever só dentro da pasta do projeto.
  - Skill `cadex-memory` no plugin do kit (plano 20): quando buscar, quando salvar uma decisão,
    quando abrir um handoff, como consolidar. É o "agente" do ai-memory: o Claude seguindo skill e
    ferramentas.
  - Handoff entre agentes: Claude ↔ Codex pela mesma pasta, com AGENTS.md como contrato comum (o
    Claude lê nativamente desde a v2.1.277).
  - Features: memory, agent-tools.
- **E. Consolidação na sessão, sem token.**
  - Hook Stop com `decision: "block"` só em marcos: worktree marcada como pronta (plano 19),
    contexto acima de memory.consolidateAtContext (70%, lido do `context_window` que o
    `cadex statusline` do plano 18 grava por sessão) ou fim de tarefa pedido pelo dono. O motivo
    diz "consolide esta sessão na memória" e o próprio Claude escreve as páginas com o contexto que
    já tem (mais barato e melhor que reler o transcript). No máximo uma vez por marco.
  - Comando memory.consolidate-now (manda a mesma mensagem por bracketed paste sem Enter, como no
    plano 21). Configuração memory.consolidateInSession (ligada com memory.enabled).
- **F. Agente de memória de fundo (ADR 0029).**
  - Primeiro, a prova num script fora do app: `CLAUDE_CONFIG_DIR=<conta> claude -p` com o login da
    conta, `--model` barato, `--max-budget-usd`, `--no-session-persistence`, `--mcp-config` só com
    as ferramentas de memória e `--allowedTools` limitado, com o ambiente limpo pelo kit. Já visto
    em 2026-11-14 (Claude Code 2.1.325): `claude -p` com `CLAUDE_CONFIG_DIR` de uma conta usou o
    login da assinatura dela (o `--bare`, que não usa esse login, ainda não é o padrão do `-p`) e
    custou menos de US$ 0,01 por chamada curta no haiku. A prova confere de novo na versão do dia,
    mede o custo de um trabalho real e vê se há bloqueio por impressão digital (issue #46262). Sem
    a prova passando, a fase para.
  - Os trabalhos, nos gatilhos do ai-memory: consolidação (sessão parada ou depois da compactação),
    auto-improve (propõe regras e armadilhas; vão para aprovação do dono, memory.requireApproval
    ligada), experience (a cada N sessões), dream (computador parado; para quando o dono volta),
    profile e bootstrap (manual, lê o histórico do plano 18).
  - Fila no app, um trabalho por vez, teto de gasto por dia (memory.dailyBudgetUsd); tudo registrado
    com custo. Configuração memory.backgroundAgent (desligada). Comandos memory.run-dream,
    memory.bootstrap, memory.pause-agent.
- **G. Página Memory.** Página da barra lateral (ícone Phosphor):
  - A wiki em árvore, aberta e editada como Markdown; histórico pelo `git-history`.
  - Cada página com a origem: sessão, conta e hora, com "Abrir a sessão" (plano 18).
  - "O que o agente vai ver": o briefing exato da próxima sessão neste projeto.
  - Fila do agente de memória com custo; propostas para aprovar ou recusar.
  - Comandos memory.show (página), memory.show-briefing, memory.approve, memory.reject,
    memory.reindex. Features: memory, sidebar, markdown, git-history.
- **H. Peso e fechamento.** Cenários no `tools/perf/run.py`: desligado igual ao de hoje (nada
  vigiado, nenhum hook a mais no `--settings`); ligado com uma wiki de 2 mil páginas e uma sessão
  falsa mandando 500 eventos. Os ids novos em `MAC_ONLY` de `tools/check_command_parity.py`.
  `CLAUDE.md` das features tocadas, README e notas da release em inglês.

## Como validar
- `make check` a cada fase; `make perf` nas fases C a H: desligado, os números de hoje; ligado e
  parado, sem CPU a mais.
- Fase A: ADRs 0028 e 0029 citam o que revêem (0007 no caminho A, a linha "IA embutida" da raiz,
  a 0023 na consolidação sem clique, a 0019 e a linha "launcher de agentes" só para o agente de
  memória, e a posição única sobre os termos); o mapa das fases por caminho;
  spec com critérios; `make manifests`.
- Fase B: com o ai-memory instalado, uma sessão aberta pelo Cadex recebe o briefing dele e grava
  no serviço; sem ele, a página explica e nada pesa; o `~/.claude` do dono não muda.
- Fase C: numa sessão do Cadex, prompts e edições aparecem em raw/ e o MEMORY.md do Claude cai
  em auto/; apagar o índice e reconstruir dá o mesmo resultado; com shareAcrossAccounts
  desligada, duas contas não se veem; 4 sessões simultâneas salvando memória deixam o MEMORY.md
  com as 4 entradas (no teste de 2026-11-14, sem o Cadex, ficou 1).
- Fase D: o briefing nunca passa de 10 mil caracteres e não tem frase imperativa; uma decisão
  salva numa sessão aparece no briefing da seguinte; o Codex numa aba pega o handoff do Claude.
- Fase E: marcar a worktree como pronta faz o Claude escrever as páginas uma vez, sem chave
  configurada em lugar nenhum.
- Fase F: a prova registrada com custo e versão; desligado, nenhum `claude -p` roda (`ps`);
  ligado, o dream para quando o dono mexe no teclado; o teto diário é respeitado.
- Fase G: editar uma página na Memory gera commit; "Abrir a sessão" leva à conversa certa; o
  briefing mostrado é igual ao que a sessão recebeu (conferido no transcript).
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`).
