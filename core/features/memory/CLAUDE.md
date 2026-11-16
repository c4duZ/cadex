# memory (núcleo)

## O que eu quero
- A memória do projeto entre sessões, contas e agentes (`../../../docs/spec/memory.md`,
  `../../../docs/adr/0028-project-memory.md`, plano `../../../docs/plans/22-memory.md`), com o
  engine do ai-memory (Rust, MIT, de Fábio Akita) num processo próprio, o `cadex-memory`.
- O código do upstream intacto, fixado por commit; tudo o que é do Cadex no crate de `server/`.

## O que eu não quero
- Editar os crates do ai-memory. Nem copiar o repositório dele para cá: o Cargo baixa os crates
  pelo commit fixado no `server/Cargo.toml` (e no `server/Cargo.lock`), como o `../../build.zig.zon`
  faz com a libghostty. Se um dia for preciso mudar o upstream, é um `[patch]` apontando para um
  fork, com ADR.
- Configurar ou chamar um provedor de LLM do fork, servidor TCP, interface web ou multiusuário
  (ADR 0028). O empacotamento falha se o binário tiver o endereço de um provedor.
- Outra feature falando com o `cadex-memory` sem passar por esta: o `cadex memory-hook` (e, depois,
  o `cadex mcp` e o app) usam o cliente desta pasta.
- Hook que faz a sessão esperar: fora do SessionStart, nunca espera o engine.

## Como eu quero
- `server/`: o crate `cadex-memory`, workspace própria (perfis e o `[patch]` do zip do upstream
  só valem na raiz). Versão do Rust no `server/rust-toolchain.toml` (a do upstream).
  - `server/src/main.rs`: escolhe o subcomando, liga o log (`CADEX_MEMORY_LOG`), roda o engine
    num runtime tokio de 2 threads e, se ele pediu, se executa de novo (`server/src/restart.rs`).
  - `server/src/args.rs`: argumentos à mão (sem `clap` no binário): `--socket`, `--data-dir`,
    `--tokens-dir` (padrão: a pasta de tokens do app), `--spool-dir` (padrão: `<data-dir>/spool`),
    `--no-embeddings`, `--watcher` (o vigia da wiki, desligado por padrão: nada por relógio),
    `--embed-idle-secs`, `--keep-alive` (não sai sem sessão: testes), `--warm` (abre o store e a
    wiki com as migrações e sai, sem socket nem `--socket`: o aquecimento que o app roda na primeira
    abertura de cada versão; com outro engine na pasta, sai na hora), `--claude-dirs a:b` (as
    pastas de conta da importação no lugar das do app: testes), `--import-delay-ms` (a espera da
    importação depois de subir e de cada SessionStart, padrão 1500, para o briefing ir antes) e os
    que o reinício passa (`--sessions`, `--lock-fd`, `--listen-fd`).
  - `server/src/engine.rs`: store, wiki, embedder, roteador de hooks e de workstream e o MCP
    (streamable HTTP, JSON, sem estado), montados como o serve.rs do cli do upstream os monta, sem
    TCP, web, autenticação multiusuário (o `require_bearer` dele roda sem token, como anônimo) nem
    provedores. Do `HookState`: `record_tool_names` e `index_file_paths` ligados (o nome de cada
    ferramenta, nunca os argumentos; o corpo guarda até 2.000 bytes do que ela devolveu, o padrão
    do upstream, que numa gravação do Claude traz o conteúdo do arquivo; e o caminho relativo ao checkout do arquivo que ela nomeou, para o handoff) e o `profile_notify` com o aviso de "um SessionEnd terminou" que o
    `server/src/handoff.rs` espera (o worker de perfil, para quem ele existe, não roda aqui).
  - `server/src/serve.rs`: o memory.sock (modo 0600) servido pelo axum; uma trava em
    `<data-dir>/engine.lock` garante um engine só por pasta (dois SessionStart juntos não sobem
    dois escritores).
  - `server/src/auth.rs`: conexão de outro uid é fechada (credenciais do socket); todo pedido,
    menos `/healthz`, leva o token da sessão em `X-Cadex-Token`, válido se algum
    `<tokens-dir>/<kitSession>.token` o contém (pasta relida quando chega token novo); sem ele, 401.
  - `server/src/sessions.rs`: o SessionStart traz o pid do `claude` (`pid=`), o kqueue avisa quando
    ele termina e o SessionEnd o tira; sem sessão viva, espera 3 s e sai (fecha o store, apaga o
    socket); sem nenhuma sessão em 10 s depois de subir, sai também. Nenhum timer com sessão viva.
  - `server/src/restart.rs`: depois que o modelo descarrega, sem pedido em andamento, o engine se
    executa de novo (~35 ms em debug) com as sessões vivas, a trava e o socket abertos, e volta ao
    tamanho de parado (o alocador não devolvia os 68 MB). Sem sessão viva, sai em vez de reiniciar.
  - O fim da sessão (fase C):
    - `server/src/hook_body.rs`: middleware que lê uma vez o corpo de cada `/hook` ao vivo e põe
      nele o `occurred_at` da chegada, sempre crescente (o roteador responde 202 e grava numa tarefa
      à parte com a hora em que ela roda: eventos mandados em ordem saíam do store fora de ordem) e,
      no PostToolUse, o arquivo do `server/src/file_claim.rs`. Evento vindo da fila leva a hora em
      que foi reenviado, na ordem da fila. Antes disso, em `/hook`, `/handoff` e `/brief`, põe na
      query os pares do .ai-memory.toml; e num evento de ferramenta aplica o `[capture]`.
    - O .ai-memory.toml do repositório, lido pelo engine porque o `cadex memory-hook` não o lê
      (o cliente do upstream lê): `server/src/marker.rs` (achar e ler: **cópia** do marker.rs do
      cli do upstream, origem no topo, sem rotas da pasta pessoal nem perfis de servidor),
      `server/src/marker_query.rs` (os pares que o `build_marker_query_suffix` do upstream manda;
      o briefing do Cadex nasce ligado e o `workspace` da conta vale mais que o do arquivo) e
      `server/src/capture.rs` (o `CapturePolicy` do upstream: some, só metadados ou fica).
    - `server/src/file_claim.rs`: o campo `_ai_memory_file` que o cliente do upstream manda e o
      `cadex memory-hook` não (o arquivo único que o `file_target` do upstream lê, relativo à pasta
      com `.git` acima do cwd, comparado sem ir ao disco).
    - `server/src/session_facts.rs`: os fatos de uma sessão no store (os prompts, as ferramentas
      por nome, os arquivos que as de edição nomearam, sem repetir, a última mensagem do assistente
      se foi capturada) e o texto do handoff: só fatos, com limites (12 prompts, 40 arquivos).
    - `server/src/handoff.rs`: anota cada SessionEnd que passa e, quando o roteador avisa que um
      terminou, troca o texto do handoff automático do upstream pelo dos fatos: cancela o dele
      (só se ainda aberto) e insere um igual (automático, mesma sessão, pasta, agente e dono), que a
      próxima sessão pega uma vez só. Sessão que o upstream deixa sem handoff fica sem.
  - A memória automática do Claude (fase C), em `<data-dir>/auto/[<conta>/]<chave>/`:
    - `server/src/project_key.rs`: a regra da chave do projeto (a raiz do repositório principal,
      lida dos arquivos `.git`, e os 16 primeiros hex do SHA-256 do caminho), igual à do app
      (`../../../apps/macos/features/memory/MemoryProject.swift`), com o mesmo valor fixado num
      teste de cada lado.
    - `server/src/auto_index.rs`: refaz o MEMORY.md pelos arquivos de tópico (frontmatter `name`,
      `description`): mantém as linhas que existem, menos link para arquivo que sumiu; acrescenta
      as que faltam (as novas por data); acima de 200 linhas ou 25.000 bytes saem as entradas dos
      tópicos mais velhos, nunca linha escrita à mão; relê o arquivo logo antes de gravar e refaz
      se o Claude o mudou no meio; grava com `.tmp` e rename.
    - `server/src/auto_wiki.rs`: cada tópico vira a página `auto/<arquivo>` (kind `fact`, com a
      sessão de origem) no escopo do projeto do project.json que o app grava, pelo
      `memory_write_page` em processo (cada gravação é um commit da wiki); tópico apagado apaga a
      página; só regrava o que mudou (hash por arquivo em `<data-dir>/auto-pages/`).
    - `server/src/auto_watch.rs`: o vigia da pasta auto/ (FSEvents pelo crate `notify`, nada
      por relógio), juntando mudanças por 500 ms; ao subir, acerta todas as pastas uma vez; a
      mudança da própria gravação do MEMORY.md é reconhecida pelo texto e ignorada.
  - `server/src/debug_panic.rs`: só em build de debug e com `CADEX_MEMORY_TEST_PANIC=1` no ambiente
    do engine: a rota `POST /debug/panic` e um hook que aborta no pânico, como o `panic=abort` do
    release (o tokio pegaria o pânico da tarefa e o processo seguiria). O release não tem nem a
    rota nem a leitura da variável.
  - `server/src/spool.rs`: ao subir, reenvia pela rota, em ordem, a fila que o hook deixou
    (`{"v":1,"path":"/hook?…","body":"…"}` por arquivo, nome pela hora), sem passar pelo token;
    apaga o que entrou, separa como `.rejected` o que foi recusado (4xx) e guarda o resto num 5xx.
  - `server/src/sys.rs`: as chamadas que pedem `unsafe` (kqueue, `geteuid`, `fcntl`), só ali.
  - `server/src/lazy_embedder.rs`: o modelo de vetores carregado no primeiro uso e solto depois
    de `--embed-idle-secs` parado (o do upstream carrega ao subir e nunca solta); baixa o modelo
    em segundo plano se faltar, e até lá a busca é só por texto; um download que falhou espera
    10 min para tentar de novo. Avisa carga e descarga ao reinício.
  - `server/src/model_fetch.rs`: o download do modelo com os arquivos e SHA-256 do upstream, mas
    retomando por `Range` num `.part` (o do upstream lê o arquivo inteiro e recomeça); só renomeia o
    que confere. O teste com o modelo de verdade é `cargo test -- --ignored real_model` (rede).
  - `server/src/mcp_scope.rs`: numa chamada do `cadex mcp`, o projeto de reserva (os cabeçalhos
    `x-memory-actor-fallback-*` do upstream) pela pasta que ele manda: o `project` do
    .ai-memory.toml, senão o nome da raiz do repositório principal, como os hooks.
  - `server/src/plugin.rs`: `cadex-memory export-plugin <pasta>`, o plugin do Claude Code com as
    skills do próprio upstream (retrieval, durable-pages, handoff, messaging), tiradas do crate;
    o `make app` e o empacotamento o escrevem.
  - A importação das conversas pelos transcripts do Claude Code (fase C), em segundo plano, uma
    tarefa só, que segura o reinício enquanto grava:
    - `server/src/import.rs`: o middleware que entrega cada SessionStart aceito à tarefa, a fila
      de trabalhos, os limites e `import_all` (escolhe as mais novas no limite, grava as escolhidas
      da mais velha para a mais nova, pula a sessão que o store já tem).
    - `server/src/import_jobs.rs`: o histórico do projeto na primeira sessão (memória sem outra
      sessão, a regra do upstream; 200 sessões, 50 mil eventos; sem a sessão que começa) e, a cada
      subida que não é reinício, as sessões de fora do Cadex dos projetos conhecidos (50 sessões e
      10 mil eventos por subida, nada mexido nos últimos 2 min, ponto de controle por conta).
    - `server/src/import_state.rs`: em `<data-dir>/imports/`, a marca de cada projeto
      (`started`/`done`) e os pontos de controle por conta (outside.json).
    - `server/src/accounts.rs`: as pastas de conta, pela regra do app (`~/.claude`, `~/.claude-*`
      com .claude.json, as contas do Cadex em Application Support), e a chave da conta (a
      workspace com memory.shareAcrossAccounts desligada lê só a sua conta).
    - `server/src/project_paths.rs`: a raiz, as subpastas e as worktrees (`git worktree list`) de
      um projeto; o repositório principal de uma worktree (`--git-common-dir`).
    - `server/src/transcripts.rs`: os `projects/<pasta>/<id>.jsonl` de cada conta, com o cwd lido
      do próprio transcript, repetidas tiradas pelo id; `cadex-memory scan-transcripts --cwd <dir>
      [--claude-dirs a:b]` lista o que a importação leria (diagnóstico).
    - `server/src/replay.rs` e `server/src/replay_capture.rs`: **código copiado do cli do
      upstream** (v3.4.7, backfill.rs e transcript_capture.rs, origem no topo de cada um): o
      transcript, lido pelo `export_transcript` do upstream, vira eventos de hook mandados ao
      `/hook/batch` pela rota, em processo, com a raiz do projeto como cwd e `auto_handoff=0`.
  - `server/tests/smoke.rs`: o engine de ponta a ponta pelo socket (páginas pelo MCP, briefing
    pelo SessionStart, busca), sem modelo e sem vigia; `server/tests/lifecycle.rs`: token, fila,
    saída quando o último `claude` termina, sessões passadas pelo reinício e o `--warm`;
    `server/tests/import.rs`: a importação com transcripts sintéticos em contas falsas (duas contas,
    subpasta, worktree, workspace da conta, uma vez só, sessões de fora, ponto de controle);
    `server/tests/auto_memory.rs`: 4 tópicos gravados juntos dão 4 entradas no MEMORY.md e 4
    páginas, edição e remoção chegam à wiki, o que mudou com o engine fora entra ao subir;
    `server/tests/marker.rs`: o .ai-memory.toml nomeia o projeto, desliga o briefing e tira um
    arquivo da captura, e a chamada MCP com o `X-Memory-Actor-Session-Id` cai no projeto da sessão;
    `server/tests/session_end.rs`: o handoff de uma sessão com 10 edições lista os 10 arquivos, e
    um pânico forçado não perde evento (a fila espera e o engine seguinte a esvazia); ajudas em
    `server/tests/common/mod.rs`.
- O cliente do socket, em Zig (o único código que fala com o memory.sock; o `cadex memory-hook`
  da feature agent-tools chama `memory.zig`):
  - `memory.zig`: a entrada da feature (`hook` e `mcp`).
  - `context.zig`: o que o hook devolve além do briefing, como o cliente do upstream: no
    SessionStart `compact` a âncora (`/recap?mode=anchor`, nunca o handoff; nada num subagente),
    num prompt que começa com "reload context" o `/recap`, no SubagentStart o `/brief`.
  - `mcp_proxy.zig`: as ferramentas `memory_*` do `cadex mcp`: a lista vem do engine (menos as de
    administração e de provedor) e cada chamada vai inteira ao `/mcp` com o
    `X-Memory-Actor-Session-Id` (CLAUDE_CODE_SESSION_ID), a pasta e a workspace da conta; sobe o
    engine se ele não responde.
  - `hook_client.zig`: `cadex memory-hook <evento>`. Sem `CADEX_SESSION_TOKEN`, nada. Lê da env
    `CADEX_MEMORY_SOCKET` (padrão: sockets/memory.sock na pasta do Cadex), `CADEX_MEMORY_DIR`
    (padrão: memory/ na pasta do Cadex), `CADEX_MEMORY_BIN`, `CADEX_SESSIONS_DIR` e `CADEX_MEMORY_WORKSPACE` (a chave da conta, posta pelo
    kit com memory.shareAcrossAccounts desligada; vai como `workspace=` em todo `/hook` e `/handoff`,
    e sem ela tudo cai na workspace `default`). SessionStart: sobe o engine se
    preciso, manda o evento e pede o briefing, tudo em 1 s, e imprime o `additionalContext`. Os
    outros eventos: 200 ms e, sem resposta (ou com 5xx), vão para a fila. Sempre sai 0.
  - `events.zig`: o nome do evento do Claude Code no do engine (o `HookEvent::parse` do upstream)
    e a query (`event`, `agent=claude-code`, `cwd`, `workspace` quando há, `session_id`, `project_strategy=repo-root`,
    `ingest_key` aleatória; `pid` no SessionStart e no SessionEnd; `briefing=1` no `/handoff`).
  - `http.zig`: HTTP/1.1 mínimo no socket Unix (`Connection: close`, tamanho ou chunked), com
    prazo para a troca inteira.
  - `launch.zig`: sobe o `cadex-memory` como o `ensure` do daemon do terminal (SETSID, stdio em
    /dev/null, socket a cada 20 ms), dentro do prazo do SessionStart.
  - `spool.zig`: a fila em `<memory>/spool/` (pasta 0700, arquivo 0600, `.tmp` e rename).
- Perfil de release para tamanho: `opt-level="z"`, LTO completo, `panic="abort"`, sem símbolos;
  candle e gemm em `opt-level=3` (no "z", gravar página com vetor fica 30% mais lento).
- Build: `make memory` (release das duas arquiteturas), `make app` (debug da máquina),
  `make package` (`lipo` em `Contents/Helpers/cadex-memory`, assinatura, cada fatia responde no
  socket, sem endereço de provedor; `../../../apps/macos/packaging/build.sh`).
- **Atualizar o upstream** (sem calendário; quando houver correção que importa ou recurso que
  queremos, no máximo a cada mês):
  1. trocar o commit nas oito linhas `rev` do `server/Cargo.toml` e rodar `cargo update -p`
     de cada crate `ai-memory-*` (o lock segue as versões que o upstream travou);
  2. `make memory` e corrigir no crate do Cadex as mudanças de API (na prova de 2026-11-15, duas
     semanas de upstream deram 3 linhas);
  3. `make memory-upstream-test` no PC;
  4. comparar, entre o commit velho e o novo, o serve.rs, o backfill.rs e o
     transcript_capture.rs do cli do upstream, e o marker.rs e o `build_marker_query_suffix` do
     hook_capture.rs (o que `server/src/marker.rs` e `server/src/marker_query.rs` repetem), e
     trazer ao `server/src/engine.rs` os passos novos de inicialização (o compilador não pega um passo que falta) e ao código copiado (as funções que
     o topo de `server/src/replay.rs` e de `server/src/replay_capture.rs` lista) as mudanças na
     conversão de conversas e no que a captura guarda; anotar a versão nova no topo deles; ver
     também o `file_path_field` do hook.rs do cli (que o `server/src/file_claim.rs` repete) e se o
     `profile_notify` ainda toca a cada SessionEnd (o `server/src/handoff.rs` depende disso, e o
     `server/tests/session_end.rs` falha se parar);
  5. `make check` e `make perf`; anotar o commit novo no topo do `server/Cargo.toml`.

## Como validar
- `make memory-test`: os testes do crate, `server/tests/smoke.rs`, `server/tests/lifecycle.rs`,
  `server/tests/import.rs`, `server/tests/auto_memory.rs`, `server/tests/marker.rs` e
  `server/tests/session_end.rs` (parte do `make check`, em segundos).
- `make memory-eval MODELS=<pasta>`: as 30 perguntas, só texto contra híbrida (`../../../tools/memory_eval.py`).
- `make core-test`: os testes do cliente (eventos, query com e sem workspace, fila, respostas HTTP,
  sem token).
- Na mão, tudo em pastas temporárias: um `.token` em `CADEX_SESSIONS_DIR`, e
  `echo '<json do SessionStart>' | CADEX_SESSION_TOKEN=… CADEX_MEMORY_BIN=… CADEX_MEMORY_DIR=…
  CADEX_MEMORY_SOCKET=… CADEX_SESSIONS_DIR=… core/zig-out/bin/cadex memory-hook SessionStart`.
  Com o engine de debug e `CADEX_MEMORY_TEST_PANIC=1`, `POST /debug/panic` (com o token) o derruba.
- Teste que falha: `CADEX_TEST_ENGINE_LOG=info` no `cargo test` põe o log do engine na saída do
  teste (`server/tests/common/mod.rs`; padrão `warn`). Para pegar corrida, rodar os binários de
  `server/target/debug/deps/` várias vezes em paralelo, sem compilar de novo.
- `make memory-upstream-test` (`upstream_test.sh`): a suíte do upstream para os crates usados, no
  PC; a cada atualização do upstream.
- `make package`: o binário universal assinado, cada fatia respondendo, sem provedor.
