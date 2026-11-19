# Estudo — o ai-memory do upstream contra o que o Cadex importou

Fase A do plano 35 (`docs/plans/35-memory-that-gets-it-right.md`), escrita em 2026-11-19. Para o
dono ler e aprovar antes das fases B a H. Só estudo: nenhuma linha de código mudou.

**Fontes.** O upstream (github.com/akitaonrails/ai-memory) clonado e lido em dois commits: o que o
Cadex fixa, fa0ec25 (v3.4.7, `core/features/memory/server/Cargo.toml`), e o alvo, 411d90d (v3.5.0
mais um commit de docs). Os caminhos do upstream e os nomes da wiki (docs/…, crates/…, _rules/,
_slots/) vão sem crase: não são deste repositório. Do lado do Cadex, o crate `cadex-memory`, o
cliente em Zig e a feature do app. Dos dados do dono, só leitura (o banco aberto com
`immutable=1`, nada escrito): a pasta Application Support/Cadex/memory (projects.json, agent.json,
agent/ledger.jsonl, agent/cadence.json, a wiki do `bkdg-center` e as tabelas `sessions` e
`auto_improve_*` do memory.sqlite), mais o `git` dos checkouts do `bkdg`. Nenhum build nem teste
do upstream rodou.

**Onde o estudo corrige o handoff de 18/11.** Duas afirmações do handoff não se confirmam no
Cadex: (1) "o backfill não é revisado sem rodar à mão": no Cadex ele **está** sendo revisado
sozinho, do mais velho para o mais novo (ponto 4); (2) "sessão vazia gera página e chama o agente
porque é o upstream": o upstream já não faz nada com sessão vazia; quem faz é o agente do Cadex
(ponto 5 e a seção "Sessão vazia").

## Resumo

| ponto | upstream | Cadex | veredito | fase |
|---|---|---|---|---|
| 1. Marcador | Nasce só por `ai-memory project init` (interativo, nunca sobrescreve, grava `workspace` e `project`); o doc manda fazer commit. Sem ele: workspace `default`, nome pelo remote, briefing desligado | Nasce só quando a tela do projeto muda algo do padrão; o padrão da tela já tem briefing ligado | importamos errado (a criação); divergência sem motivo forte (o padrão) | B |
| 2. Briefing | Desligado; liga por repositório em `[briefing]`. Aviso e rodapé são texto fixo do upstream | `briefing=1` em todo SessionStart; o aviso cita um arquivo que não existe | importamos errado (o padrão); o rodapé que mente sem páginas fixadas é erro dele | B, E |
| 3. Projeto da sessão | A pasta onde a sessão começou; `cd` não move a sessão (só observações, em `follow-cwd`). Nome pelo caminho do remote (v3) | Mesma regra de escopo. Nome pela raiz do repositório principal; worktree irmã cai no mesmo projeto | escopo igual; nome é divergência de propósito, escrita na spec | B (fixar `project` no marcador) |
| 4. Auto-improve | Agendador de hora em hora, sessões com 10 min, marca d'água ao subir: histórico nunca revisado; SessionEnd não dispara; aprova sozinho | Roda a cada SessionEnd (até vazia); marca d'água criada tarde, 0 no Center: o backfill inteiro entra na fila, do mais velho ao mais novo | importamos errado | C, G, D |
| 5. Páginas de sessão | Sem IA por padrão (synth.rs: título = primeiro prompt, corpo = lista). A consolidação por IA no SessionEnd é opcional, desligada. O histórico se destila pelo bootstrap | Sessão ao vivo: consolidada pelo haiku (mais que o upstream). Backfill: a página sem IA, como no upstream | igual ao upstream; não é erro | G (bootstrap com aprovação) |
| 6. Snapshot de recuperação | De propósito: a última sessão sem SessionEnd, menos a que recebe, com o rodapé "may still be live"; `[recovery]` desliga | Igual na sessão. O painel pede o texto sem `session_id` e mostra a própria sessão como cortada | o snapshot é de propósito; o painel é erro nosso | D, H |
| 7. Perfil e precedência | Conversa › CLAUDE.md › memória do projeto › perfil. A passada roda depois de SessionEnd **com trabalho** e de hora em hora | Mesma precedência (texto do upstream). A passada roda a cada SessionEnd, até vazia (6 chamadas do haiku numa sessão vazia) | precedência igual; gatilho importado errado | C |
| 8. 3.4.7 → 3.5.0 | 314 commits; 5 migrações; chaves novas no marcador; StopFailure; re-briefing ao trocar de projeto; procedência das páginas | — | — | F |

## 1. O marcador (.ai-memory.toml)

**Upstream.** docs/marker-file.md, "Create a marker interactively": `ai-memory project init`, de
dentro de um checkout, cria o arquivo na raiz da worktree. Pede `workspace` e `project`, com o
padrão sendo o escopo que os hooks já resolvem (o marcador herdado, senão o nome tirado do remote
`upstream`/`origin`, senão a pasta), "so accepting the defaults pins the scope your memory already
lives in". Precisa de terminal, **nunca sobrescreve** e grava **só** `workspace` e `project`; o
resto fica no padrão até o dono escrever. E: "In a repository, commit the file so every checkout
and worktree routes the same way" (presente já na 3.4.7). Ninguém cria o arquivo sozinho: o
upstream não tem caminho automático. Código: crates/ai-memory-cli/src/marker.rs (achar e ler) e
`build_marker_query_suffix` em crates/ai-memory-cli/src/commands/hook_capture.rs (o que vai na
query).

Sem marcador vale: workspace `default`; projeto pelo caminho do remote (seção "Repository
identity"), senão a pasta; briefing desligado; handoff e snapshot entregues; perfil `contribute` e
`consume` com o valor guardado no servidor (sem marcador o cliente não manda os pares); captura de
tudo.

**Cadex.** `core/features/memory/server/src/marker.rs` é cópia do marker.rs do upstream e
`core/features/memory/server/src/marker_query.rs` repete o `build_marker_query_suffix`, no engine,
porque o `cadex memory-hook` não lê o arquivo. Quem grava é a tela do projeto:
`apps/macos/features/memory/MemoryProjectForm.swift` (`change`) só cria o arquivo quando um valor
difere do padrão, e `apps/macos/features/memory/MemoryMarker.swift` tem como padrão
`briefing = true`. A spec diz o mesmo (`docs/spec/memory.md`, "um arquivo novo só nasce quando algo
difere do padrão"). No `bkdg-center` não existe marcador.

**Veredito.** A criação: importamos errado em relação ao que o dono quer, não em relação ao
upstream (o upstream também não cria sozinho; o dono pediu que o Cadex crie em todo projeto). O
conteúdo padrão da tela: divergência sem motivo escrito além de "o Cadex liga o briefing" (ver 2).

**O que fazer (fase B).**
- Criar o arquivo ao adicionar um projeto e, nos que existem, ao abrir, sem sobrescrever um que
  já está lá, com o que o `project init` grava: `workspace = "default"` e `project = "<o nome que
  a memória já usa>"` (no Center, `bkdg-center`, o do projects.json). Fixar o `project` resolve a
  divergência do nome (ponto 3) sem mudar o motor e mantém o histórico onde está.
- As outras chaves vão **comentadas**, com o padrão do upstream: `[briefing]
  inject_on_session_start` comentada (desligado), `[handoff]`, `[recovery]`, `[profile]`,
  `[capture]`. O `MemoryMarker` passa a ter `briefing = false` como padrão.
- O `workspace` da conta (memory.shareAcrossAccounts desligada) continua valendo mais que o do
  arquivo (`core/features/memory/server/src/marker_query.rs`, motivo escrito: privacidade). Isso não muda.
- **Git (pergunta aberta).** A posição do upstream é fazer commit, e a tela do Cadex já diz isso.
  Duas razões práticas a favor: a worktree fora da raiz (o `bkdg-space`) só vê o marcador se ele
  estiver no branch dela, já que a busca sobe pelas pastas e não passa pela raiz principal; e
  todo checkout fica com o mesmo nome. Contra: o `bkdg` é repositório de time. Um arquivo que
  só nomeia o projeto não afeta quem não usa ai-memory. A alternativa local é `.git/info/exclude`.
  Decisão do dono.

## 2. O briefing

**Upstream.** docs/marker-file.md (schema, `[briefing]`): "Off by default: the brief costs tokens on
EVERY session start, so opt in per repo." docs/design-tiered-session-brief.md, "Marker and
once-per-session gate": "Opt-in, off when absent". O servidor só monta o brief com o par
`briefing` verdadeiro (`render_requested_session_brief` em crates/ai-memory-hooks/src/router.rs).
As camadas (`render_session_brief`, mesmo arquivo; o desenho é o do doc): primeiro as páginas de
núcleo (fixadas, _rules/, _slots/, até 24), cada uma com um trecho curto, depois mais fundo
dentro de `max_chars` (padrão 4000, entre 1500 e 20000); as que não cabem viram lista de caminhos;
por fim os títulos das 10 páginas mudadas por último. Só devolve nada quando núcleo **e**
recentes estão vazios. Os textos são constantes:
- `BRIEF_PREAMBLE_TITLE`: "ai-memory: project brief (auto-injected — `.ai-memory.toml [briefing]`)";
- `BRIEF_AGENT_FOOTER`: "this brief is compiled from this project's pinned / _rules/ / _slots/
  wiki pages".

Os dois são iguais na 3.4.7 e na 3.5.0.

**Cadex.** `core/features/memory/events.zig` (`handoffTarget`) manda `briefing=1` em todo
SessionStart, e `core/features/memory/server/src/page/briefing.rs` faz o mesmo no painel. O
marcador só pode desligar (`core/features/memory/server/src/marker_query.rs`). Motivo escrito: `docs/plans/22-memory.md`, fase C,
"sem `briefing=1` as páginas não entram no briefing", o que é a descrição do interruptor, não um
motivo para ligá-lo. A spec registra a diferença ("o briefing já nasce ligado (no ai-memory é
preciso pedir)") sem dar razão.

**Veredito.**
- O padrão: importamos errado (divergência sem motivo; o dono prefere o do upstream).
- O aviso "auto-injected — .ai-memory.toml [briefing]": correto no upstream, onde só chega quem
  pediu no arquivo; mente no Cadex por causa do padrão nosso. Volta a ser verdade quando o
  briefing só vier pelo marcador.
- O rodapé "compiled from pinned / _rules/ / _slots/" quando só há títulos recentes: **erro
  dele**. `render_session_brief` põe o rodapé mesmo com o núcleo vazio. Acontece no upstream com
  qualquer repositório que ligou o briefing e ainda não tem página de núcleo.
- Injetar só títulos faz sentido? O próprio desenho diz que os títulos são "follow-up pointers"
  depois do núcleo. Sem núcleo, no Center, os títulos eram de sessões ("s", "pode fazer.") e das 4
  páginas erradas. Seguindo o upstream (desligado até o dono pedir), o caso some.

**O que fazer.** Fase B: tirar o `briefing=1` de `core/features/memory/events.zig` e de `core/features/memory/server/src/page/briefing.rs`, para valer o
marcador. Fase E: o rodapé fica como o upstream (não editamos os crates); reportar ao upstream o
rodapé com núcleo vazio. Se o dono quiser o texto certo antes disso, a reescrita é no crate do
Cadex, no caminho da resposta do /handoff (onde o `core/features/memory/server/src/session_facts.rs` já troca o handoff), com ADR
curta, porque é texto do upstream mudado por nós.

## 3. Qual projeto recebe a sessão, e com que nome

**Upstream.** docs/auto-scope.md e docs/marker-file.md ("Mid-session navigation"): a sessão e a
página dela ficam no projeto da pasta em que começou. Com `[routing] mid_session = "follow-cwd"`
(padrão, configuração do servidor, não do marcador), cada observação depois de um `cd` vai para o
projeto da pasta nova; com `sticky`, fica na sessão. Com `project_strategy = "repo-root"`, uma
observação numa pasta fora de qualquer repositório e de qualquer marcador herda o projeto da
sessão. Código: `resolve_project_ids_inner` e o bloco `sticky_scope` em
crates/ai-memory-hooks/src/router.rs.

Nome: na v3, um checkout sem marcador e com remote válido vai pela **identidade** do remote
(`github.com/blackdog-bkdg/bkdg`), e o nome é o caminho sem o host, `/` virando `-`
(`identity_style = "path"`, padrão do cliente desde a v3). Daria algo como `blackdog-bkdg-bkdg`.
Worktrees e clones do mesmo remote caem no mesmo projeto, onde quer que estejam. Um `project` no
marcador vale mais que o remote.

**Cadex.** O cliente manda `cwd`, `project_strategy=repo-root` e nenhuma identidade
(`core/features/memory/events.zig`; `core/features/memory/server/src/marker_query.rs`: "not sent: the repository identity and aliases (Cadex names a
project by its main repository root, server-side)"). O nome sai do `derive_project_name` do
upstream com a raiz do repositório principal: `bkdg-center`. A importação
(`core/features/memory/server/src/replay.rs`) manda todo evento de uma conversa antiga com a raiz
do projeto como `cwd`. O backfill do upstream também manda tudo para um escopo só.

Nos dados do dono: 32 sessões no `bkdg-center`, todas com `cwd` igual à raiz. O `bkdg-space` é
worktree do `bkdg-center` (`git rev-parse --git-common-dir` aponta para bkdg-center/.git) e está
no `git worktree list`; pela regra, as sessões dele vão para `bkdg-center`
(`core/features/memory/server/src/project_paths.rs`). Até 19/11 não havia nenhuma sessão com
`cwd` no `bkdg-space` no banco, então não pude ver isso acontecer. Há também um projeto `cadu`
(125 sessões com `cwd` na pasta pessoal) e um `scratch`.

A sessão `98ee49fa` (23/09) começou no Center e trabalhou em "bkdg/Migração Solides", que **não é
repositório git**. Com `repo-root`, o upstream também guardaria essas observações no Center. Se o
Claude Code manda o `cwd` novo no payload depois de um `cd` não confirmei. Para essa sessão não
importa: ela entrou pela importação, com a raiz como `cwd`.

**Veredito.** Escopo: igual ao upstream. Nome: divergência de propósito, escrita na spec ("o Cadex
é local e nomeia o projeto pela raiz do repositório principal") e no plano 22 (sem `repo-root` cada
worktree virava projeto). Esse motivo era verdade sem identidade. Com a identidade da v3 o
upstream também junta as worktrees. Ainda assim, mudar agora renomearia ou dividiria a memória
que existe.

**O que fazer.** Fase B: o marcador criado fixa `project = "bkdg-center"`. O upstream recomenda
isso para manter o escopo atual, e assim a escolha fica explícita e com o mesmo efeito, sem tocar
no motor. Fase E: nada no nome. Confirmar com uma sessão real no `bkdg-space` que ela cai no
`bkdg-center`. Sessão que muda de repositório: a 3.5.0 traz `[routing] brief_on_project_change`
(só re-briefa, só quando a pasta nova tem marcador). Nada no upstream reatribui a sessão ou recusa
a proposta do auto-improve por caminho inexistente; não achei essa checagem. Isso seria nosso
(fase G).

## 4. O auto-improve

**Upstream.** docs/auto-improvement-loop.md: "periodically reviews newly completed sessions",
"auto-approved by default" (`[auto_improve] require_approval = false`), `min_observations = 8`,
`min_session_duration_secs = 120`; agendador com `interval_secs = 3600`,
`max_sessions_per_tick = 1` por projeto, `min_session_age_secs = 600`. Nos "Safety Invariants":
"Automatic SessionEnd triggering is off by default". No "Existing User Upgrade Contract": "Historical
sessions are not reviewed automatically on upgrade". Código: `ensure_scheduler_state` em
crates/ai-memory-store/src/auto_improve.rs grava a marca d'água no `ended_at` mais novo do
projeto; `auto_improve_candidate_sessions` em crates/ai-memory-store/src/reader.rs pega as
sessões terminadas depois dela, **da mais velha para a mais nova**; e o serve.rs chama
`initialize_auto_improve_scheduler_scopes` ao subir, para todo projeto conhecido. O experience
(`experience_every_sessions`) vem desligado (crates/ai-memory-cli/src/config.rs, `0`).

**Cadex.** `core/features/memory/server/src/agent/improve.rs` é cópia do agendador. O "tick" é o
SessionEnd ao vivo: no máximo uma revisão por hora por projeto (agent/cadence.json),
`min_session_age_secs: 0`, experience **ligado** (`ExperienceConfig::default()`, com a nota de que
o upstream o deixa desligado), `require_approval` da configuração (desligada por padrão, ADR
`docs/adr/0037-memory-agent-on-by-default.md`, como o upstream). A marca d'água só é criada dentro
do primeiro job do projeto (`ensure_auto_improve_scheduler_state` em `core/features/memory/server/src/agent/improve.rs`); o engine não
chama o `initialize_…` ao subir (`core/features/memory/server/src/engine.rs`).

**O que os dados mostram** (o banco do dono, só leitura):
- `auto_improve_scheduler_state` do `bkdg-center`: `watermark_ended_at = 0`, iniciada em
  18/11 15:38:02Z, antes da importação do histórico (~15:39). Toda sessão importada ficou
  "nova".
- `auto_improve_scheduler_claims` do Center, em ordem: `98ee49fa` (16:05, a das competências),
  `db33cbf6`, `db0c4cf3`, `d274efce`, `2416d0a7` (19/11 01:48). São as sessões de setembro, por
  `ended_at`. As de 5 e 4 observações passaram pelo filtro sem chamar o modelo.
- O gatilho de cada uma foi o SessionEnd de outra sessão, inclusive das vazias. A revisão das
  competências saiu do fim da `3cd2e5f6` (2 observações).
- O ledger registra a sessão **que terminou**, não a revisada. A linha "auto-improve … session
  3cd2e5f6" foi a revisão da `98ee49fa` (`core/features/memory/server/src/agent/jobs.rs`, `Step::provider` põe job.session no
  rótulo). A auditoria lê errado.

Não descobri quem criou a linha às 15:38:02. O resultado é certo: com a marca em 0, o histórico
inteiro entra na fila.

**Veredito.** Importamos errado: (a) a marca d'água fora da ordem do upstream (ele cria ao subir,
para todo projeto, e o histórico do primeiro uso nunca é revisado); (b) a revisão disparada pelo
SessionEnd, inclusive de sessão vazia, onde o upstream usa relógio. O relógio foi recusado pelo
Cadex de propósito (ADR 0029, "nunca por relógio"), então (b) é divergência com motivo; o que falta
é o filtro de sessão vazia. (c) Experience ligado: divergência anotada no código, sem decisão do
dono escrita.

**O que fazer.**
- Fase C: sessão vazia não dispara o job (seção abaixo).
- Fase G: criar a marca d'água como o upstream, depois da importação de cada projeto
  (`core/features/memory/server/src/import_jobs.rs` marca `done`) ou ao subir com
  `initialize_auto_improve_scheduler_scopes`, que é pública. Para o Center, que já está com 0, a
  correção precisa avançar a marca até o `ended_at` mais novo do backfill; é escrita no banco do
  dono, com o aval dele. O backfill passa a ser revisado só à mão, com aprovação: é configuração,
  `require_approval` no agent.json (memory.requireApproval), não código.
- Recusar proposta que cita caminho ou tabela que não existe no repositório: o upstream não tem.
  É código nosso, no `stage_and_apply` de `core/features/memory/server/src/agent/improve.rs`, antes de aprovar.
- Fase D: o ledger passa a registrar a sessão revisada (o `candidate.session_id`) ao lado da
  que disparou.
- Decidir com o dono se o experience segue ligado (o upstream deixa desligado).

## 5. As páginas de sessão

**Upstream.** crates/ai-memory-hooks/src/synth.rs: "Rule-based session-page synthesis (no LLM) …
first-prompt as title, files touched, tool-call counts". O corpo é metadados mais a lista
`## Prompts`. A consolidação por IA no SessionEnd é opcional e vem **desligada**:
`consolidate_on_session_end` em crates/ai-memory-hooks/src/router.rs ("Off by default so session
close stays cheap"), ligada por AI_MEMORY_CONSOLIDATE_ON_SESSION_END. Sem provedor nunca há
resumo. O histórico importado vira o mesmo tipo de página, e o caminho para destilá-lo é o
bootstrap (docs/design-boot-backfill.md, "Consolidation quality: shipped behind the hard cap").

**Cadex.** As páginas do backfill do Center são as do synth ("generated by process:ai-memory/3.4.7
at 2026-11-18T15:39:57Z", "167 prompts, over 140h 9m."). As sessões ao vivo são consolidadas
pelo haiku em todo SessionEnd (`core/features/memory/server/src/agent/jobs.rs`, `consolidate`); a
`4d9262aa` tem resumo de verdade. O bootstrap existe e só roda no clique do dono (ADR 0029).

**Veredito.** Igual ao upstream. Ele também não destila por padrão, e o Cadex destila mais (as
sessões ao vivo). Os títulos inúteis ("s", "pode fazer.") são a regra do synth.

**O que fazer.** Fase G: rodar o bootstrap no Center (memory.bootstrap, com a estimativa antes),
depois de o auto-improve parar de andar sozinho pelo backfill. Nada no synth.

## 6. O snapshot de recuperação

**Upstream.** `render_interrupted_session_context` em crates/ai-memory-hooks/src/router.rs: a
última sessão do mesmo escopo e dono sem SessionEnd, **menos a que está recebendo**
(`latest_interrupted_session_candidate`, docs/security-boundaries.md linha 29), até 64
observações e 6.000 caracteres. É de propósito, e o rodapé (`INTERRUPTED_SESSION_FOOTER`) diz: "the
source session did not emit SessionEnd and may still be live … Do not close or overwrite the
source session". O que exige 15 min parada é só o marcador de fechamento
(`BACKFILL_CLOSE_MIN_IDLE`), pensado para "a live parallel agent mid-turn". Para desligar,
`[recovery] deliver_on_session_start = false` no marcador.

**Cadex.** O SessionStart manda `session_id` (`core/features/memory/events.zig`), então a sessão nunca recebe a si
mesma. O painel monta "o que a próxima sessão recebe" com `claim=0` e **sem** `session_id`
(`core/features/memory/server/src/page/briefing.rs`, `base`). Por isso o texto mostrado dentro da `4d9262aa` trazia a própria
`4d9262aa` como cortada. Nenhum texto injetado fica guardado.

**Veredito.** O snapshot de uma sessão paralela viva é de propósito no upstream, com o aviso
escrito. O que confundiu é erro nosso: o painel mostra a prévia da próxima sessão como se fosse a
da atual, e não há registro do que foi entregue.

**O que fazer.** Fase D: guardar por sessão o texto que o SessionStart entregou. É a resposta do
/handoff vista no engine, um middleware ao lado de `core/features/memory/server/src/handoff.rs`, ou
o `additionalContext` que `core/features/memory/hook_client.zig` imprime. Fase H: o painel diz "o
próximo agente vai receber" e o resumo de uma sessão mostra o que ela recebeu. Opcional, decisão
do dono: com muitas sessões paralelas no mesmo projeto, `[recovery] deliver_on_session_start =
false` no marcador. É configuração do upstream e não diverge dele.

## 7. O perfil e a precedência

**Upstream.** docs/cross-project-profile.md, "How the agent uses it": 1. as instruções da
conversa; 2. o arquivo de regras do repositório (CLAUDE.md, AGENTS.md); 3. a memória do projeto; 4.
o perfil. Num servidor de um usuário só fica ligado e global (`default/_global`). A passada roda
"once shortly after startup, after every session that ends (a few seconds later, so a burst of
session ends costs one pass), and hourly". No código da 3.4.7, o aviso (`profile_notify`) só toca
no caminho de sessão **com trabalho**; o caminho de sessão vazia retorna antes. A colheita pula
página que o auto-improve aprovou sozinho.

**Cadex.** O texto do perfil é o do upstream, com a mesma precedência. `core/features/memory/server/src/agent/jobs.rs` roda o
`run_profile_pass` em todo job de SessionEnd, sem olhar se a sessão teve trabalho. O ledger do dono
mostra 6 chamadas de perfil depois da sessão vazia `3cd2e5f6` e outras 6 depois da `4d9262aa`.

**Veredito.** Precedência: igual. Gatilho: importamos errado (sessão vazia não devia disparar).

**O que fazer.** Fase C (o mesmo filtro da sessão vazia). Na fase F, olhar o `[profile]
harvest_prompts = "interactive"` da 3.5.0: a sessão aberta por automação
(AI_MEMORY_SESSION_ORIGIN=automation) não vira perfil. Serve às sessões que o Cadex abre por
orquestração ou corrida (ADR 0033), se o dono não quiser os prompts delas no perfil. O cliente
Zig teria de mandar o par.

## Sessão vazia (fase C, pergunta aberta)

**Upstream, já na 3.4.7.** crates/ai-memory-hooks/src/router.rs, no SessionEnd:
`session_has_substantive_observation`. Sem nenhum `UserPrompt`, `PreToolUse` ou `PostToolUse`
(`is_ephemeral_session`), chama `end_admitted_lifecycle_only_session` e para: "lifecycle-only
session ended without summary, handoff, or consolidation". Sem página, sem handoff, sem fila de
consolidação, sem perfil.

**Cadex.** O middleware `watch` de `core/features/memory/server/src/agent/routes.rs` transforma
todo SessionEnd aceito (202) num job (`enqueue`), sem essa checagem. O job consolida com
`consolidate_session_keeping_agent_page`, que escreve página para uma sessão de 2 observações (só
falha com zero). Depois roda perfil, experience e auto-improve. Continua acontecendo: a `d2a9e4be`
(19/11 01:46, 2 observações) virou a página "Sessão vazia sem atividade registrada" e disparou
consolidate, experience e a revisão da `2416d0a7`. As outras vazias no banco: `31264e58`,
`3cd2e5f6` e `4fc4d46a`.

**Veredito.** Importamos errado: o agente do Cadex passa por cima de um filtro que o upstream tem.

**Onde filtrar, sem editar o upstream.** No crate `cadex-memory`, no começo do ramo
`Kind::SessionEnd` de `core/features/memory/server/src/agent/jobs.rs` (`run`): achar o escopo da
sessão (`find_session_scope`, já usado em `core/features/memory/server/src/agent/improve.rs`) e chamar
`reader.session_has_substantive_observation(ws, proj, sid)`, que é pública no store. Se der falso,
uma linha no ledger sem custo (`Step::note`, "empty session") e fim. No job, e não no middleware,
porque o upstream fecha a sessão numa tarefa à parte depois do 202. O job já espera
`--import-delay-ms`, e o predicado é o mesmo que o upstream usa ao fechar. O mesmo filtro vale para
o `Kind::Compact`.

Uma diferença de palavra: o plano diz "sem nenhum `user-prompt`". O critério do upstream é "sem
prompt **e** sem ferramenta". Uma sessão só de ferramentas (um agente que rodou sem prompt
digitado) conta como trabalho. Recomendo o do upstream. Se o dono quiser o critério do plano, é
uma consulta nossa às observações de tipo `user-prompt`. Na tela (fase H), a lista de sessões
esconde as que o upstream fechou como vazias (sem página).

## 8. O que mudou da 3.4.7 para a 3.5.0

314 commits entre fa0ec25 e 411d90d; nos crates, +29.689/−2.064 linhas em 314 arquivos.
CHANGELOG.md, seção [3.5.0] - 2026-11-18. O que toca o Cadex:
- **Migrações V108 a V112**: sessions.origin, o limite e o piso de relevância por projeto, e
  `page_sources` (de quais observações cada versão de página saiu, #2164). Esta ajuda na
  auditoria da fase D: dá para ver de onde uma página veio.
- **Marcador**: `[retrieval] default_result_limit` e `min_relevance`, que o cliente manda no
  SessionStart. `core/features/memory/server/src/marker_query.rs` precisa repassar. Atenção: o `min_relevance` exige reranker e a
  consulta é recusada sem ele. Conferir se o engine do Cadex tem um antes de deixar a tela
  oferecer a chave.
- **Roteamento**: `[routing] brief_on_project_change` (servidor, padrão desligado).
- **Hooks**: StopFailure e Interrupt passam a gravar o fim de turno (#2303). O kit e o
  `core/features/memory/events.zig` precisam do evento novo.
- **Auto-improve e experience**: orçamento de entrada com margem de 80% e o pulo
  `input_budget_too_small`, que avança a sessão (#2309, #2312, #2313), dentro de
  `run_auto_improve_review` e `run_experience_review`, que o Cadex chama: vem de graça.
  `include_global_titles` (opcional). O reviewer passa a tratar correções do usuário (#1992).
  O auto_improve_schedule.rs que `core/features/memory/server/src/agent/improve.rs` copia mudou só nos testes.
- **Consolidação**: `[consolidation] output_language` (opcional; o dono escreve em português).
- **Perfil**: `harvest_prompts = "interactive"` (ponto 7).
- **O handoff no SessionStart** entrega o retrato da própria reivindicação (#2340).
- **Código copiado** que o procedimento de `core/features/memory/CLAUDE.md` manda comparar: serve.rs
  +493 linhas, run.rs +465, hook.rs +419, hook_capture.rs +96, marker.rs +11 (as duas chaves de
  `[retrieval]` na lista de fronteira), backfill.rs +4 (dois campos novos no `HookState`,
  `project_briefs` e `assistant_excerpt_max_bytes`, que o `core/features/memory/server/src/engine.rs` precisa preencher; o
  compilador acusa).
- Não muda nada nos pontos 2, 5 e 6: o aviso, o rodapé, o synth e o snapshot são iguais.

**O que fazer (fase F).** O procedimento de atualização do `core/features/memory/CLAUDE.md`, com
atenção a: os dois campos do `HookState`, o repasse das chaves de `[retrieval]`, o evento
StopFailure no cliente e o `make memory-upstream-test` no PC.

## Perguntas em aberto, com o que o estudo responde

- **O .ai-memory.toml no git?** O upstream manda fazer commit (ponto 1). A decisão é do dono, por
  ser repositório de time.
- **Sessão vazia, onde filtrar?** No começo do job de SessionEnd, em `core/features/memory/server/src/agent/jobs.rs`, com o
  predicado do upstream (seção "Sessão vazia").
- **Reatribuir a sessão que muda de repositório?** O upstream não reatribui; a 3.5.0 só re-briefa
  quando há marcador. Recusar proposta com caminho inexistente seria código nosso (fase G).
- **Auto-improve no backfill com `require_approval = true`?** Sim, mas antes é preciso parar a
  revisão automática, que já está andando pelo histórico (ponto 4). `require_approval` é
  configuração, não código.
- **Briefing desligado sem página fixada?** Seguindo o upstream, desligado até o marcador pedir; o
  caso dos títulos some (ponto 2).
- **Corrigir o texto do aviso ou criar o marcador?** Criar o marcador e tirar o `briefing=1`: o
  aviso volta a ser verdade. O rodapé é do upstream (ponto 2).

## O que não confirmei

- Quem criou a marca d'água do Center às 15:38:02 (o efeito, marca em 0, está confirmado).
- Se o Claude Code manda o `cwd` novo no payload do hook depois de um `cd` no Bash.
- Uma sessão real no `bkdg-space` caindo no `bkdg-center` (pela regra, cai; não havia nenhuma no
  banco).
- Se o engine do Cadex tem reranker para o `min_relevance` da 3.5.0.
