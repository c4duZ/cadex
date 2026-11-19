# Plano 35 — A memória que acerta

Handoff para a sessão que vai fazer este plano (escrito em 2026-11-18, depois do plano 34). A
origem é uma auditoria feita numa sessão do `bkdg-center` (o arquivo
`~/Downloads/handoff-ai-memory-bkdg-center-2026-11-18.md`, do dono) e o que o dono decidiu ao
lê-lo. Resumo do caso: no `bkdg-center`, das 33 páginas, só 4 eram de conhecimento, e as 4 eram de
outro sistema (competências e ciclo de avaliação, de uma sessão que abriu no Center e trabalhou em
outra pasta por `cd`); as páginas de sessão eram a lista de prompts com o primeiro como título
("s", "pode fazer."); nada das sessões grandes virou conhecimento; e duas sessões vazias, de um
painel do Cadex aberto e fechado sem prompt, dispararam o agente de memória, que gastou chamadas
do haiku e escreveu justamente as 4 páginas erradas.

Os nomes de arquivo do upstream (docs/…) e da wiki (_rules/, _slots/) vão sem crase: não são
caminhos deste repositório.

## O que eu quero
- A memória do jeito do ai-memory do Fabio Akita (`github.com/akitaonrails/ai-memory`). Onde o
  Cadex diverge dele, fica o jeito dele, a menos que um motivo escrito diga o contrário (o dono,
  2026-11-18: "eu prefiro manter da forma dele").
- Primeiro um estudo grande do upstream: como ele faz cada coisa abaixo, e, para cada diferença,
  se fomos nós que importamos errado ou se é ele. O estudo vira um documento antes de qualquer
  código.
- O .ai-memory.toml em todo repositório aberto como projeto no Cadex (o dono, 2026-11-18: "a
  gente tem que ter esse arquivo em todos os repositórios que a gente abre como um projeto"). Hoje
  ele só nasce quando o dono muda algo do padrão (`../../apps/macos/features/memory/MemoryMarker.swift`).
- Sessão sem nenhum prompt do dono não vira página nem chama o agente de memória.
- Poder auditar o agente: o pedido e a resposta de cada chamada do `claude -p` guardados (0600, com
  retenção), e o briefing que cada sessão recebeu de fato guardado por sessão.
- O painel e a página do projeto (plano 34) mostrando o que foi dado, não o que seria dado agora.

## O que eu não quero
- Editar os crates do upstream: o que mudar no motor é no crate `cadex-memory` (`../../core/features/memory/server/`)
  ou, se for preciso mudar o upstream, um `[patch]` com ADR (`../../core/features/memory/CLAUDE.md`).
- Corrigir antes de estudar: cada fase de correção cita o trecho do estudo que a justifica.
- Texto que mente: o aviso do briefing dizendo "`.ai-memory.toml [briefing]`" sem o arquivo, e o
  rodapé "compiled from pinned / _rules/ / _slots/" sem nenhuma dessas páginas.
- Gastar o haiku com sessão vazia.

## Decidido com o dono (2026-11-19, lendo o estudo `../research/ai-memory-upstream.md`)
- **Por que as competências caíram no Center** (o que importa mais que o Center): a sessão
  `98ee49fa` começou na raiz do Center e trabalhou noutra pasta (a regra do upstream, a sessão é da
  pasta em que começou); três erros nossos fizeram disso páginas: a marca d'água do auto-improve
  criada em 0 antes da importação (o upstream nunca revisa o histórico), a revisão disparada pelo
  fim de uma sessão vazia (a `3cd2e5f6`), e nada conferindo se a proposta fala do repositório. O
  ledger, ainda, registra a sessão que terminou e não a revisada.
- Corrigir o banco do Center (avançar a marca d'água até o fim do backfill): pode.
- Sessão vazia: o critério do upstream, sem prompt **e** sem ferramenta.
- O briefing continua ligado para o dono, mas pelo marcador: o .ai-memory.toml nasce em todo
  projeto com `inject_on_session_start = true` escrito nele (o aviso volta a ser verdade). Sem
  página de núcleo (fixadas, _rules/, _slots/), não se injeta nada: só títulos de sessão não
  ajudam (no Center eram "s", "pode fazer." e as quatro páginas erradas); divergência com o motivo.
- O marcador vai para o git do repositório por padrão; nas Configurações do projeto o dono escolhe
  "só nesta máquina" (o arquivo no .git/info/exclude). O Cadex não faz commit.
- O experience fica ligado (decisão do dono; o upstream o deixa desligado), escrito na ADR.

## Como eu quero
- [x] A. O estudo, num arquivo novo em docs/research (ai-memory-upstream.md): o upstream na 3.5.0 (commit `411d90d`)
  contra o que o Cadex fixa (`fa0ec25`, a 3.4.7, `../../core/features/memory/server/Cargo.toml`). Para
  cada ponto, como ele faz, onde está (o doc e o código dele), como o Cadex faz, e o veredito
  (importamos errado, divergência de propósito, ou erro dele):
  1. O marcador: o .ai-memory.toml, quando e por quem é criado, o que vale sem ele
     (docs/marker-file.md dele).
  2. O briefing: no upstream fica desligado e liga por repositório no marcador; o Cadex liga por
     padrão (`../../core/features/memory/server/src/marker_query.rs`, `briefing=1`). O texto do aviso e o
     rodapé. O resumo em camadas (fixadas, _rules/, _slots/, depois só títulos:
     docs/design-tiered-session-brief.md dele) e se faz sentido injetar só títulos.
  3. Qual projeto recebe a sessão: a pasta em que ela começou, e um `cd` no meio não muda
     (docs/auto-scope.md). O nome do projeto: a v3 nomeia pelo caminho do remote (aqui
     `github.com/BlackDog-bkdg/bkdg`), o Cadex pela raiz da pasta (`bkdg-center`, no
     projects.json da memória). Para onde vão as sessões de uma worktree em pasta irmã fora da
     raiz (o `bkdg-space`).
  4. O auto-improve: só sessões novas, quando terminam; mínimo de 8 observações; grava sem
     aprovação por padrão (docs/auto-improvement-loop.md). O backfill (importado em 18/11) não é
     revisado sem rodar à mão.
  5. As páginas de sessão: por que o título é o primeiro prompt e o corpo só a lista, sem resumo
     destilado; se o upstream destila e nós não ligamos, ou se ele também não.
  6. O snapshot de recuperação ("unfinished-session recovery"): ele trata como cortada uma sessão
     viva só por não ter `SessionEnd`; numa sessão paralela isso vira "trabalho interrompido" que
     continua andando.
  7. O perfil e a precedência (usuário, `CLAUDE.md`, memória do projeto, perfil).
  8. O que mudou da 3.4.7 para a 3.5.0.
  Feito: `../research/ai-memory-upstream.md`, lido e decidido com o dono (acima).
- [x] B. O marcador em todo projeto: ao adicionar um projeto (e nos que já existem, ao abrir), o
  Cadex cria o .ai-memory.toml com o que o estudo disser que é o padrão certo, comentado; a
  seção Memória das Configurações do projeto (plano 32, que no plano 34 fica dentro da página do
  projeto) edita esse arquivo. Decidir com o dono se o arquivo entra no git do repositório.
  Feito: o app cria o .ai-memory.toml ao abrir, criar ou restaurar um projeto e ao ligar a memória
  (uma vez por abertura, fora da linha principal, nunca por cima de um que existe, nunca na pasta
  pessoal, só com memory.enabled), com `workspace`, `project` (o nome que a memória já usa) e
  `[briefing] inject_on_session_start = true`, o resto comentado
  (`../../apps/macos/features/memory/MemoryMarkerPlace.swift`, `../../apps/macos/app/MemoryMarkerWiring.swift`);
  a seção Memória do projeto escolhe "No repositório" ou "Só neste Mac" (o `info/exclude` do git).
  O cliente e o engine deixaram de pedir `briefing=1`: o briefing vem só do arquivo, como no
  upstream (`../../core/features/memory/events.zig`, `../../core/features/memory/server/src/page/briefing.rs`).
  Apagar o arquivo à mão: ele volta na próxima abertura do projeto.
- [x] C. A sessão vazia: sem nenhum `user-prompt`, não grava página de sessão e não dispara o
  agente (consolidate, perfil, auto-improve). O caso: as sessões `4fc4d46a` e `3cd2e5f6`, um painel
  aberto às 14:20 sem prompt (`sessions/cfa808ed-….args.json` com `[]`).
  Feito: o critério do upstream (sem prompt e sem ferramenta, `session_has_substantive_observation`),
  no começo do trabalho de SessionEnd e de PostCompact em
  `../../core/features/memory/server/src/agent/jobs.rs`: só uma linha sem custo no ledger ("empty
  session"); teste em `../../core/features/memory/server/tests/agent.rs` (falha sem o filtro).
- [x] D. A auditoria do agente: cada chamada do `claude -p` (que vai pelo stdin, com
  `--no-session-persistence` e hooks desligados, `../../core/features/memory/server/src/agent/claude_cli.rs`)
  grava o pedido e a resposta ao lado do memory/agent/ledger.jsonl, 0600, com retenção; e o
  briefing injetado em cada SessionStart fica guardado por sessão.
  Feito: cada chamada grava `agent/calls/<hora>-<tipo>-<id>.json` (o argv, o system prompt, o
  stdin, a resposta; sem ambiente nem token; 0600, pasta 0700), apontado pela linha do ledger
  (`call`); o briefing de cada SessionStart de verdade fica em `agent/briefings/<sessão>.md`; as
  duas pastas guardam 30 dias e no máximo 500 arquivos
  (`../../core/features/memory/server/src/agent/audit.rs`,
  `../../core/features/memory/server/src/agent/briefings.rs`).
- [x] E. O que o estudo apontar como importado errado: o texto do aviso e do rodapé, o briefing
  por padrão, o snapshot com sessão viva, o nome do projeto e a worktree irmã, cada um com o veredito
  do estudo.
  Feito: o aviso do briefing ficou verdadeiro na B (o briefing só vem do arquivo); sem página de
  núcleo o briefing não vai, o que tira também o rodapé que mentia
  (`../../core/features/memory/server/src/core_brief.rs`, teste em
  `../../core/features/memory/server/tests/memory_page.rs`, que falha sem o filtro); o nome do
  projeto ficou fixado no arquivo (B). O painel que mostra a própria sessão como cortada fica na H.
  Falta ver uma sessão de verdade no `bkdg-space` cair no `bkdg-center`; o rodapé com núcleo vazio
  vale relatar ao upstream.
- [x] F. A 3.5.0: atualizar o commit fixado, com a suíte do upstream (`make memory-upstream-test`, no
  PC) e a nossa.
  Antes de instalar um pacote com a 3.5.0: copiar o memory.sqlite do dono para o lado (como o
  memory.sqlite.before-plan35 da G). As migrações V108 a V112 rodam ao subir e não voltam; o engine
  novo só rodou em pastas temporárias.
  Feito: o upstream fixado na 3.5.0 (`411d90d`); no crate, os três campos novos com os padrões do
  upstream, o repasse de `[retrieval] default_result_limit` e `min_relevance` (o engine não tem
  reranker: o `min_relevance` recusa a busca, a tela não o oferece) e a correção do upstream que
  tira de um ai-jail sem preset as chaves de outros provedores. O StopFailure (turno cortado por
  erro da API) entra no kit e vai como `stop`, sem pedir consolidação. A suíte do upstream rodou no
  Mac, sem o PC: 5.029 testes, nenhuma falha, 18 min; a nossa passa inteira. Fica o `make perf`, a
  suíte no PC se o dono quiser, e copiar o memory.sqlite do dono antes de instalar o pacote
  (V108–V112 não voltam).
- [x] G. O auto-improve com proteção: recusar a proposta que cita caminhos ou tabelas que não
  existem no repositório do projeto; rodar o backfill do Center com `require_approval = true`.
  Conforme o estudo, isso pode ser configuração do upstream e não código nosso.
  Feito antes (2026-11-19, com o aval do dono): no banco do dono, a marca d'água do `bkdg-center` e
  do `cadex` foi para o fim do histórico importado (a sessão mais nova terminada antes de a marca
  nascer), com cópia em memory.sqlite.before-plan35 ao lado; o `cadu` (a pasta pessoal) segue em 0.
  As quatro páginas de competências já tinham saído em 18/11 (a sessão do Center); as três que o
  auto-improve escreveu depois (o Suporte do admin, o disco do Postgres de dev, a migration 0259)
  são do Center e ficam.
  Feito no código: o engine inicializa o agendador ao subir, como o upstream, e cada sessão
  importada (o histórico do projeto e as de fora do Cadex) é marcada como já vista, sem revisão
  automática (`../../core/features/memory/server/src/history_review.rs`); a proposta que cita só
  caminhos que não existem no repositório é recusada, com uma linha sem custo no ledger
  (`../../core/features/memory/server/src/agent/cited_paths.rs`); a linha do auto-improve diz a
  sessão revisada em `session` e a que terminou em `trigger`. O backfill do Center revisado com
  aprovação (o bootstrap) fica para quando o dono quiser rodar.
- [x] H. Na tela (com o plano 34): o resumo de uma sessão mostra o briefing que ela recebeu; as
  sessões vazias não aparecem; o painel Memory diz "o próximo agente vai receber" quando mostra o
  briefing de agora.
  Feito: o detalhe de uma sessão na página do projeto tem "O que esta sessão recebeu" (o arquivo
  da fase D, lido do disco); as sessões sem prompt saem das listas (a história do Claude e as
  páginas de sessão do upstream sem prompt nem ferramenta); a prévia se chama "O próximo agente vai
  receber"; e a prévia não mostra como cortada uma sessão viva (o engine guarda o id de cada sessão
  viva e pergunta de novo com `recovery=0`, divergência escrita na spec). Não conferido no app.

- [ ] I. Desligar a memória num projeto ou numa conversa (o dono, 2026-11-19: "a gente precisa
  poder desligar o AI memory em projetos específicos ou conversas específicas"). O ai-memory não tem
  esse interruptor (só `[capture] ignore_paths` e `AI_MEMORY_HANDOFF=off`); é do Cadex.
  1. **Por projeto:** "Memória neste projeto" no topo da seção Memória das Configurações do
     projeto, guardado no arquivo de projetos do Cadex (não no .ai-memory.toml: commitado, valeria
     para o time). Desligada: as sessões que o Cadex abre ali não recebem os hooks nem as
     ferramentas da memória (nada gravado, nada injetado), a importação o pula, o agente não o
     revisa, e a busca de outros projetos não o enxerga (desligado é desligado; o dono concordou).
     O que já está gravado fica.
  2. **Por conversa:** "Nova sessão sem memória" (o "+" das abas e o ⌘K) abre a sessão sem os
     hooks e as ferramentas; "Pausar a memória nesta sessão" (o menu da aba e o ⌘K) marca a sessão
     e, dali em diante, o hook e o engine descartam os eventos dela, e ela não vira página nem chama
     o agente ao terminar; a aba mostra um sinal discreto. Pausar não apaga o que já foi gravado.
  Apagar a memória de um projeto e esquecer uma sessão ficam para depois.

## Como validar
- O estudo lido e aprovado pelo dono antes das fases B a G.
- `make memory-test` e o `make memory-upstream-test` no PC depois de F.
- Numa instância de teste: abrir e fechar um painel sem prompt não cria página nem linha no ledger;
  uma sessão com prompt cria a página e deixa o pedido e a resposta do agente na pasta de auditoria;
  um projeto novo nasce com o .ai-memory.toml.
- O `bkdg-center` do dono depois de F e G: as sessões do backfill revisadas com aprovação, sem
  página de outro sistema.
