# Plano 22 — Memória: o engine do ai-memory dentro do Cadex

Depende de: plano 20 (servidor MCP e skills do Cadex), plano 19 (app.sock, `cadex hook`,
worktrees, daemon do terminal) e plano 18 (kit da sessão, contas, histórico, continuar em outra
conta); não depende do 21 · Features: memory (nova, núcleo e app macOS), agents, agent-tools,
markdown, git-history, explorer, sidebar, settings, command-palette · Decisões: ADR 0028 e ADR 0029
(a escrever na fase A), `docs/adr/0002-zig-core-with-c-api.md` e `docs/adr/0004-clean-rewrite.md`
(revistas pela 0028 só para a memória), `docs/adr/0005-every-action-is-a-command.md`,
`docs/adr/0007-one-step-install.md`, `docs/adr/0019-agents-observe-only.md` e as ADRs 0021 a 0027
dos planos 18 a 21.

## O que eu quero
- O projeto lembra: decisões, armadilhas, conceitos e o que cada sessão fez passam de uma sessão
  para a próxima, de uma conta para outra e do Claude para o Codex. É o que o
  akitaonrails/ai-memory faz (o dono, 2026-11-14: "Orca + Cadex + AI Memory").
- **Usar o código do Fábio, não refazer** (o dono, 2026-11-15): o ai-memory (Rust, MIT) vira o
  engine da memória, num fork adaptado ao Cadex, sem perder nada de desempenho. Quase nativo,
  rodando o código dele.
- **A memória nasce ligada**, com a busca por sentido (embeddings) junto (o dono, 2026-11-15).
- A memória organizada com IA de verdade, sem token em lugar nenhum: quem pensa é o Claude do
  próprio usuário, na sessão aberta ou numa sessão nova pelo CLI na mesma conta.
- Ver e editar a memória no Cadex como Markdown, com o histórico do git, e saber de onde cada
  memória veio: a sessão e o momento em que nasceu.
- Ver exatamente o que o agente vai receber ao começar uma sessão (o briefing).
- Continuar o trabalho em outro agente (o `ai-memory run`): Claude → Codex e de volta, com o que a
  sessão anterior fez, mesmo quando ela caiu ou a cota acabou.
- Uma memória para todas as contas do mesmo projeto, ou separada quando as contas forem de clientes
  diferentes.
- Leve: o app não pesa mais parado; o engine roda num processo próprio que só existe com sessão de
  agente aberta.

## O que eu não quero
- Reescrever o ai-memory em Zig ou Swift, ou traduzir o código: o fork é Rust e fica Rust.
- O engine dentro do app ou dentro do daemon do terminal: um erro nele derrubaria a janela ou todas
  as sessões. Ele roda no processo `cadex-memory`.
- O que o Cadex já faz de outro jeito: o servidor HTTP na porta 49374, a interface web e o console
  de gestão, `install-hooks`, `install-mcp`, `mcp-bridge`, `setup`, `upgrade`, `doctor`, os serviços
  launchd/systemd dele e o suporte aos outros ~13 CLIs (fica Claude e Codex).
- O multiusuário dele: login, senhas, chaves `aim_`, permissões por projeto, painel de admin.
- O Cadex chamando modelo, guardando chave de API ou usando o token da assinatura: saem todos os
  provedores de LLM do fork (`anthropic`, `anthropic-oauth`, `openai`, `openai-oauth`, `codex`,
  `copilot`, `cursor`, `gemini`, `opencode`, `openai-compat`) e os embedders remotos. O
  `anthropic-oauth` a própria doc dele chama de "unofficial and against Anthropic's usage policies".
- Proxy ou endpoint "compatível com OpenAI" na frente do `claude -p`: a Usage Policy de 2026-11-12
  proíbe "route requests through consumer subscriptions".
- Escrever no `~/.claude` (ou no `CODEX_HOME`) do dono: hooks, MCP, skills e `autoMemoryDirectory`
  chegam por `--settings`, `--mcp-config` e `--plugin-dir` das sessões que o Cadex abre (ADR 0021).
- Ordens no briefing: contexto injetado entra como lembrete do sistema; texto imperativo pode
  disparar a defesa contra injeção. Fatos, não ordens.
- Editar transcript no lugar ou montar histórico à mão para o `--resume`. (O dossiê do `run` é
  outra coisa: um Markdown à parte, só de leitura, que some quando a sessão fecha.)
- Consolidar a cada turno: gasta o plano. Só em marcos.
- Tarefa do engine rodando por relógio (o auto-improve e o profile dele rodam de hora em hora):
  aqui, só por evento.
- Ação só em botão ou menu: cada uma é um comando com id (ADR 0005).

## O que já foi medido (2026-11-15, ai-memory 3.4.7, Rust 1.95, Mac Apple Silicon)
Auditoria autorizada pelo dono como exceção à ADR 0004 (registrada na ADR 0028):
- **Código:** ~239 mil linhas de Rust de produção (mais ~250 mil de testes) em 10 crates. Fica
  como está ~31% (store SQLite/FTS5, wiki em git, consolidação, núcleo, embeddings locais); fica com
  adaptação ~27% (hooks, ferramentas MCP, comandos de hook e fila, `run`); sai ~42% (cli/instalador/
  serviço, multiusuário, web, provedores). Os cortes são quase todos crates ou arquivos inteiros que
  não compilamos: o merge com o upstream continua viável.
- **Tamanho:** o binário dele tem 47,5 MB; o mesmo código com `opt-level="z"`, LTO completo e
  `panic="abort"`, 20,0 MB. O nosso, cortado: ~14–16 MB por arquitetura (estimado), ~28–32 MB no
  app universal. O limite do app sobe de 55 para 85 MB (o dono, 2026-11-15).
- **Tempo** (com o servidor HTTP dele no meio): hook `post-tool-use` 18 ms (processo + fila);
  briefing `session-start` ~270 ms; salvar página com embedding e commit ~430 ms pelo CLI.
- **RAM:** servidor parado ~60 MB, 0% de CPU; com o modelo de embeddings carregado ~155 MB, e volta
  a ~60 depois de parado. O modelo (`all-MiniLM-L6-v2`, 87 MB) é baixado na primeira vez.
- **Disco:** 54 páginas (as nossas ADRs e specs) = wiki 1,8 MB + banco 5,3 MB.

## Como eu quero
**Arquitetura:**
- **O fork:** o ai-memory vendorizado em core/features/memory/engine/ (a criar), o mais intacto
  possível, com a versão e o commit de origem anotados; as nossas mudanças só em três pontos (hooks,
  MCP, provedores) e num crate nosso por cima. Código de terceiro, como a libghostty: fora da regra
  das 500 linhas, entra no `NOTICE` com as licenças das dependências.
- **O processo `cadex-memory`:** executável Rust (o crate nosso + os crates mantidos do fork),
  universal, dentro do app. Sobe pelo launchd quando a primeira sessão de agente abre num projeto
  com a memória ligada e sai sozinho quando a última fecha, sem timer parado (como o daemon da
  ADR 0022). Escritor único da wiki e do banco. Um erro nele só para a memória, que sobe de novo.
- **O terceiro socket:** memory.sock na pasta de sockets do Cadex (revê a ADR 0022), com o mesmo
  token por sessão e `getpeereid` do app.sock. Só a feature `memory` do núcleo fala com ele; o
  `cadex hook`, o `cadex mcp` e o app passam por ela.
- **A IA:** o ponto do fork onde o engine chama o "provedor de LLM" ganha uma implementação só, o
  Claude do usuário: na sessão (fase F) ou num `claude -p` de fundo (fase G). Sem nenhum dos dois
  ligados, as tarefas que precisam de modelo não rodam e o resto funciona igual.

**Fases:**
- **A. Decisão, ADRs e spec (sem código).**
  - ADR 0028 (docs/adr/0028-project-memory.md, a criar): o engine é o fork do ai-memory; exceção à
    ADR 0004 só para esse código (MIT, crédito no `NOTICE`); Rust no núcleo só para a feature
    memory (revê a ADR 0002); o processo `cadex-memory` e o memory.sock (revê a 0022); o que sai
    do fork e por quê; o fork acompanha o upstream. Revê também a ADR 0023: a consolidação na sessão
    (fase F) manda o agente consolidar por um Stop com `block`, sem clique, nos marcos ligados em
    memory.consolidateInSession. Reescreve a linha "IA embutida no app" do `CLAUDE.md` da raiz para:
    "O Cadex não roda modelo nem guarda chave: quando a memória precisa de IA, quem pensa é o
    Claude Code do usuário, na sessão ou numa sessão nova pelo CLI na mesma conta".
  - ADR 0029 (docs/adr/0029-memory-agent.md, a criar): o agente de memória de fundo, um
    `claude -p` novo na conta, desligado por padrão (fase G). Revê a ADR 0019 e a linha "launcher de
    agentes" do `CLAUDE.md` da raiz **só para ele** (a ADR 0033 do plano 24 generaliza depois). Fixa
    a posição sobre os termos: uso automatizado da assinatura, sem o dono disparando, é zona cinzenta
    pelos Consumer Terms §3(7); por isso desligado, com teto de gasto, e o Cadex sugere chave de API
    (`apiKeyHelper`) como alternativa.
  - Spec docs/spec/memory.md (a criar): pastas, processo, briefing, página, chaves, estados, o que o
    fork mantém do comportamento do ai-memory. Termos "Memória do projeto", "Briefing", "Handoff",
    "Workstream", "Consolidação" e "Agente de memória" no `docs/CONTEXT.md`.
- **B. O fork e o build.**
  - Vendorizar o ai-memory na versão do dia; o crate nosso (core/features/memory/server/, a criar)
    monta o `cadex-memory` com os crates mantidos: core, store, wiki, consolidate, hooks, mcp, llm
    (só tipos e embeddings locais), workstream. Fora do build: web, cli (o que serve dele, fila e
    `run`, passa para o crate nosso), test-support só nos testes.
  - Perfil de release para tamanho (`opt-level="z"`, LTO completo, `panic="abort"`, sem símbolos),
    com os crates de inferência (candle) em `opt-level=3`.
  - **Como compila** (o dono, 2026-11-15): o `cadex-memory` é mais um executável auxiliar, como o
    `cadex-terminald`; Zig e Rust não se misturam numa compilação (o `cadex` fala com ele pelo
    memory.sock, sem API C entre os dois). Ferramenta: `rustup` com a versão do
    rust-toolchain.toml do fork (1.95) e os alvos `aarch64-apple-darwin` e `x86_64-apple-darwin`;
    só quem desenvolve precisa dela, quem instala recebe o binário no app (ADR 0007 intacta).
    - `make memory` (novo): `cargo build --release --locked` das duas arquiteturas.
    - `make app` e `make run`: o `cadex-memory` em debug, só da arquitetura da máquina.
    - `make check`: `cargo test` dos crates mantidos. A suíte inteira do fork (~250 mil linhas de
      teste) roda ao trazer uma versão nova do upstream; o tempo das duas medido nesta fase decide
      o que fica no `make check`.
    - `make package` (`apps/macos/packaging/build.sh`): o mesmo do `cadex-terminald`, `lipo` das
      duas fatias em `Contents/Helpers/cadex-memory`, `strip`, `codesign` e um teste rápido de cada
      fatia.
  - Dependências pelo Cargo.lock do fork (`--locked`), baixadas do crates.io no primeiro build e
    guardadas no cache do `~/.cargo`, não copiadas para o repositório (centenas de MB). Licenças
    conferidas pelo `cargo deny` com o deny.toml do fork, e o resultado vai para o `NOTICE`.
  - Tempo medido em 2026-11-15: o primeiro build completo do ai-memory, 6 min nesta máquina; os
    seguintes recompilam só o que mudou. O `make package` com as duas arquiteturas e LTO completo
    deve ficar em 10–15 min (medir nesta fase).
  - O `docs/plans/README.md` passa a citar o Rust nas ferramentas da máquina.
  - O limite `app_mb` do `tools/perf/limits.py` sobe para 85, com o motivo ao lado. No Windows, o
    engine entra quando a memória for portada; até lá o build Windows segue sem ela.
  - Procedimento de merge do upstream no `CLAUDE.md` da feature. Features: memory.
- **C. O processo, a captura e as pastas.**
  - `cadex-memory` com o memory.sock, a vida pelo launchd e o escritor único; dados em
    `~/Library/Application Support/Cadex/memory/` (a criar), no layout do ai-memory (wiki/ em git,
    db/, raw/, models/).
  - O kit da sessão (plano 18) contribui os hooks da memória: SessionStart, UserPromptSubmit,
    PostToolUse, PreCompact, PostCompact, SubagentStart, SubagentStop, Stop, SessionEnd. Todos pelo
    `cadex hook`, que manda ao memory.sock e, se o processo não responde, grava na fila local e
    sai; o `cadex-memory` esvazia a fila ao subir. Nunca espera o engine fora do SessionStart.
  - Projeto pela raiz do repositório: as worktrees dele dividem a mesma memória.
    memory.shareAcrossAccounts (ligada): desligada, cada conta tem a sua.
  - **A memória automática do Claude:** o `autoMemoryDirectory` de cada conta aponta para auto/
    pelo kit; o `cadex-memory` indexa e versiona e **reconstrói o MEMORY.md** a partir dos arquivos
    de tópico (frontmatter `name`/`description`), dentro de 200 linhas / 25 KB, sem apagar entrada
    escrita à mão. Testado em 2026-11-14: 4 sessões simultâneas deixaram 1 entrada no MEMORY.md.
  - SessionEnd: página `sessions/<id>.md` e handoff por regras, sem modelo, e commit na wiki;
    sessão que morre sem SessionEnd vira o retrato de sessão interrompida do engine.
  - Configuração memory.enabled (**ligada**). Features: memory, agent-tools, agents, settings.
- **D. Briefing, busca e ferramentas.**
  - SessionStart (startup, resume, clear, compact, fork): o briefing do engine (handoff aberto,
    páginas fixadas, _rules/, decisões e armadilhas recentes), em frases de fato, no limite de
    caracteres dele. Se o `cadex-memory` não está de pé, o hook o sobe e espera no máximo 1 s; sem
    resposta, a sessão segue sem briefing. PreCompact: o checkpoint, que volta no SessionStart
    `compact` (testado em 2026-11-14 com `/compact`; falta conferir a compactação automática).
  - O `cadex mcp` (plano 20) expõe as ferramentas `memory_*` do engine, menos as de multiusuário e
    administração: `memory_query`, `memory_recent`, `memory_read_page`, `memory_write_page`,
    `memory_patch_page`, `memory_briefing`, `memory_handoff_*`, `memory_read_session_observations`
    e as demais de páginas e mensagens. Escrever só dentro da memória do projeto.
  - Skill `cadex-memory` no plugin do kit: quando buscar, quando salvar, quando abrir um handoff.
  - **Embeddings ligados:** o modelo local (87 MB) baixado em segundo plano na primeira sessão de
    agente, sem travar nada (até lá, só FTS5); carregado só para indexar ou buscar e descarregado
    depois de parado. Busca híbrida (FTS5 + vetores) do engine.
  - Antes de fechar a fase, o teste das 30 perguntas: uma wiki com as nossas ADRs e specs, 30
    perguntas reais, acerto do FTS5 contra o híbrido, registrado na spec.
  - Features: memory, agent-tools.
- **E. Continuar em outro agente (o `run`).**
  - O workstream do engine (qual sessão continua qual, a trava contra dois agentes no mesmo
    workstream, o leitor das conversas de Claude e Codex) no `cadex-memory`.
  - Comando agents.continue-in-agent (⌘K "Continue in…"): escolhe agente e conta; o Cadex abre a
    aba com o workstream e, numa troca Claude ↔ Codex, o dossiê da sessão anterior (Markdown à
    parte, só de leitura, apagado quando a sessão fecha). Claude → Claude continua o "Continue in
    Another Account" do plano 18 (`--resume --fork-session`), agora registrado no workstream.
  - O Codex só entra onde aceitar hooks e MCP por argumento ou `CODEX_HOME` da conta do Cadex, sem
    escrever na pasta do dono; o que faltar fica para o plano do kit do Codex.
  - Features: memory, agents, command-palette.
- **F. Consolidação na sessão, sem token.**
  - Hook Stop com `decision: "block"` só em marcos: worktree marcada como pronta (plano 19),
    contexto acima de memory.consolidateAtContext (70%, do `context_window` que o
    `cadex statusline` grava) ou pedido do dono. O motivo diz "consolide esta sessão na memória" e o
    próprio Claude escreve as páginas pelas ferramentas `memory_*`. No máximo uma vez por marco.
  - Comando memory.consolidate-now (bracketed paste sem Enter, como no plano 21). Configuração
    memory.consolidateInSession (ligada).
- **G. Agente de memória de fundo (ADR 0029).**
  - Primeiro, a prova num script fora do app: `CLAUDE_CONFIG_DIR=<conta> claude -p` com o login da
    conta, `--model` barato, `--max-budget-usd`, `--no-session-persistence`, `--mcp-config` só com
    as ferramentas de memória e `--allowedTools` limitado. Visto em 2026-11-14: usou o login da
    assinatura e custou menos de US$ 0,01 por chamada curta no haiku. Sem a prova passando, a fase
    para.
  - O provedor "Claude do usuário" do fork chama esse `claude -p` para as tarefas do engine:
    consolidação (sessão parada ou depois da compactação), auto-improve (propostas vão para
    aprovação, memory.requireApproval ligada), experience, dream (computador parado; para quando o
    dono volta), profile e bootstrap (manual).
  - Fila no `cadex-memory`, um trabalho por vez, teto por dia (memory.dailyBudgetUsd), tudo
    registrado com custo. Configuração memory.backgroundAgent (desligada). Comandos
    memory.run-dream, memory.bootstrap, memory.pause-agent.
- **H. Página Memory.** Página da barra lateral (ícone Phosphor):
  - A wiki em árvore, aberta e editada como Markdown; histórico pelo `git-history`.
  - Cada página com a origem: sessão, conta e hora, com "Abrir a sessão" (plano 18).
  - "O que o agente vai ver": o briefing exato da próxima sessão neste projeto.
  - Estado do `cadex-memory` e do modelo de embeddings (baixando, pronto, carregado).
  - Fila do agente de fundo com custo; propostas para aprovar ou recusar.
  - Comandos memory.show, memory.show-briefing, memory.approve, memory.reject, memory.reindex.
    Features: memory, sidebar, markdown, git-history.
- **I. Peso e fechamento.** Cenários no `tools/perf/run.py`: app parado igual ao de hoje (o engine
  fora do app); `cadex-memory` ausente sem sessão de agente; ligado e parado com uma wiki de 2 mil
  páginas; uma sessão falsa mandando 500 eventos; o modelo descarregado depois de parado. Limites
  novos no `tools/perf/limits.py` com o motivo ao lado. Os ids novos em `MAC_ONLY` de
  `tools/check_command_parity.py`. `CLAUDE.md` das features tocadas, README e notas da release em
  inglês.

## Como validar
- `make check` a cada fase (com o engine e os testes dos crates mantidos a partir da B); `make perf`
  nas fases B a I.
- Fase A: ADR 0028 cita o que revê (0002, 0004, 0022, 0023, a linha "IA embutida" da raiz) e o que
  sai do fork; ADR 0029 cita a 0019, a linha "launcher de agentes" e a posição sobre os termos;
  spec com critérios; `make manifests`.
- Fase B: o app universal até 85 MB; o `cadex-memory` por arquitetura no tamanho medido e
  anotado; o build sem nenhum crate de web, multiusuário ou provedor remoto (`cargo tree`).
- Fase C: numa sessão do Cadex, prompts e edições chegam ao engine; com o `cadex-memory` morto, a
  fila guarda e esvazia quando ele volta; 4 sessões simultâneas salvando memória deixam o MEMORY.md
  com as 4 entradas; com shareAcrossAccounts desligada, duas contas não se veem; sem sessão de
  agente, nenhum `cadex-memory` no `ps`; o `~/.claude` do dono não muda.
- Fase D: o hook de ferramenta no tempo de hoje; o briefing dentro do limite e sem frase
  imperativa; uma decisão salva numa sessão aparece no briefing da seguinte; o teste das 30
  perguntas registrado; o modelo descarrega depois de parado.
- Fase E: uma sessão do Claude interrompida continua no Codex com o dossiê, e o dossiê some quando
  a sessão fecha; dois agentes não pegam o mesmo workstream.
- Fase F: marcar a worktree como pronta faz o Claude escrever as páginas uma vez, sem chave
  configurada em lugar nenhum.
- Fase G: a prova registrada com custo e versão; desligado, nenhum `claude -p` roda (`ps`); ligado,
  o dream para quando o dono mexe no teclado; o teto diário é respeitado.
- Fase H: editar uma página na Memory gera commit; "Abrir a sessão" leva à conversa certa; o
  briefing mostrado é igual ao que a sessão recebeu (conferido no transcript).
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`).
