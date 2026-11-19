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
    provedores; sem as rotas `/messages*` da 3.5.0 (só o comando `ai-memory message` as usa; as
    ferramentas `memory_message_*` do MCP seguem) e com o `[routing] brief_on_project_change`
    desligado, o padrão do upstream. Do `HookState`: `record_tool_names` e `index_file_paths` ligados (o nome de cada
    ferramenta, nunca os argumentos; o corpo guarda até 2.000 bytes do que ela devolveu, o padrão
    do upstream, que numa gravação do Claude traz o conteúdo do arquivo; e o caminho relativo ao checkout do arquivo que ela nomeou, para o handoff) e o `profile_notify` com o aviso de "um SessionEnd terminou" que o
    `server/src/handoff.rs` espera (o passo de perfil do agente de memória roda depois do SessionEnd,
    pelo `server/src/agent/`, só com o agente ligado).
  - `server/src/serve.rs`: o memory.sock (modo 0600) servido pelo axum; uma trava em
    `<data-dir>/engine.lock` garante um engine só por pasta (dois SessionStart juntos não sobem
    dois escritores).
  - `server/src/auth.rs`: conexão de outro uid é fechada (credenciais do socket); todo pedido,
    menos `/healthz`, leva o token da sessão em `X-Cadex-Token`, válido se algum
    `<tokens-dir>/<kitSession>.token` o contém (pasta relida quando chega token novo); sem ele, 401.
  - `server/src/sessions.rs`: o SessionStart traz o pid do `claude` (`pid=`), e o `POST
    /workstream/runs?pid=` traz o do `cadex-memory run` (o engine fica de pé até o launcher importar
    e fechar a execução, depois do fim do agente); o kqueue avisa quando ele termina e o SessionEnd o tira; sem sessão viva, espera 3 s e sai (fecha o store, apaga o
    socket); sem nenhuma sessão em 10 s depois de subir, sai também. Nenhum timer com sessão viva.
    O SessionStart também nomeia a sessão (`session_id=`, só id simples): o registro sabe quais
    sessões estão vivas (`live_sessions`), para a prévia do briefing (plano 35 H), e o reinício as
    passa junto dos pids (`--sessions 12:<id>,34`).
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
      `server/src/core_brief.rs` (plano 35 E: pedido o briefing e sem página de núcleo do projeto,
      fixada, _rules/ ou _slots/, o pedido segue com `briefing=0`; dentro da camada do marcador),
      `server/src/marker_query.rs` (os pares que o `build_marker_query_suffix` do upstream manda;
      o briefing só com o marcador pedindo, como no upstream, desde o plano 35 B; numa worktree sem
      marcador próprio vale o do checkout principal, `settings_marker`, porque o arquivo que o Cadex cria
      só chega a uma worktree irmã depois do commit; o `workspace` da conta vale mais que o do arquivo;
      desde a 3.5.0 também `[retrieval] default_result_limit` e `min_relevance`, vazios quando o
      arquivo não os tem; o engine não tem reranker, então um `min_relevance` faz o `memory_query` do
      projeto ser recusado, como no upstream, e o app não oferece a chave) e
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
  - A memória desligada (plano 35 I; spec "Desligar"), o interruptor que o upstream não tem:
    `server/src/off.rs` lê o `<data-dir>/off-projects.json` que o app grava (as raízes dos projetos
    desligados; relido só quando o mtime ou o tamanho muda; uma pasta é desligada sob uma raiz ou
    quando o checkout principal dela, lido dos arquivos por `server/src/project_key.rs`, é uma) e as
    marcas `<data-dir>/paused/<sessão>` (só id simples); o middleware `gate`, por fora de todos os
    vigias (importação, sessões, agente, handoff, manutenção), responde 202 sem gravar a um `/hook`
    de pasta desligada ou de sessão pausada e 204 a `/handoff`, `/brief`, `/recap` e
    `/cadex/consolidate` delas; a fila e a importação passam por ele também.
    `server/src/off_search.rs`, no `/mcp`, com algum projeto desligado: a chamada que nomeia um
    (`project`, ou um item de `scopes`) recebe um erro da ferramenta sem chegar ao upstream, e da
    resposta saem os itens de lista com o nome dele (`project_name`, como os `global_hits`, ou
    `project`), também no JSON do `text`; pelo nome, o único que a resposta traz. A importação
    (`server/src/import_jobs.rs`) não traz o histórico de um projeto desligado (sem marcar: religado,
    vem) nem as sessões de fora dele (essas nunca: o ponto de controle passa); o agente
    (`server/src/agent/jobs.rs`) não roda trabalho de projeto desligado nem de sessão pausada.
  - `server/src/mcp_scope.rs`: numa chamada do `cadex mcp`, o projeto de reserva (os cabeçalhos
    `x-memory-actor-fallback-*` do upstream) pela pasta que ele manda: o `project` do
    .ai-memory.toml, senão o nome da raiz do repositório principal, como os hooks.
  - Consolidação na sessão (fase F): `server/src/consolidate_prompt.rs`, a rota
    `GET /cadex/consolidate?session_id&reason&cwd&workspace`: o pedido que faz o Claude da sessão
    consolidar, com as regras do próprio upstream (`BATCH_SYSTEM_PROMPT` do crate de consolidação,
    até o contrato de saída JSON; as convenções de caminho, `tier` e `kind` copiadas do
    `batch_request_plan`), a workspace e o projeto da pasta (o `memory_write_pages_batch` não tem
    escopo padrão) e as ferramentas no lugar do JSON. O consolidador do upstream pede um provedor de
    IA, que o Cadex não tem.
  - A manutenção (fase F), por evento e nunca por relógio: `server/src/maintenance.rs` (ao subir e
    a cada SessionEnd ao vivo, depois de `--import-delay-ms`, na mesma fila da importação e segurando
    o reinício), `server/src/maintenance_jobs.rs` (**cópia** dos passos do agendador do serve.rs do
    upstream, origem no topo: a varredura de esquecimento, a de projetos vazios e o lint por regras,
    no máximo uma vez por dia cada; a geração de vetores que faltam, ao subir e no máximo de hora em
    hora) e `server/src/maintenance_state.rs` (a hora da última rodada de cada um em
    `<data-dir>/maintenance/`; rodada que falha não conta). Os padrões do upstream valem, inclusive o
    que apaga: página com `expires_at` vencido, página episódica fria (~80 dias sem leitura, as
    sessions/ incluídas, arquivo removido e linha marcada), marca de remoção com mais de 180 dias,
    projeto vazio com mais de 7 dias; sessão parada 48 h é fechada. Fora (pedem IA): o auto-improve,
    o dream, o worker de consolidação e o de perfil.
  - O agente de memória (fase G, ADR 0029), em `server/src/agent/`: o provedor de IA do upstream
    (`LlmProvider`) feito com o `claude -p` da conta, para o consolidador, o perfil, o experience, o
    auto-improve, o dream e o bootstrap do próprio upstream rodarem sem mudança.
    - `server/src/agent/claude_cli.rs`: a chamada provada em 2026-11-16 (`claude -p --model haiku
      --max-budget-usd <por chamada> --no-session-persistence --tools "" --strict-mcp-config
      --mcp-config <vazio> --settings <disableAllHooks> --system-prompt … --output-format json`, o
      pedido no stdin, numa pasta vazia, sem CLAUDECODE/CLAUDE_CODE_*, com o CLAUDE_CONFIG_DIR da
      conta do projeto; nunca `--bare`, que pula o keychain do login); sem endereço de provedor.
    - `server/src/agent/provider.rs` (o `LlmProvider`, que confere o teto antes de cada chamada e
      registra depois), `server/src/agent/config.rs` (o agent.json que o app grava, lido a cada
      trabalho; sem arquivo, desligado), `server/src/agent/ledger.rs` (`<data-dir>/agent/ledger.jsonl`,
      0600: tipo, projeto, custo, versão do Claude Code, modelo, `call` com o arquivo da chamada; no
      auto-improve, `session` é a sessão revisada e `trigger` a que terminou e disparou o trabalho,
      plano 35 G; o gasto do dia local), `server/src/agent/audit.rs` (plano 35 D: o pedido e a resposta de cada
      chamada em `<data-dir>/agent/calls/<hora UTC>-<tipo>-<id>.json`, sem ambiente, e o briefing de
      cada sessão em `<data-dir>/agent/briefings/<sessão>.md`; pasta 0700, arquivo 0600, temporário e
      rename; 30 dias e 500 arquivos por pasta, podados a cada gravação),
      `server/src/agent/briefings.rs` (o middleware do `/handoff` com `session_id` e sem `claim=0`:
      guarda a resposta depois de respondê-la, numa thread à parte),
      `server/src/agent/queue.rs` (um trabalho por vez, sem repetir, pausa; segura o engine e o
      reinício enquanto há trabalho), `server/src/agent/jobs.rs` (sessão sem prompt e sem ferramenta, pelo
      `session_has_substantive_observation` do upstream, não roda nada, só uma linha sem custo no
      ledger: plano 35 C; no SessionEnd ao vivo: consolidar
      pelo caminho do worker do upstream, que pula a página que o Claude da sessão já consolidou
      (`consolidated_by: agent`), o perfil, o experience a cada 5 sessões, o auto-improve no máximo
      de hora em hora por projeto, com propostas pendentes quando memory.requireApproval; no
      PostCompact, consolidar o que houve; e um dream se não há sessão viva e o Mac está parado há
      10 min), `server/src/agent/improve.rs` (**cópia** do agendador do auto-improve do upstream,
      por projeto), `server/src/agent/cited_paths.rs` (plano 35 G, não é do upstream: antes de
      preparar as propostas, a que cita caminhos e nenhum deles existe na raiz principal do projeto,
      nem como fim de um arquivo do `git ls-files`, é tirada, com uma linha sem custo no ledger e
      um aviso na execução; `.md` só conta como achado, pode ser página da wiki), `server/src/agent/dream.rs` (o dream e o tempo parado do Mac pelo `ioreg`; o
      automático para quando o dono volta), `server/src/agent/bootstrap.rs` (a estimativa sem
      chamar o Claude e o bootstrap do upstream sobre as sessões do projeto) e
      `server/src/agent/routes.rs` (`GET /cadex/agent/status`, `POST /cadex/agent/pause`,
      `/cadex/agent/run-dream`, `/cadex/agent/bootstrap[?dry_run=1]`; o bootstrap roda mesmo com o
      agente desligado, com o mesmo teto) e `server/src/agent/mod.rs`.
  - A página Memory (fase H), em `server/src/page/`, rotas `/cadex/memory/*`: `server/src/page/overview.rs`
    (projeto, pasta da wiki, modelo, contagens e o histórico importado por conta, contado de agora em
    diante em `<data-dir>/imports/counts.json`, já que o store não guarda a conta de uma sessão),
    `server/src/page/briefing.rs` e `server/src/page/handoff_text.rs` (o que a próxima sessão recebe,
    sem pegar o handoff: o `/handoff` com `claim=0` pela própria rota, o aviso de handoff trocado pelo
    texto dele com o renderizador do upstream **copiado**, e o corte de 9.800 caracteres como o
    upstream; igual byte a byte ao SessionStart seguinte, no teste; plano 35 H: se o snapshot de
    sessão não terminada do upstream é de uma sessão viva, a prévia pede de novo com `recovery=0`,
    para não mostrar a sessão em que o dono está, ou uma paralela rodando, como cortada), `server/src/page/pages.rs`
    (gravar e apagar como as ferramentas, com commit; sem frontmatter, a página guarda o que tinha),
    `server/src/page/reindex.rs` (o arquivo editado no disco entra pelo `Wiki::reindex_page`, com a
    varredura **copiada** do vigia do upstream, e um commit; arquivo apagado no disco não apaga a
    página, como no upstream) e `server/src/page/proposals.rs` (as propostas pendentes, até 200, e
    aprovar ou recusar pelo caminho do "pending-writes" do admin do upstream, com commit na aprovação).
    `server/src/projects_file.rs`: o `<data-dir>/projects.json` (workspace, projeto, raiz, pasta da
    wiki), atualizado no SessionStart, na gravação de página e no overview, para a página mostrar a
    árvore com o engine parado.
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
    - `server/src/history_review.rs` (plano 35 G): o histórico importado nunca é revisado sozinho
      pelo auto-improve, como no upstream: ao subir, o `initialize_auto_improve_scheduler_scopes`
      dele (o passo do serve.rs); e cada sessão que uma importação grava (o histórico e as de fora
      do Cadex) é reivindicada na hora (`claim_auto_improve_scheduler_session`), o que a tira da
      fila sem mexer na marca d'água (o upstream não tem chamada pública que a mova, e movê-la
      levaria junto as sessões ao vivo que esperam a vez).
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
      upstream** (v3.4.7, backfill.rs e transcript_capture.rs, iguais na 3.5.0; origem no topo de cada um): o
      transcript, lido pelo `export_transcript` do upstream, vira eventos de hook mandados ao
      `/hook/batch` pela rota, em processo, com a raiz do projeto como cwd e `auto_handoff=0`.
  - Continuar em outro agente (fase E), `cadex-memory run`, em `server/src/run/`: **cópia do
    `ai-memory run`** do cli do upstream (run.rs, jail_folders.rs e transcript_capture.rs; as
    funções copiadas listadas no topo de cada arquivo), com as mesmas opções (`--workspace`,
    `--project`/`--project-id`, `--workstream`/`--new`, `--executable`, `--yolo`, `--jail[=…]`,
    `--no-jail`, `--jail-map`, `--jail-rw-map`, `--fresh`, `--force-unlock`, `--no-exit-prompt`,
    `--require-server`, `--profile`, `--env`, `--env-file`), os mesmos agentes e nomes (Claude,
    `claude-*`, Codex, OpenCode, Pi, Crush, OMP, Kimi, Command Code, Kiro, Grok, Antigravity, Copilot)
    e a lógica deles no crate de workstream. Do Cadex: `--socket`, `--data-dir` e as palavras do kit
    por agente (`--claude-kit-arg`, `--codex-kit-arg`, postas depois do plano montado, só as do agente
    que roda). Lê o token e o socket como o hook (CADEX_SESSION_TOKEN, CADEX_MEMORY_SOCKET,
    CADEX_MEMORY_DIR, CADEX_SESSIONS_DIR, CADEX_MEMORY_WORKSPACE, CADEX_MEMORY_BIN para subir o
    engine); quem o chama é o `cadex continue` da feature agent-tools.
    - A linha de comando: `server/src/run/args.rs`, `server/src/run/choice.rs` (nomes dos agentes),
      `server/src/run/wrapper.rs` (opções digitadas depois do agente), `server/src/run/profiles.rs` (o
      `[run]` do config.toml do próprio ai-memory, **só lido**) e `server/src/run/child_env.rs` (perfil,
      `--env-file`, `--env`, achar o executável).
    - Antes do engine: `server/src/run/local.rs`, `server/src/run/auto.rs` (sem agente: a sessão mais
      nova do checkout) e `server/src/run/opencode.rs` (o dialeto do OpenCode; o motor do Kiro).
    - Uma execução: `server/src/run/flow.rs`, `server/src/run/launch.rs`, `server/src/run/adopt.rs`
      e `server/src/run/picker.rs` (adotar uma sessão nativa, com menu num terminal),
      `server/src/run/attach.rs` (`claude attach` de uma sessão que roda em segundo plano),
      `server/src/run/harness_ctx.rs` (o pacote do workstream do Crush e do Grok),
      `server/src/run/store_record.rs`, `server/src/run/plan.rs`, `server/src/run/history.rs` (o
      dossiê do agente anterior, 0600, apagado no fim), `server/src/run/server.rs` e
      `server/src/run/uds_http.rs` (preparar com a espera da trava, batimento de 30 s, cancelar,
      fechar, pelo memory.sock).
    - Depois do agente: `server/src/run/after.rs`, `server/src/run/import.rs`,
      `server/src/run/ledger_capture.rs` (o `[capture]` aplicado à conversa) e
      `server/src/run/hookless.rs` (fim de sessão de quem não tem SessionEnd; sem a rota
      `/admin/open-sessions` do upstream, manda o fim direto ao `/hook/batch`).
    - Sem o engine: `server/src/run/offline.rs` (o agente roda mesmo assim, com aviso; com
      `--require-server`, não), `server/src/run/journal.rs` e `server/src/run/recover.rs` (o diário em
      `<data-dir>/run/`, refeito no próximo `run` que acha o engine; o upstream pede `ai-memory recover`
      à mão).
    - `--yolo` e o ai-jail: `server/src/run/yolo.rs`, `server/src/run/jail.rs`,
      `server/src/run/jail_checklist.rs`, `server/src/run/jail_choices.rs`, `server/src/run/jail_exec.rs`
      e `server/src/run/jail_folders.rs`. Dentro da jaula o launcher chega ao engine pelo arquivo do
      memory.sock mapeado (`--rw-map`) e pelas variáveis passadas por `--env` (o ai-jail limpa o
      ambiente); só a pasta `<data-dir>/run` vai junto, nunca a pasta de sockets (a do daemon do
      terminal ficaria exposta).
    - `server/src/run/exit_prompt.rs`: o menu depois de uma sessão (outro agente, de novo, sair).
    - Tudo o que o launcher guarda (diário, registros de sessão, respostas da jaula) fica em
      `<data-dir>/run/`, nunca nas pastas do ai-memory.
    - Fora, de propósito: a instalação automática de hooks e MCP do upstream (`--no-autowire` é
      aceita e não faz nada): ela grava na configuração dos agentes do dono, que o Cadex nunca toca; o
      kit faz isso para o Claude (e o MCP do Codex). Também fora o reparo de projeto dividido e o
      registro de projetos (só acontecem num servidor compartilhado que roteia pelo remote do git), a
      escolha entre projetos de mesmo nome (multiusuário) e o seletor de pastas em tela da jaula
      (crossterm não está no lock: `f` manda usar `--jail-map`). AI_MEMORY_HOOK_URL nunca vai ao
      agente (não há TCP).
  - `server/tests/smoke.rs`: o engine de ponta a ponta pelo socket (páginas pelo MCP, briefing
    pelo SessionStart, busca), sem modelo e sem vigia; `server/tests/lifecycle.rs`: token, fila,
    saída quando o último `claude` termina, sessões passadas pelo reinício e o `--warm`;
    `server/tests/import.rs`: a importação com transcripts sintéticos em contas falsas (duas contas,
    subpasta, worktree, workspace da conta, uma vez só, sessões de fora, ponto de controle);
    `server/tests/auto_memory.rs`: 4 tópicos gravados juntos dão 4 entradas no MEMORY.md e 4
    páginas, edição e remoção chegam à wiki, o que mudou com o engine fora entra ao subir;
    `server/tests/marker.rs`: o .ai-memory.toml nomeia o projeto, desliga o briefing e tira um
    arquivo da captura, e a chamada MCP com o `X-Memory-Actor-Session-Id` cai no projeto da sessão;
    `server/tests/run.rs`, `server/tests/run_agents.rs` e `server/tests/run_launch.rs` (agentes
    falsos e um ai-jail falso em `server/tests/common/bench.rs`): Claude, depois Codex no mesmo workstream com o dossiê do Claude (0600,
    apagado depois), depois Claude de novo retomando a sessão dele com o dossiê do Codex; um segundo
    launcher no workstream ocupado é recusado depois da espera curta; o engine fica de pé do fim do
    agente até o `/finish`; sem agente, a sessão mais nova continua; `--yolo` sem terminal põe a
    flag sem perguntar; sessão do Claude em segundo plano vira `claude attach`; o Grok recebe o pacote
    como `--rules`; o dialeto do OpenCode pela versão; perfil, `--env-file` e `--env` na ordem certa;
    sem engine o agente roda e o próximo `run` recupera; `--jail` roda de novo dentro do ai-jail e
    alcança o engine;
    `server/tests/maintenance.rs`: um SessionEnd varre o vencido e o frio e um segundo no mesmo dia
    não; a subida varre o que venceu; sem evento, nada; o SessionStart responde rápido durante a
    varredura;
    `server/tests/agent.rs` (um `claude` falso em `server/tests/common/agent.rs`): desligado, nada; ligado,
    o SessionEnd consolida pelo falso, com a linha de comando e o ambiente exatos da prova; sessão
    vazia não chama nada; pausa e
    teto; a estimativa sem chamar e o bootstrap com o agente desligado; propostas pendentes com
    aprovação; o dream depois de um SessionEnd só com o Mac parado (as sessões de teste em
    `server/tests/common/agent.rs`); `server/tests/agent_audit.rs`: o SessionEnd deixa o pedido e a
    resposta de cada chamada, 0600, apontados pelo ledger; o SessionStart deixa o briefing que
    recebeu, e a prévia (`claim=0`) não deixa nada (a poda é teste de unidade em `server/src/agent/audit.rs`);
    `server/tests/agent_guard.rs` (plano 35 G): sessões de fora importadas não são revisadas; a
    proposta que só cita caminhos que o repositório não tem é recusada, com a linha no ledger, e a
    que cita um arquivo dele fica pendente; a linha do auto-improve nomeia a sessão revisada, com a
    que terminou em `trigger`;
    `server/tests/memory_page.rs`: a sessão viva fora do snapshot da prévia e de volta quando o
    `claude` dela sai (plano 35 H); overview com o engine de pé e parado, o briefing igual ao do
    SessionStart seguinte e sem pegar o handoff, gravar e apagar página com commit, o reindex de um
    arquivo editado no disco, propostas aprovadas e recusadas, o projects.json;
    `server/tests/memory_off.rs` (plano 35 I): um projeto desligado não grava nem chama o agente,
    sai da busca em todos e a chamada que o nomeia é recusada, e o gravado antes fica; uma sessão
    pausada não grava mais nada nem chama o agente ao terminar; `server/tests/import.rs` também: as
    sessões de fora de um projeto desligado não entram;
    `server/tests/session_end.rs`: o handoff de uma sessão com 10 edições lista os 10 arquivos, e
    um pânico forçado não perde evento (a fila espera e o engine seguinte a esvazia); ajudas em
    `server/tests/common/mod.rs`.
- O cliente do socket, em Zig (o único código que fala com o memory.sock; o `cadex memory-hook`
  da feature agent-tools chama `memory.zig`):
  - `memory.zig`: a entrada da feature (`hook` e `mcp`).
  - `consolidate.zig` (fase F): os marcos da consolidação na sessão, cada um uma vez por sessão
    (marca em `<memory>/consolidate/<sessão>`): o contexto passou de CADEX_MEMORY_CONSOLIDATE_AT (do
    arquivo da sessão que o `cadex statusline` grava em `<usage>/sessions/`) ou a tarefa ficou
    pronta (o pedido que o app deixa em `<memory>/consolidate/requests/`); no Stop, sem
    `stop_hook_active`, o hook responde `decision: "block"` com o texto do `/cadex/consolidate`. Um
    prompt que começa com "Consolidate this session into the project memory" (o que o
    memory.consolidate-now cola) recebe o mesmo texto ao lado. Sem a variável, nada.
  - `agent_client.zig` (fases G e H): `cadex memory-agent <ação> [--cwd D] [--workspace W]`, o
    caminho do app até a memória (o app roda o comando e lê uma linha JSON; não fala com o socket):
    o token é o CADEX_SESSION_TOKEN que o app dá, do arquivo dele na pasta de tokens. Ações: do
    agente, `status`, `pause`, `resume`, `dream`, `bootstrap [--dry-run]`; da página Memory,
    `overview`, `briefing` (texto puro), `write-page --path P` (corpo no stdin), `delete-page --path
    P`, `reindex`, `proposals`, `approve --id`, `reject --id`. `status` e `overview` nunca sobem o
    engine (fora: `{"running":false}`); os outros sobem. Erro: saída 1 e `{"error":…}`; uso: 2.
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
    e sem ela tudo cai na workspace `default`). Uma sessão com a marca `<memória>/paused/<id>`
    (o app a deixa ao pausar a memória da conversa, plano 35 I) não manda nem imprime nada, em
    nenhum evento. SessionStart: sobe o engine se
    preciso, manda o evento e pede o briefing, tudo em 1 s, e imprime o `additionalContext`. Os
    outros eventos: 200 ms e, sem resposta (ou com 5xx), vão para a fila. Sempre sai 0.
  - `events.zig`: o nome do evento do Claude Code no do engine (o `HookEvent::parse` do upstream;
    o StopFailure, turno cortado por erro da API, vai como `stop`, como o plugin do upstream manda, e
    não pede a consolidação na sessão, que o Claude Code ignora nesse hook)
    e a query (`event`, `agent=claude-code`, `cwd`, `workspace` quando há, `session_id`, `project_strategy=repo-root`,
    `ingest_key` aleatória; `pid` no SessionStart e no SessionEnd; sem `briefing=1` no `/handoff` desde o plano 35 B: o briefing vem do .ai-memory.toml, que o app cria em todo projeto) e,
    numa execução gerenciada (fase E), `managed_run` (o AI_MEMORY_RUN_ID) no `/hook` e no `/handoff`
    e `auto_handoff=0` (AI_MEMORY_AUTO_HANDOFF falso) no `/hook`, como o cliente do upstream.
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
  3. `make memory-upstream-test` no PC (sem o PC, o mesmo `cargo test` roda num clone no Mac: na
     3.5.0, em 2026-11-19, 5.029 testes em 18 min com 10 núcleos; o `target` dele, apagado depois);
  4. comparar, entre o commit velho e o novo, o serve.rs, o backfill.rs e o
     transcript_capture.rs do cli do upstream, o run.rs (as funções que o topo de cada arquivo de
     `server/src/run/` lista), e o marker.rs e o `build_marker_query_suffix` do
     hook_capture.rs (o que `server/src/marker.rs` e `server/src/marker_query.rs` repetem), e
     trazer ao `server/src/engine.rs` os passos novos de inicialização (o compilador não pega um passo que falta) e ao código copiado (as funções que
     o topo de `server/src/replay.rs` e de `server/src/replay_capture.rs` lista) as mudanças na
     conversão de conversas e no que a captura guarda; anotar a versão nova no topo deles; ver
     também o `file_path_field` do hook.rs do cli (que o `server/src/file_claim.rs` repete) e se o
     `profile_notify` ainda toca a cada SessionEnd (o `server/src/handoff.rs` depende disso, e o
     `server/tests/session_end.rs` falha se parar);
  5. `make check` e `make perf`; anotar o commit novo no topo do `server/Cargo.toml`.
- O painel web do upstream só como referência (plano 40 A, `../../../docs/plans/40-memory-panel.md`):
  `server/examples/web_reference.rs` monta o ai-memory-web (dependência só de desenvolvimento, nunca
  no binário) sobre a cópia de uma pasta da memória, em 127.0.0.1, com quem olha como o dono (root);
  `cargo run --example web_reference -- <cópia> [porta]`. Nunca sobre a pasta de verdade: o crate
  migra o banco ao abrir.
- A memória falsa e a paridade com o painel do upstream (plano 40 A2):
  - `server/tests/panel/seed.rs` e `server/tests/panel/seed_queues.rs`: o seed, só pelas gravações do
    upstream (writer do Store, `Wiki::write_page`, `send_agent_message`, workstream, auto-improve),
    como a suíte do ai-memory-web semeia: workspace `default` com `cadex` (4 sessões, 1 aberta, 15
    eventos, 5 páginas, uma com 2 versões, links, páginas de regra e de slot, handoff, 3 mensagens com 2
    na fila, um workstream, 2 propostas), `site` (1 sessão, página com link para o `cadex`, 1
    proposta), `_global` (1 página) e `empty`. Ids e `occurred_at` fixos; o que o upstream carimba
    com "agora" (versões, fim de sessão, mensagens) varia, então os testes comparam contagens e ordem.
    `cargo run --example panel_seed -- <pasta vazia>` (`server/examples/panel_seed.rs`) escreve o
    mesmo seed para os prints e os testes do app.
  - `server/tests/panel/mod.rs`: o painel do upstream montado como no `web_reference` e as listas
    de rotas GET do inventário (`../../../docs/research/memory-panel-screens.md`);
    `server/tests/panel/html.rs`: tirar números, listas e atributos do HTML dele (texto, pedaços por
    marcador, `<strong>`, `data-*`), para a fase B comparar com o nosso JSON;
    `server/tests/panel/snapshot.rs`: o hash de cada arquivo da pasta (menos `-shm`, as marcas de
    leitura do SQLite), tirado com o store fechado pelo `Store::close` (fila drenada e WAL no arquivo
    principal); o ponto de partida é abrir e fechar sem pedido até nada mudar (o `PRAGMA optimize`
    do `Store::open` acrescenta uma linha de `sqlite_stat1` na segunda abertura).

## Como validar
- `make memory-test`: os testes do crate, `server/tests/smoke.rs`, `server/tests/lifecycle.rs`,
  `server/tests/import.rs`, `server/tests/auto_memory.rs`, `server/tests/marker.rs`,
  `server/tests/run.rs`, `server/tests/run_agents.rs`, `server/tests/run_launch.rs`, `server/tests/maintenance.rs`, `server/tests/agent.rs`, `server/tests/agent_audit.rs`, `server/tests/agent_guard.rs`, `server/tests/memory_page.rs`, `server/tests/memory_off.rs`, `server/tests/session_end.rs` e `server/tests/panel_parity.rs` (o painel do upstream sobre o seed: toda tela e rota `/api/v1` responde 200 com os números do seed, e ler tudo deixa a pasta igual byte a byte) (parte do `make check`, em segundos).
- `make memory-eval MODELS=<pasta>`: as 30 perguntas, só texto contra híbrida (`../../../tools/memory_eval.py`).
- `make core-test`: os testes do cliente (eventos, query com e sem workspace, fila, respostas HTTP,
  sem token, a sessão pausada que não manda nem enfileira nada).
- Na mão, tudo em pastas temporárias: um `.token` em `CADEX_SESSIONS_DIR`, e
  `echo '<json do SessionStart>' | CADEX_SESSION_TOKEN=… CADEX_MEMORY_BIN=… CADEX_MEMORY_DIR=…
  CADEX_MEMORY_SOCKET=… CADEX_SESSIONS_DIR=… core/zig-out/bin/cadex memory-hook SessionStart`.
  Com o engine de debug e `CADEX_MEMORY_TEST_PANIC=1`, `POST /debug/panic` (com o token) o derruba.
- Teste que falha: `CADEX_TEST_ENGINE_LOG=info` no `cargo test` põe o log do engine na saída do
  teste (`server/tests/common/mod.rs`; padrão `warn`). Para pegar corrida, rodar os binários de
  `server/target/debug/deps/` várias vezes em paralelo, sem compilar de novo.
- `make memory-upstream-test` (`upstream_test.sh`): a suíte do upstream para os crates usados e
  para o ai-memory-web (a referência do painel), no PC; a cada atualização do upstream.
- `make package`: o binário universal assinado, cada fatia respondendo, sem provedor.
- `make perf` (`../../../tools/perf/plan22.py`): o engine do pacote parado com sessão (até 25 MB, CPU
  zero), com o modelo (pico até 400 MB) e de volta ao parado depois do reinício sozinho, e uma wiki
  de 2 mil páginas com 500 eventos (hook, briefing e o `cadex memory-hook` inteiro no tempo medido);
  o app parado sem nenhum `cadex-memory` no `ps`. O modelo vem de `CADEX_PERF_MODELS` (a pasta com
  all-MiniLM-L6-v2/) ou o engine o baixa numa pasta temporária.
