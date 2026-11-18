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

## Como eu quero
- [ ] A. O estudo, num arquivo novo em docs/research (ai-memory-upstream.md): o upstream na 3.5.0 (commit `411d90d`)
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
- [ ] B. O marcador em todo projeto: ao adicionar um projeto (e nos que já existem, ao abrir), o
  Cadex cria o .ai-memory.toml com o que o estudo disser que é o padrão certo, comentado; a
  seção Memória das Configurações do projeto (plano 32, que no plano 34 fica dentro da página do
  projeto) edita esse arquivo. Decidir com o dono se o arquivo entra no git do repositório.
- [ ] C. A sessão vazia: sem nenhum `user-prompt`, não grava página de sessão e não dispara o
  agente (consolidate, perfil, auto-improve). O caso: as sessões `4fc4d46a` e `3cd2e5f6`, um painel
  aberto às 14:20 sem prompt (`sessions/cfa808ed-….args.json` com `[]`).
- [ ] D. A auditoria do agente: cada chamada do `claude -p` (que vai pelo stdin, com
  `--no-session-persistence` e hooks desligados, `../../core/features/memory/server/src/agent/claude_cli.rs`)
  grava o pedido e a resposta ao lado do memory/agent/ledger.jsonl, 0600, com retenção; e o
  briefing injetado em cada SessionStart fica guardado por sessão.
- [ ] E. O que o estudo apontar como importado errado: o texto do aviso e do rodapé, o briefing
  por padrão, o snapshot com sessão viva, o nome do projeto e a worktree irmã, cada um com o veredito
  do estudo.
- [ ] F. A 3.5.0: atualizar o commit fixado, com a suíte do upstream (`make memory-upstream-test`, no
  PC) e a nossa.
- [ ] G. O auto-improve com proteção: recusar a proposta que cita caminhos ou tabelas que não
  existem no repositório do projeto; rodar o backfill do Center com `require_approval = true`.
  Conforme o estudo, isso pode ser configuração do upstream e não código nosso.
- [ ] H. Na tela (com o plano 34): o resumo de uma sessão mostra o briefing que ela recebeu; as
  sessões vazias não aparecem; o painel Memory diz "o próximo agente vai receber" quando mostra o
  briefing de agora.

## Como validar
- O estudo lido e aprovado pelo dono antes das fases B a G.
- `make memory-test` e o `make memory-upstream-test` no PC depois de F.
- Numa instância de teste: abrir e fechar um painel sem prompt não cria página nem linha no ledger;
  uma sessão com prompt cria a página e deixa o pedido e a resposta do agente na pasta de auditoria;
  um projeto novo nasce com o .ai-memory.toml.
- O `bkdg-center` do dono depois de F e G: as sessões do backfill revisadas com aprovação, sem
  página de outro sistema.
