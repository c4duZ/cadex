# Plano 22 — Memória: o engine do ai-memory dentro do Cadex

Depende de: plano 20 (servidor MCP e skills do Cadex), plano 19 (app.sock, `cadex hook`,
worktrees, daemon do terminal) e plano 18 (kit da sessão, contas, histórico, continuar em outra
conta); não depende do 21 · Features: memory (nova, núcleo e app macOS), agents, agent-tools,
terminal, markdown, git-history, explorer, sidebar, settings, command-palette · Decisões: ADR 0028
e ADR 0029 (a escrever na fase A), `docs/adr/0002-zig-core-with-c-api.md` e
`docs/adr/0004-clean-rewrite.md` (revistas pela 0028 só para a memória),
`docs/adr/0005-every-action-is-a-command.md`, `docs/adr/0007-one-step-install.md`,
`docs/adr/0019-agents-observe-only.md` e as ADRs 0021 a 0027 dos planos 18 a 21.

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
- **Editar dentro dos crates do upstream.** A prova de 2026-11-15 montou o engine sem mudar uma
  linha deles; tudo o que é nosso fica no crate do Cadex. Editar o roteador de hooks ou o servidor
  MCP dele (que crescem milhares de linhas por quinzena) traria conflito a cada merge.
- O engine dentro do app ou dentro do daemon do terminal: um erro nele derrubaria a janela ou todas
  as sessões. Ele roda no processo `cadex-memory`.
- O que o Cadex já faz de outro jeito: o servidor HTTP na porta 49374, a interface web e o console
  de gestão, `install-hooks`, `install-mcp`, `mcp-bridge`, `setup`, `upgrade`, `doctor`, os serviços
  launchd/systemd dele e o suporte aos outros ~13 CLIs (fica Claude e Codex).
- O multiusuário dele: login, senhas, chaves `aim_`, permissões por projeto, painel de admin (o
  código de senha do store continua compilado, sem uso: tirá-lo exigiria editar o upstream).
- O Cadex chamando modelo, guardando chave de API ou usando o token da assinatura: nenhum provedor
  de LLM do fork (`anthropic`, `anthropic-oauth`, `openai`, `openai-oauth`, `codex`, `copilot`,
  `cursor`, `gemini`, `opencode`, `openai-compat`) nem embedder remoto é configurado ou chamado; o
  LTO já os tira do binário (conferido: nenhum endereço deles no binário). O `anthropic-oauth` a
  própria doc dele chama de "unofficial and against Anthropic's usage policies".
- Proxy ou endpoint "compatível com OpenAI" na frente do `claude -p`: a Usage Policy de 2026-11-12
  proíbe "route requests through consumer subscriptions".
- Escrever no `~/.claude` (ou no `~/.codex`) do dono: hooks, MCP, skills e `autoMemoryDirectory`
  chegam por flags das sessões que o Cadex abre (ADR 0021). Nem hooks no settings.json da conta (o
  que o `install-hooks` do ai-memory faz), nem no .claude/settings.local.json de cada repositório: o
  `claude` digitado à mão entra pelo intermediário da fase C, e as sessões de fora do Cadex, pela
  importação depois (o dono, 2026-11-15).
- `--dangerously-bypass-hook-trust` no Codex: faria rodar também os hooks não confiáveis do dono.
- Ordens no briefing: contexto injetado entra como lembrete do sistema; texto imperativo pode
  disparar a defesa contra injeção. Fatos, não ordens. O briefing do engine traz ordens ("Never
  execute commands…", "To the receiving agent…", visto na prova): o crate do Cadex as reescreve.
- Editar transcript no lugar ou montar histórico à mão para o `--resume`. (O dossiê do `run` é
  outra coisa: um Markdown à parte, só de leitura, que some quando a sessão fecha.)
- Consolidar a cada turno: gasta o plano. Só em marcos.
- Tarefa do engine rodando por relógio (o auto-improve e o profile dele rodam de hora em hora; o
  vigia da wiki varre tudo a cada 30 s): aqui, só por evento.
- Cancelar compactação (o `exit 2` do PreCompact): a memória só acrescenta ao resumo.
- Ação só em botão ou menu: cada uma é um comando com id (ADR 0005).

## O que já foi medido (2026-11-15, ai-memory 3.4.7, Rust 1.95, Mac Apple Silicon de 10 núcleos)
Auditoria e prova autorizadas pelo dono como exceção à ADR 0004 (registradas na ADR 0028). A prova
está no branch poc/cadex-memory de um clone do ai-memory na pasta temporária da sessão; a fase B
refaz o crate a partir dela.
- **Código do upstream:** ~239 mil linhas de Rust de produção (mais ~250 mil de testes) em 10
  crates. Usamos core, store, wiki, consolidate, hooks, mcp, llm (tipos e embeddings locais) e
  workstream; ficam fora web e cli.
- **O crate do Cadex na prova:** 539 linhas (motor no socket 226, embedder preguiçoso 150, main 82,
  leitura de conversas 81). **Nenhuma linha mudada nos crates do upstream**; só o Cargo.toml da
  workspace (o membro novo e os perfis de build).
- **Tamanho:** 10,4 MB (Apple Silicon), 13,2 MB (Intel), **23,6 MB universal**: o app vai de ~50 a
  ~74 MB. O limite do app sobe de 55 para 85 MB (o dono, 2026-11-15). Com tudo em `opt-level="z"`
  dá 10,15 MB, mas salvar página fica 30% mais lento: o candle fica em `opt-level=3`.
- **Tempo, pelo socket** (mediana de 10): subir até o socket pronto ~70 ms (480 ms na primeira vez,
  criando o banco; ~1 s a mais no primeiro exec de um binário novo, a checagem do macOS);
  **briefing 0,9 ms**; hook de ferramenta 0,15 ms (fila); busca só FTS5 2,8 ms, híbrida 9,1 ms
  (~390 ms quando precisa carregar o modelo); salvar página 34–46 ms (~180 ms uma ADR inteira).
- **RAM:** parado e sem modelo, 22 MB RSS / 12 MB de footprint, 7 threads; com o modelo, 193 MB
  depois de uma busca e 280–335 MB em gravação em lote (pico 366 MB); depois de descarregar o
  modelo, o footprint fica em **68 MB** (o alocador não devolve). Intel pelo Rosetta: 420–446 MB
  com o modelo.
- **CPU parado:** o vigia da wiki gasta 0,08 s a cada 120 s; sem ele, zero.
- **Build:** do zero, Apple Silicon com LTO completo, 5 min; só religar, 1 min.
- **Testes do upstream no PC** (Linux, 12 núcleos, `roda-no-pc`): os crates usados, 4.804 testes em
  15 min 54 s; a workspace inteira, 8.110 em 17 min 21 s (12 falhas, todas do cli e do ambiente
  montado para a prova).
- **Acompanhar o upstream:** de 31/10 a 15/11 foram 1.048 commits e +88 mil linhas (+43 mil nos
  crates usados). O crate da prova sobre a versão de 31/10 e depois o merge da de 15/11: **0
  conflitos de texto** e 2 erros de compilação (mudança de API, 3 linhas).
- **Claude Code 2.1.325, testado:**
  - dois `--settings`: **vale só o último**, em qualquer ordem, arquivo ou JSON; os hooks da conta
    continuam rodando junto. Hooks por `--plugin-dir` não colidem com o `--settings` do dono;
  - Stop com `decision: "block"`: o Claude continua, faz o pedido e para; `stop_hook_active` vem
    `true` na segunda chamada (sem laço); o pedido aparece como turno do usuário no transcript; o
    Stop traz `last_assistant_message`; +US$ 0,005 no haiku;
  - **compactação automática:** o PreCompact chega com `trigger: "auto"`, o texto dele entra no
    resumo, o PostCompact traz `compact_summary` e vem o SessionStart `compact`. Para testar,
    `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=1` dispara no turno seguinte;
  - o intermediário: `--version`, `--help`, `mcp list`, `plugin list`, `auth status`, `-p` saem
    idênticos ao `claude` de verdade; uma sessão interativa recebe o kit. Numa pasta nova, o
    SessionStart só roda depois de aceita a confiança, e o próprio Claude grava essa confiança no
    .claude.json da conta.
- **Codex 0.149.1, sem login:** MCP por `-c mcp_servers.<nome>...` funciona e soma aos do dono;
  hooks por `-c hooks.<Evento>=...` carregam mas ficam "não confiáveis" e não rodam; a confiança vale
  só gravada no config.toml de um `CODEX_HOME` (o hash vem do `hooks/list` do `codex app-server`).
  Eventos: SessionStart, UserPromptSubmit, PreToolUse, PermissionRequest, PostToolUse, PreCompact,
  PostCompact, SubagentStart, SubagentStop, Stop, SessionEnd. Sem login não deu para ver a saída do
  hook chegando ao modelo.
- **Disco:** 54 páginas (as nossas ADRs e specs) = wiki 1,8 MB + banco 5,3 MB.
- **Fase B, o build de verdade (2026-11-15):** `cadex-memory` com 9,98 MB (Apple Silicon) e
  12,57 MB (Intel), 22,6 MB universal; **app de release com 73,2 MB**; parado, 11 MB de footprint
  e CPU zero; sobe em ~120–150 ms (670 ms na primeira vez); nenhum endereço de provedor no binário.
  `panic="unwind"` custaria +2,3 MB por arquitetura (12,28 MB): fica `abort`. Release do zero:
  2 min 21 s (Apple Silicon) e 4 min 22 s (Intel); `make package` ~4 min do zero, 30 s com cache.
  O Cargo.lock do crate tem as mesmas 408 versões do upstream. 383 crates na lista de licenças,
  todas aceitas (um MPL-2.0, `option-ext`, sem modificação).

## Como eu quero
**Arquitetura:**
- **O fork:** os crates do ai-memory **sem edição**, baixados pelo Cargo fixados por commit (no
  Cargo.toml e no Cargo.lock do crate do Cadex), como a libghostty no `core/build.zig.zon`; nada do
  código dele copiado para o repositório (seriam 25 MB num repositório de 37 MB; decidido na fase
  B, 2026-11-15). No `NOTICE`, com as licenças das dependências.
- **O crate do Cadex** (core/features/memory/server/, a criar): monta o `cadex-memory` com os crates
  usados e tudo o que é nosso: o servidor no socket, o embedder preguiçoso, a leitura de conversas
  de várias contas, a reescrita do briefing, o handoff melhor, o provedor "Claude do usuário". O que
  for copiado do cli do upstream (a montagem do servidor, ~400 linhas da conversão de conversas do
  backfill) leva no topo a origem (arquivo e versão) e entra no checklist do merge.
- **O processo `cadex-memory`:** executável Rust universal dentro do app. Sobe como o daemon da
  ADR 0022 (sem launchd: quem precisa dele o inicia com `setsid` se não responde no socket) quando a
  primeira sessão de agente abre num projeto com a memória ligada, e sai sozinho quando a última
  fecha: ele registra o `claude` de cada SessionStart e o kqueue o avisa quando esse processo
  termina, sem timer parado. Escritor único da wiki e do banco. Um erro nele só para a memória: o
  próximo hook o sobe de novo e a fila local do hook guarda o que chegou nesse meio-tempo.
- **O terceiro socket:** memory.sock na pasta de sockets do Cadex (revê a ADR 0022), modo 0600,
  com o mesmo token por sessão e `getpeereid` do app.sock. O caminho cabe no limite de 104 bytes do
  macOS (a pasta de sockets já é curta pela ADR 0021). Só a feature `memory` do núcleo fala com ele;
  o `cadex hook`, o `cadex mcp` e o app passam por ela.
- **A IA:** o ponto do engine que chama o "provedor de LLM" recebe, pelo crate do Cadex, uma
  implementação só, o Claude do usuário: na sessão (fase F) ou num `claude -p` de fundo (fase G).
  Sem nenhum dos dois, as tarefas que precisam de modelo não rodam e o resto funciona igual.

**Fases:**
- **A. Decisão, ADRs e spec (sem código).**
  - ADR 0028 (docs/adr/0028-project-memory.md, a criar): o engine é o fork do ai-memory, sem edição
    nos crates dele; exceção à ADR 0004 só para esse código (MIT, crédito no `NOTICE`); Rust no
    núcleo só para a feature memory (revê a ADR 0002); o processo `cadex-memory` e o memory.sock
    (revê a 0022); o que fica fora do fork e por quê; o fork acompanha o upstream pelo procedimento
    da fase B. Revê também a ADR 0023: a consolidação na sessão (fase F) manda o agente consolidar
    por um Stop com `block`, sem clique, nos marcos ligados em memory.consolidateInSession. Reescreve a linha
    "IA embutida no app" do `CLAUDE.md` da raiz para: "O Cadex não roda modelo nem guarda chave:
    quando a memória precisa de IA, quem pensa é o Claude Code do usuário, na sessão ou numa sessão
    nova pelo CLI na mesma conta".
  - ADR 0029 (docs/adr/0029-memory-agent.md, a criar): o agente de memória de fundo, um
    `claude -p` novo na conta, desligado por padrão (fase G). Revê a ADR 0019 e a linha "launcher de
    agentes" do `CLAUDE.md` da raiz **só para ele** (a ADR 0033 do plano 24 generaliza depois). Fixa
    a posição sobre os termos: uso automatizado da assinatura, sem o dono disparando, é zona cinzenta
    pelos Consumer Terms §3(7); por isso desligado, com teto de gasto, e o Cadex sugere chave de API
    (`apiKeyHelper`) como alternativa.
  - Spec docs/spec/memory.md (a criar): pastas, processo, briefing, página, chaves, estados, o que o
    fork mantém do comportamento do ai-memory, e os limites conhecidos (o `alias claude=` do dono
    passa por cima do intermediário; sessões de fora do Cadex não recebem briefing; Codex sem hooks
    até ter `CODEX_HOME` do Cadex). Termos "Memória do projeto", "Briefing", "Handoff",
    "Workstream", "Consolidação" e "Agente de memória" no `docs/CONTEXT.md`.
- **B. O fork, o crate e o build.**
  - Fixar o ai-memory por commit (v3.4.7) e refazer o crate do Cadex a partir da prova:
    servidor axum no UnixListener com o roteador de hooks, o do workstream e o MCP (streamable
    HTTP, sem estado); o middleware de autenticação dele roda sem token, como usuário único.
  - Perfil de release `cadex`: `opt-level="z"`, LTO completo, `codegen-units=1`, sem símbolos, com
    candle e gemm em `opt-level=3`. `panic`: medir `abort` contra `unwind` (tamanho e o que um
    pânico numa tarefa faz) e anotar a escolha; com `abort`, um pânico derruba o processo, e o
    teste da fase C confere que a fila não perde evento.
  - **Como compila** (o dono, 2026-11-15): o `cadex-memory` é mais um executável auxiliar, como o
    `cadex-terminald`; Zig e Rust não se misturam numa compilação (o `cadex` fala com ele pelo
    memory.sock, sem API C entre os dois). Ferramenta: `rustup` com a versão do
    rust-toolchain.toml do fork (1.95) e os alvos `aarch64-apple-darwin` e `x86_64-apple-darwin`;
    só quem desenvolve precisa dela, quem instala recebe o binário no app (ADR 0007 intacta).
    - `make memory` (novo): `cargo build --release --locked` das duas arquiteturas.
    - `make app` e `make run`: o `cadex-memory` em debug, só da arquitetura da máquina.
    - `make check`: os testes do crate do Cadex e uma prova rápida (o engine sobe numa pasta
      temporária, recebe um SessionStart com página no escopo e devolve o briefing; grava e acha uma
      página), em segundos. A suíte dos crates do upstream (16 min no PC) **não** entra.
    - `make memory-upstream-test` (novo): a suíte dos crates usados, no PC (o host `pc` do
      `roda-no-pc`), mandada por `ssh` só com o commit fixado; roda em toda atualização do
      upstream. Não pelo `roda-no-pc`: ele espelha a pasta inteira, com os builds (4,8 GB), e
      encheu o disco do PC em 2026-11-15; a pasta de build dos testes é apagada ao fim.
    - `make package` (`apps/macos/packaging/build.sh`): como o `cadex-terminald`: `lipo` das duas
      fatias em `Contents/Helpers/cadex-memory`, `strip`, `codesign`, e cada fatia sobe numa pasta
      temporária e responde no socket (a Intel pelo Rosetta, quando houver). Confere também que o
      binário não tem endereço de provedor (`strings`).
  - Dependências pelo Cargo.lock do fork (`--locked`), baixadas do crates.io no primeiro build e
    guardadas no cache do `~/.cargo`, não copiadas para o repositório. Licenças conferidas pelo
    `cargo deny` com o deny.toml do fork, e o resultado vai para o `NOTICE`. Ficam no binário, por
    dependência dos crates usados: reqwest, rustls e ring (download do modelo, webhooks da wiki),
    hyper (axum) e argon2 (senhas do store, sem uso); a spec registra isso.
  - Tempos medidos: build do zero 5 min, religar 1 min. O `make package` com as duas arquiteturas
    medido nesta fase.
  - O limite `app_mb` do `tools/perf/limits.py` sobe para 85, com o motivo ao lado. No Windows, o
    engine entra quando a memória for portada; até lá o build Windows segue sem ela.
  - **Procedimento de atualização do upstream** no `CLAUDE.md` da feature: (1) trocar o commit
    fixado; (2)
    `make memory` e corrigir as mudanças de API no crate do Cadex; (3) `make memory-upstream-test`
    no PC; (4) comparar o serve.rs e a conversão de conversas do cli do upstream entre as duas
    versões e trazer ao crate do Cadex os passos novos (o compilador não pega passo de
    inicialização novo); (5) `make check` e `make perf`. Sem calendário fixo: quando houver correção
    que importa ou recurso que queremos, no máximo a cada mês.
  - O `docs/plans/README.md` passa a citar o Rust nas ferramentas da máquina. Features: memory.
- **C. O processo, a captura e as pastas.**
  - `cadex-memory` com o memory.sock, iniciado sob demanda (`setsid`, como o daemon do terminal),
    o fim pelo kqueue sobre os `claude` vivos e o escritor único; dados em
    `~/Library/Application Support/Cadex/memory/` (a criar), no layout do ai-memory (wiki/ em git,
    db/, raw/, models/).
  - **Aquecer depois de instalar ou atualizar:** na primeira abertura do app depois de uma versão
    nova, o app roda o `cadex-memory` uma vez em segundo plano (migrações do banco e a checagem do
    macOS do binário novo), para que o primeiro SessionStart não gaste o 1 s de espera nisso.
  - **Os hooks da memória entram pelo kit, no `--settings`** como os dos planos 19 e 21, num
    comando próprio, `cadex memory-hook <evento>` (separado do `cadex hook` do app, que corta o
    PostToolUse para a revisão; numa edição rodam os dois, ~4 ms a mais). Mover os hooks para o
    `--plugin-dir` foi recusado (fase C, 2026-11-15): o plugin é uma pasta fixa, e o `--settings`
    do kit leva também ambiente e permissões; a colisão com o `--settings` do dono só existe no
    `claude` digitado, e o intermediário junta os dois. Os eventos: SessionStart,
    UserPromptSubmit, PostToolUse, PreCompact, PostCompact, SubagentStart, SubagentStop, Stop,
    SessionEnd. O comando fala HTTP/1.1 com o memory.sock (token da sessão no cabeçalho); se o
    processo não responde, grava na fila local e sai; o `cadex-memory` esvazia a fila ao subir.
    Nunca espera o engine fora do SessionStart. O kit passa no ambiente o caminho do
    `cadex-memory` e a pasta da memória.
  - **Escopo:** o `cadex hook` manda sempre `project_strategy=repo-root` e `briefing=1`, desde a
    primeira sessão de cada projeto. Sem isso o engine faz de cada worktree um projeto à parte (pelo
    nome da pasta) e, uma vez registrada assim, ela não volta; e sem `briefing=1` as páginas não
    entram no briefing. Workspace `default`; memory.shareAcrossAccounts (ligada): desligada, cada
    conta vira uma workspace própria.
  - **A memória automática do Claude:** o `autoMemoryDirectory` de cada conta aponta para auto/
    pelo kit; o `cadex-memory` indexa e versiona e **reconstrói o MEMORY.md** a partir dos arquivos
    de tópico (frontmatter `name`/`description`), dentro de 200 linhas / 25 KB, sem apagar entrada
    escrita à mão. Testado em 2026-11-14: 4 sessões simultâneas deixaram 1 entrada no MEMORY.md.
    Como ficou (2026-11-16), diferente do texto acima: o `autoMemoryDirectory` não é por conta, é
    **por sessão**, na pasta do projeto (`auto/<chave do projeto>`, e `auto/<conta>/<chave>` com
    memory.shareAcrossAccounts desligada), porque o MEMORY.md é de um projeto; a chave é a raiz do
    repositório principal (worktrees e subpastas juntas), com a mesma regra no app e no engine,
    fixada por um teste de cada lado. Só vai quando quem abre a sessão sabe a pasta dela (todas as
    entradas do app sabem; sem ela fica a pasta padrão do Claude). Um project.json em cada pasta
    leva o engine ao projeto. O vigia é por FSEvents só da pasta auto/ (o vigia da wiki continua
    desligado), com 500 ms para juntar as gravações; ao subir, acerta tudo uma vez. Cada tópico vira
    a página `auto/<arquivo>` (kind `fact`) pelo `memory_write_page`, que já faz o commit na wiki.
  - **Sem vigia por relógio:** o vigia da wiki do engine fica desligado. Edição pela página Memory
    vai pelo engine (`memory_write_page`/`memory_patch_page`); edição de fora (outro editor) entra
    pela reindexação ao subir o processo e pelo comando memory.reindex.
  - SessionEnd: página `sessions/<id>.md` e handoff, sem modelo, e commit na wiki. **O handoff do
    crate do Cadex:** o do engine é fraco (disse "sessão de um prompt" depois de 10 edições); o
    nosso lista os prompts, os arquivos editados e o último estado, só com o que foi capturado.
    Como ficou (2026-11-16): o engine liga `record_tool_names` (o nome da ferramenta, nunca os
    argumentos) e `index_file_paths` (o caminho relativo ao checkout do arquivo que ela nomeou; o
    campo que o cliente do upstream manda é posto pelo engine, porque o `cadex memory-hook` passa o
    payload como veio). O roteador do upstream responde antes de terminar a sessão, então o crate
    espera o aviso que ele dá ao fim de cada SessionEnd (o `profile_notify`) e troca o texto: como o
    store não tem atualização de handoff, cancela o automático (só se ainda aberto) e insere um
    igual com o texto novo, pego uma vez só como o primeiro. A última resposta do assistente não
    entra (a captura dela segue desligada). O texto é só de fatos: sem "Continue from" nem
    "Next steps".
    Sessão que morre sem SessionEnd vira o retrato de sessão interrompida do engine.
  - **O histórico que já existe** (o dono, 2026-11-15): na primeira sessão de um projeto com a
    memória vazia, o backfill importa sozinho, em segundo plano e sem IA, as conversas antigas do
    projeto (até 200 sessões por agente e 50 mil eventos, os limites dele), pelo mesmo caminho e a
    mesma limpeza da captura ao vivo. Viram sessões e observações na busca, não páginas. Uma vez só;
    nunca numa memória que já tem conteúdo. O do upstream lê uma pasta de conta só e casa o cwd
    exato; o crate do Cadex percorre **todas as pastas de conta** (as do plano 18; só a da conta com
    memory.shareAcrossAccounts desligada), tira repetidas pelo id da sessão e casa **a raiz do
    repositório, as subpastas e as worktrees dele** (as do plano 19), não só o cwd exato.
    Como ficou (2026-11-16): "memória vazia" é a regra do upstream (nenhuma sessão no projeto além
    da que começa); escolhe as 200 mais novas e entra na ordem em que aconteceram (mais novas
    primeiro deixavam a mais velha no topo do briefing); não deixa handoff (`auto_handoff=0`); uma
    marca em `<memória>/imports/` faz ser uma vez só e retoma uma importação cortada pela saída do
    processo; sessão cuja pasta já não existe fica de fora (o leitor do upstream confere a pasta).
  - **O `claude` digitado à mão** (o dono, 2026-11-15, opção "1 + 3"): prefixar o PATH das abas
    não funciona (o shell de login e o `.zshrc` reordenam). O Cadex abre o zsh das abas com uma
    pasta de inicialização dele (`ZDOTDIR`): ela devolve o `ZDOTDIR` do dono, carrega os arquivos
    dele normalmente e define uma função `claude` que chama `cadex claude`, que pede o kit ao app e
    executa o `claude` de verdade com ele, sem trocar a conta (o `CLAUDE_CONFIG_DIR` da aba fica
    como está). Bash e fish ficam sem (entram pela importação).
    - Só para sessão interativa. Passam direto, sem nada: `-p`/`--print`, `-v`/`--version`,
      `-h`/`--help` e todo subcomando. O subcomando é a primeira palavra que não é opção, pulando o
      valor das opções que levam valor (`claude --model haiku mcp list` é `mcp`). A lista vem do
      `claude --help` mais os escondidos achados na prova (`daemon`, `design-login`,
      `import-conversations`, `project`, `remote-control`/`rc`/`bridge`, `sandbox`,
      `workspace-trust`, `worktree-hook`), num arquivo do agent-tools; um teste do `make check`
      compara a lista com o `claude` instalado e avisa quando aparecer palavra nova.
    - `--bg` e `remote-control` passam direto, sem kit, até decisão própria.
    - Se o dono passa `--settings`, o intermediário junta o dele com o `statusLine` do kit num
      arquivo só (o do dono vale em tudo, menos o `statusLine`), porque dois `--settings` não se
      somam; os hooks dos dois se somam nesse arquivo.
    - Um `alias claude=` do dono passa por cima, e a spec diz isso.
  - **Sessões de fora do Cadex** (outro terminal, VS Code, bash e fish): nada percebe a hora em que
    terminam sem um vigia rodando o tempo todo. Toda vez que o `cadex-memory` sobe, ele importa,
    pelo mesmo caminho do backfill, as sessões dos projetos conhecidos que ainda não estão na
    memória (pelo id da sessão). Briefing elas não receberam.
    Como ficou (2026-11-16): a importação roda em segundo plano depois que o socket está pronto,
    para não atrasar o SessionStart que subiu o processo; esse briefing pode sair sem elas, e a
    sessão seguinte já as tem. Não roda no reinício que devolve a memória (o processo não "subiu").
    Por subida: até 50 sessões e 10 mil eventos, mais novas primeiro; transcript mexido nos
    últimos 2 minutos espera (pode ser uma sessão aberta); um ponto de controle por conta faz a
    subida seguinte ler só o que mudou depois, e só avança quando nada ficou para trás. Projeto
    cuja importação do histórico ainda vai rodar fica com ela.
  - Configuração memory.enabled (**ligada**). Features: memory, agent-tools, agents, terminal,
    settings.
- **D. Briefing, busca e ferramentas.**
  - SessionStart (startup, resume, clear, compact, fork): o briefing do engine (handoff aberto,
    páginas fixadas, _rules/, decisões e armadilhas recentes), no limite de caracteres dele.
    **O crate do Cadex reescreve o briefing antes de entregar:** tira as frases imperativas do
    modelo do engine e deixa só fatos; um teste com o texto do engine falha se o upstream mudar o
    modelo e uma ordem nova passar. Se o `cadex-memory` não está de pé, o hook o sobe e espera no
    máximo 1 s; sem resposta, a sessão segue sem briefing. Numa pasta nova, o briefing chega depois
    que o dono aceita a confiança da pasta (é quando o Claude roda o SessionStart).
  - PreCompact: o checkpoint, que entra no resumo, manual ou automático (testado nos dois); o
    PostCompact guarda o `compact_summary` na sessão; o SessionStart `compact` traz o checkpoint.
  - O `cadex mcp` (plano 20) expõe as ferramentas `memory_*` do engine, menos as de multiusuário e
    administração: `memory_query`, `memory_recent`, `memory_read_page`, `memory_write_page`,
    `memory_patch_page`, `memory_briefing`, `memory_handoff_*`, `memory_read_session_observations`
    e as demais de páginas e mensagens. Escrever só dentro da memória do projeto.
  - Skill `cadex-memory` no plugin do kit: quando buscar, quando salvar, quando abrir um handoff.
  - **Embeddings ligados, pelo embedder preguiçoso do crate do Cadex:** o do engine carrega o
    modelo ao subir e nunca solta. O nosso: o modelo (87 MB) baixado em segundo plano na primeira
    sessão de agente, com retomada se cair e conferência do arquivo (até lá, só FTS5); carregado na
    primeira busca ou gravação que precisa (~400 ms); descarregado depois de memory.embedIdleSecs
    (60 s) parado. **Como o alocador não devolve a memória** (68 MB depois de descarregar), o
    `cadex-memory` se reinicia sozinho quando está parado, sem modelo e sem pedido em andamento
    (~70 ms), e volta aos ~12 MB.
  - O download do modelo é testado de verdade nesta fase (a prova copiou o arquivo): rede caindo no
    meio, arquivo corrompido, sem rede (fica no FTS5 e tenta de novo na próxima sessão).
  - Antes de fechar a fase, o teste das 30 perguntas: uma wiki com as nossas ADRs e specs, 30
    perguntas reais, acerto do FTS5 contra o híbrido, registrado na spec.
  - Features: memory, agent-tools.
- **E. Continuar em outro agente (o `run`).**
  - O workstream do engine (qual sessão continua qual, a trava contra dois agentes no mesmo
    workstream, o leitor das conversas de Claude e Codex) no `cadex-memory`, pelo roteador de
    workstream dele (servido na prova).
  - Comando agents.continue-in-agent (⌘K "Continue in…"): escolhe agente e conta; o Cadex abre a
    aba com o workstream e, numa troca Claude ↔ Codex, o dossiê da sessão anterior (Markdown à
    parte, só de leitura, apagado quando a sessão fecha). Claude → Claude continua o "Continue in
    Another Account" do plano 18 (`--resume --fork-session`), agora registrado no workstream.
  - **Codex:** MCP por `-c mcp_servers...` (funciona e soma aos do dono). Hooks só com um
    `CODEX_HOME` do Cadex por conta, cujo config.toml guarda a confiança dos hooks do kit (o hash do
    `hooks/list` do `codex app-server`), gravada pelo Cadex na pasta dele, nunca no `~/.codex` do
    dono. Sem conta do Codex hoje (o dono, 2026-11-15): a parte do Codex fica pronta para testar e
    só fecha com uma conta; o que não puder ser conferido vai marcado na spec.
  - Features: memory, agents, command-palette.
- **F. Consolidação na sessão, sem token.**
  - Hook Stop com `decision: "block"` só em marcos: worktree marcada como pronta (plano 19),
    contexto acima de memory.consolidateAtContext (70%, do `context_window` que o
    `cadex statusline` grava) ou pedido do dono. O motivo diz "consolide esta sessão na memória" e o
    próprio Claude escreve as páginas pelas ferramentas `memory_*`. No máximo uma vez por marco; com
    `stop_hook_active` verdadeiro o hook nunca bloqueia de novo. A spec avisa que o pedido aparece
    no transcript como turno do usuário.
  - Comando memory.consolidate-now (bracketed paste sem Enter, como no plano 21). Configuração
    memory.consolidateInSession (ligada).
  - Ligar ao crate do Cadex o que a prova deixou de fora e esta fase precisa: o consolidador do
    engine e a manutenção (forget sweep, lint de regras, decaimento), disparados por evento (fim de
    sessão, subida do processo), nunca por relógio.
- **G. Agente de memória de fundo (ADR 0029).**
  - Primeiro, a prova num script fora do app: `CLAUDE_CONFIG_DIR=<conta> claude -p` com o login da
    conta, `--model` barato, `--max-budget-usd`, `--no-session-persistence`, `--mcp-config` só com
    as ferramentas de memória e `--allowedTools` limitado. Visto em 2026-11-14: usou o login da
    assinatura e custou menos de US$ 0,01 por chamada curta no haiku. Sem a prova passando, a fase
    para.
  - O provedor "Claude do usuário" do crate do Cadex chama esse `claude -p` para as tarefas do
    engine: consolidação (sessão parada ou depois da compactação), auto-improve (propostas vão para
    aprovação, memory.requireApproval ligada), experience, dream (computador parado; para quando o
    dono volta) e profile, todas por evento.
  - **Organizar o histórico com IA** (o bootstrap do engine, o dono, 2026-11-15): o `claude -p` lê
    o que o backfill importou e escreve as páginas de decisões, armadilhas e conceitos. Só por
    clique do dono (comando memory.bootstrap), depois de mostrar a estimativa de custo; por ser
    disparado pelo dono, roda mesmo com memory.backgroundAgent desligada, com o mesmo teto.
  - Fila no `cadex-memory`, um trabalho por vez, teto por dia (memory.dailyBudgetUsd), tudo
    registrado com custo. Configuração memory.backgroundAgent (desligada). Comandos
    memory.run-dream, memory.bootstrap, memory.pause-agent.
- **H. Página Memory.** Página da barra lateral (ícone Phosphor):
  - A wiki em árvore, aberta e editada como Markdown (gravando pelo engine); histórico pelo
    `git-history`.
  - Cada página com a origem: sessão, conta e hora, com "Abrir a sessão" (plano 18).
  - "O que o agente vai ver": o briefing exato da próxima sessão neste projeto, já reescrito.
  - Estado do `cadex-memory` e do modelo de embeddings (baixando, pronto, carregado).
  - O histórico importado (quantas sessões, de quais contas) e o botão "Organize History with AI"
    (memory.bootstrap), com a estimativa de custo antes.
  - Fila do agente de fundo com custo; propostas para aprovar ou recusar.
  - Comandos memory.show, memory.show-briefing, memory.approve, memory.reject, memory.reindex.
    Features: memory, sidebar, markdown, git-history.
- **I. Peso e fechamento.** Cenários no `tools/perf/run.py`, com limites no `tools/perf/limits.py`
  e o motivo ao lado, partindo da prova:
  - app parado igual ao de hoje (o engine fora do app); `cadex-memory` ausente sem sessão de agente;
  - `cadex-memory` parado sem modelo: footprint até 25 MB (12 MB na prova), CPU zero;
  - com o modelo carregado: pico até 400 MB (366 na prova); depois de memory.embedIdleSecs e do
    reinício sozinho, de volta ao limite parado;
  - uma wiki de 2 mil páginas e uma sessão falsa mandando 500 eventos: hook de ferramenta e
    briefing no tempo da prova (a ordem de 1 ms pelo socket, o `cadex hook` inteiro no tempo de
    hoje);
  - app de release até 85 MB.
  Os ids novos em `MAC_ONLY` de `tools/check_command_parity.py`. `CLAUDE.md` das features tocadas,
  README e notas da release em inglês.

**Testes que chamam o Claude de verdade** (lição da prova, que gastou US$ 1,73 em vez de US$ 0,08):
em bash com listas (nunca o `$args` do zsh, que não separa as palavras), `--model haiku` fixo,
`--max-budget-usd` e `--no-session-persistence` em todo `-p`, numa conta escolhida pelo dono, com o
custo anotado.

## Como validar
- `make check` a cada fase (com o crate do Cadex e a prova rápida do engine a partir da B);
  `make perf` nas fases B a I; `make memory-upstream-test` a cada merge do upstream.
- Fase A: ADR 0028 cita o que revê (0002, 0004, 0022, 0023, a linha "IA embutida" da raiz),
  a regra de não editar o upstream e o que fica fora do fork; ADR 0029 cita a 0019, a linha
  "launcher de agentes" e a posição sobre os termos; spec com critérios e limites conhecidos;
  `make manifests`.
- Fase B: o app universal até 85 MB; o `cadex-memory` por arquitetura no tamanho medido e anotado;
  `git diff` dos crates do upstream contra a tag vazio; o binário sem endereço de provedor; o
  `cargo tree` sem web, cli nem askama; cada fatia do pacote responde no socket; o procedimento de
  merge escrito e ensaiado uma vez.
- Fase C: numa sessão do Cadex, prompts e edições chegam ao engine; com o `cadex-memory` morto (e
  com um pânico forçado), a fila guarda e esvazia quando ele volta, sem perder evento; 4 sessões
  simultâneas salvando memória deixam o MEMORY.md com as 4 entradas; uma worktree nova cai na
  memória do repositório desde a primeira sessão; com shareAcrossAccounts desligada, duas contas
  não se veem; sem sessão de agente, nenhum `cadex-memory` no `ps`; o `~/.claude` do dono não muda.
  O primeiro projeto aberto importa o histórico de todas as contas, das subpastas e das worktrees,
  uma vez, sem atrasar a sessão; reabrir não importa de novo. Um `claude` digitado numa aba do
  Cadex grava e recebe briefing, na conta da aba; com `--settings` do dono, os hooks dele e os do
  kit rodam juntos; `claude -p`, `claude mcp list`, `claude --model haiku mcp list` e
  `claude --version` saem iguais aos de fora do Cadex. Uma sessão do projeto num terminal de fora
  entra na memória na próxima sessão do Cadex. O handoff de uma sessão com 10 edições lista as 10. O primeiro
  SessionStart depois de atualizar o app recebe briefing (o aquecimento funcionou).
  Coberto por teste no `make check` (2026-11-16), sem Claude de verdade: a fila guarda e esvazia
  com o processo morto e com um pânico forçado (`core/features/memory/server/tests/lifecycle.rs`,
  `core/features/memory/server/tests/session_end.rs`); 4 tópicos gravados juntos deixam 4 entradas no MEMORY.md e 4
  páginas (`core/features/memory/server/tests/auto_memory.rs`); o handoff de uma sessão com 10 edições lista as 10
  (`core/features/memory/server/tests/session_end.rs`); a worktree cai na pasta e na memória do repositório (MemoryTests,
  `core/features/memory/server/tests/import.rs`); a importação de contas, subpastas e worktrees uma vez
  (`core/features/memory/server/tests/import.rs`); o `--settings` do dono junto com o do kit (SessionKitTests). Só com
  uma sessão real do Claude Code: 4 sessões de verdade salvando ao mesmo tempo, o Claude lendo a
  pasta do `autoMemoryDirectory` e o MEMORY.md refeito na sessão seguinte, o `claude` digitado e os
  subcomandos, o `~/.claude` intacto, o `ps` sem engine, e o briefing depois de atualizar.
- Fase D: o hook de ferramenta no tempo de hoje; o briefing dentro do limite e sem frase
  imperativa; uma decisão salva numa sessão aparece no briefing da seguinte; a compactação
  automática leva o checkpoint ao resumo; o teste das 30 perguntas registrado; o modelo baixa (e
  retoma), carrega, descarrega depois de parado, e o processo volta ao limite de parado.
- Fase E: uma sessão do Claude interrompida continua no Codex com o dossiê, e o dossiê some quando
  a sessão fecha; dois agentes não pegam o mesmo workstream; sem conta do Codex, o que ficou sem
  conferir está marcado na spec.
- Fase F: marcar a worktree como pronta faz o Claude escrever as páginas uma vez, sem chave
  configurada em lugar nenhum; nunca dois bloqueios seguidos.
- Fase G: a prova registrada com custo e versão; desligado, nenhum `claude -p` roda (`ps`); ligado,
  o dream para quando o dono mexe no teclado; o teto diário é respeitado; "Organizar o histórico
  com IA" mostra o custo antes, só roda no clique e escreve as páginas.
- Fase H: editar uma página na Memory gera commit; "Abrir a sessão" leva à conversa certa; o
  briefing mostrado é igual ao que a sessão recebeu (conferido no transcript).
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`).
