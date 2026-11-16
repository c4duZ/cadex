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
- Outra feature falando com o `cadex-memory` sem passar por esta (fase C: o cliente do socket em
  Zig).

## Como eu quero
- `server/`: o crate `cadex-memory`, workspace própria (perfis e o `[patch]` do zip do upstream
  só valem na raiz). Versão do Rust no `server/rust-toolchain.toml` (a do upstream).
  - `server/src/main.rs`: argumentos à mão (sem `clap` no binário), log em `CADEX_MEMORY_LOG`,
    runtime tokio com 2 threads.
  - `server/src/engine.rs`: store, wiki, embedder, roteador de hooks e de workstream e o MCP
    (streamable HTTP, JSON, sem estado), montados como o serve.rs do cli do upstream os monta, sem
    TCP, web, autenticação nem provedores; servidos pelo axum num socket Unix modo 0600.
  - `server/src/lazy_embedder.rs`: o modelo de vetores carregado no primeiro uso e solto depois
    de `--embed-idle-secs` parado (o do upstream carrega ao subir e nunca solta); baixa o modelo
    em segundo plano se faltar, e até lá a busca é só por texto.
  - `server/src/transcripts.rs`: `cadex-memory scan-transcripts`, as sessões de um projeto em
    várias pastas de conta (base da importação do histórico, fase C).
  - `server/tests/smoke.rs`: o engine de ponta a ponta pelo socket (páginas pelo MCP, briefing
    pelo SessionStart, busca), sem modelo e sem vigia.
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
- `make memory-test`: os testes do crate e o `server/tests/smoke.rs` (parte do `make check`).
- `make memory-upstream-test` (`upstream_test.sh`): a suíte do upstream para os crates usados, no
  PC; a cada atualização do upstream.
- `make package`: o binário universal assinado, cada fatia respondendo, sem provedor.
