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
    abertura de cada versão; com outro engine na pasta, sai na hora) e os que o reinício passa
    (`--sessions`, `--lock-fd`, `--listen-fd`).
  - `server/src/engine.rs`: store, wiki, embedder, roteador de hooks e de workstream e o MCP
    (streamable HTTP, JSON, sem estado), montados como o serve.rs do cli do upstream os monta, sem
    TCP, web, autenticação multiusuário (o `require_bearer` dele roda sem token, como anônimo) nem
    provedores.
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
  - `server/src/spool.rs`: ao subir, reenvia pela rota, em ordem, a fila que o hook deixou
    (`{"v":1,"path":"/hook?…","body":"…"}` por arquivo, nome pela hora), sem passar pelo token;
    apaga o que entrou, separa como `.rejected` o que foi recusado (4xx) e guarda o resto num 5xx.
  - `server/src/sys.rs`: as chamadas que pedem `unsafe` (kqueue, `geteuid`, `fcntl`), só ali.
  - `server/src/lazy_embedder.rs`: o modelo de vetores carregado no primeiro uso e solto depois
    de `--embed-idle-secs` parado (o do upstream carrega ao subir e nunca solta); baixa o modelo
    em segundo plano se faltar, e até lá a busca é só por texto. Avisa carga e descarga ao reinício.
  - `server/src/transcripts.rs`: `cadex-memory scan-transcripts`, as sessões de um projeto em
    várias pastas de conta (base da importação do histórico, fase C).
  - `server/tests/smoke.rs`: o engine de ponta a ponta pelo socket (páginas pelo MCP, briefing
    pelo SessionStart, busca), sem modelo e sem vigia; `server/tests/lifecycle.rs`: token, fila,
    saída quando o último `claude` termina, sessões passadas pelo reinício e o `--warm`; ajudas em
    `server/tests/common/mod.rs`.
- O cliente do socket, em Zig (o único código que fala com o memory.sock; o `cadex memory-hook`
  da feature agent-tools chama `memory.zig`):
  - `memory.zig`: a entrada da feature (`hook`).
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
  4. comparar, entre o commit velho e o novo, o serve.rs e o backfill.rs do cli do upstream e
     trazer ao `server/src/engine.rs` os passos novos de inicialização (o compilador não pega um
     passo que falta) e à importação do histórico as mudanças na conversão de conversas;
  5. `make check` e `make perf`; anotar o commit novo no topo do `server/Cargo.toml`.

## Como validar
- `make memory-test`: os testes do crate, `server/tests/smoke.rs` e `server/tests/lifecycle.rs`
  (parte do `make check`, em segundos).
- `make core-test`: os testes do cliente (eventos, query com e sem workspace, fila, respostas HTTP,
  sem token).
- Na mão, tudo em pastas temporárias: um `.token` em `CADEX_SESSIONS_DIR`, e
  `echo '<json do SessionStart>' | CADEX_SESSION_TOKEN=… CADEX_MEMORY_BIN=… CADEX_MEMORY_DIR=…
  CADEX_MEMORY_SOCKET=… CADEX_SESSIONS_DIR=… core/zig-out/bin/cadex memory-hook SessionStart`.
- `make memory-upstream-test` (`upstream_test.sh`): a suíte do upstream para os crates usados, no
  PC; a cada atualização do upstream.
- `make package`: o binário universal assinado, cada fatia respondendo, sem provedor.
