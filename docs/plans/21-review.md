# Plano 21 — Revisar o código do agente

Depende de: plano 19 (worktree por tarefa, ponto de partida, app.sock, `cadex hook`) e plano 18
(kit da sessão) · Features: source-control (núcleo e app), review (nova, app macOS), agents,
worktrees, explorer, terminal, shortcuts, settings, command-palette · Decisões: ADR 0027 (a
escrever na fase A), `docs/adr/0018-element-picker.md` (entrega por colagem sem Enter),
docs/adr/0021-cadex-managed-accounts.md e docs/adr/0022-terminal-daemon.md (planos 18 e 19),
`docs/adr/0004-clean-rewrite.md`, `docs/adr/0005-every-action-is-a-command.md`.

## O que eu quero
- Revisar de verdade o que o agente fez numa worktree, sem sair do Cadex (o dono, 2026-11-14,
  depois de ler a doc do Orca): todas as mudanças da tarefa num lugar só, contra o ponto de
  partida da worktree, e não só contra o HEAD como o diff de hoje.
- Uma aba de revisão por worktree: todos os arquivos juntos, a árvore de arquivos ao lado, trocar a
  base (outro commit ou branch), stage por trecho e por linha, j/k para o próximo e o anterior
  arquivo, n/p para o próximo e o anterior trecho, recolher regiões sem mudança, quebra de linha,
  mostrar espaços.
- Diff de imagem (lado a lado, deslizar, sobrepor) e conflito de merge em três vias, resolvido por
  bloco.
- Comentar em qualquer linha ou intervalo do código gerado, em Markdown, e mandar tudo de volta ao
  agente da worktree num texto só, de uma vez, sem copiar número de linha.
- Ver no diff o que o agente escreveu e o que o dono escreveu (autoria por linha), para saber onde
  olhar com mais cuidado.

## O que eu não quero
- Refazer o que o source-control já faz: o painel, stage por arquivo, commit, push, pull, branches e
  o diff de um arquivo (lado a lado ou unificado) continuam como estão (`docs/spec/source-control.md`).
- Mandar texto ao agente com Enter: os comentários vão por bracketed paste, sem Enter, como o
  seletor de elementos (ADR 0018); o dono lê e aperta Enter.
- Autoria no git: fica só no Cadex, fora do repositório; exportar é uma ação explícita.
- Ler o log das conversas para achar autoria: a fonte são os eventos de ferramenta que os hooks
  das sessões do Cadex já mandam (plano 19). Sessão aberta fora do Cadex não tem autoria.
- Travar com diff grande: 5 mil linhas em 50 arquivos abrem e rolam sem engasgo; o diff é calculado
  fora da linha principal e só o que aparece é desenhado.
- Reimplementar o git: stage parcial e conflito passam pelo binário `git`, como o resto do
  source-control.
- Código do Orca como referência (ADR 0004): só o comportamento descrito na doc dele.
- Ação só em tecla, botão ou menu: cada uma é um comando com id (ADR 0005). As teclas de uma letra
  (j, k, n, p, c) valem só com a aba de revisão em foco e são configuráveis.
- Por enquanto: o Windows ganha o núcleo (diff contra base, stage parcial, conflito); a aba de
  revisão, comentários e autoria chegam com o port.

## Como eu quero
**Fases:**
- **A. ADR e specs.** Nenhum código.
  - ADR 0027 (docs/adr/0027-local-authorship.md, a criar): autoria por linha local. A feature
    review contribui ao kit da sessão um hook PostToolUse (Edit, Write, MultiEdit, NotebookEdit),
    ao lado dos do plano 19; o Cadex grava intervalos por arquivo, nunca o conteúdo da conversa; edição
    no disco sem evento de agente vira humana; nada vai para o git; exportar é ação do dono.
  - docs/spec/review.md (a criar, modelo do `docs/spec/README.md`): aba de revisão, comentários,
    envio, autoria, estados e critérios. `docs/spec/source-control.md` ganha Diff contra base,
    Stage parcial, Imagem e Conflito em três vias.
  - Termos no `docs/CONTEXT.md`: Revisão, Base da revisão, Comentário de revisão, Autoria.
  - Feita em 2026-11-15: a ADR 0027, `docs/spec/review.md` (aba, comentários, envio, autoria) e
    `docs/spec/source-control.md` (Diff contra base, Stage parcial, Imagem, Conflito em três vias),
    os quatro termos. O New Task do plano 19 grava o branch de partida, não um commit: a base padrão
    é o merge-base com ele, e assim continua certa quando o branch anda.
- **B1. Diff de revisão no núcleo** (`core/features/source-control/`), uma sessão:
  - diff.zig ganha o diff de uma worktree contra uma base: a base é o ponto de partida gravado
    pelo plano 19 (worktrees.new-task); sem ele, o merge-base com a branch padrão; trocar para
    qualquer commit ou branch. Entram staged, não staged e novos, numa lista de arquivos com os
    trechos de cada um. Também o diff entre duas worktrees (as pontas de dois branches), que a
    corrida do plano 24 usa para comparar concorrentes.
  - Stage e unstage parciais em actions.zig: o núcleo monta o patch só do trecho ou das linhas
    escolhidas e aplica com `git apply --cached` (e `--reverse` para unstage), dentro do workspace
    autorizado e com o tempo limite de sempre. Arquivo novo: a primeira linha staged faz `add -N`.
  - API C nova em c_api.zig (`cadex_git_review_*`), listas em linhas com tab como as de hoje;
    testes em repo_test.zig.
  - Feita em 2026-11-15: `core/features/source-control/review.zig` (base, arquivos, um arquivo, duas pontas) e `core/features/source-control/partial.zig`
    (recorte do patch e o `git apply --cached --recount`), cinco funções `cadex_git_review_*`. As
    linhas escolhidas são índices no texto do patch que o núcleo deu (`cadex_git_review_patch`):
    a aba (B2) mapeia o que o dono marcou para elas. Testes em `core/features/source-control/review_test.zig`, ao lado do
    repo_test.zig, com repositórios de verdade; `add -N` + recorte conferido com o git 2.50.
- **B2. A aba de revisão no app** (`apps/macos/features/source-control/`), outra sessão:
  - ReviewDocument.swift (a criar), uma aba (TabDocument) com a árvore à esquerda (`MenuTableView`
    compartilhado) e os arquivos empilhados à direita numa vista de texto só, que desenha o que
    aparece (como a conversa do subagente, que trocou uma view por entrada por uma vista só: 25 MB
    a menos). Abre contra a base ou entre duas worktrees.
  - Recolher regiões sem mudança (padrão 3 linhas de contexto, "mostrar mais" expande), quebra de
    linha, mostrar espaços, numeração dos dois lados.
  - Comandos (todos `git.review-*` nesta fase; `review.*` fica para comentários e autoria):
    git.review-open (e o botão no grupo da worktree em Agents e no cabeçalho do Git),
    git.review-compare-worktrees, git.review-set-base, git.review-stage-hunk,
    git.review-unstage-hunk, git.review-stage-lines, git.review-unstage-lines,
    git.review-next-file (j), git.review-prev-file (k), git.review-next-hunk (n),
    git.review-prev-hunk (p), git.review-toggle-collapse, git.review-toggle-wrap,
    git.review-toggle-whitespace. Configurações git.reviewContextLines, git.reviewWrap,
    git.reviewShowWhitespace. Features: source-control, worktrees, shortcuts, command-palette,
    settings.
  - Feita em 2026-11-15: a aba numa vista só que desenha o que aparece (50 arquivos com 100 mudanças
    montam em menos de 1,5 s, testado), a lista à esquerda, os 14 comandos, as três configurações, e
    as entradas em Tasks, no grupo da tarefa em Agents e no cabeçalho do Git. j/k/n/p são atalhos
    comuns de comandos que ficam indisponíveis fora da revisão em foco, e a tecla segue adiante. O
    stage casa as linhas da revisão com as do patch (`ReviewStaging.swift`). Conferido no app de
    release com um repositório de teste: a aba, as regiões recolhidas, rename e apagado, n andando
    entre as mudanças com a lista acompanhando, e o stage de uma mudança só pelo ⌘K. Achou e
    corrigiu: o fundo cinza da lista e o rename sem conteúdo mostrando o arquivo. O app ficou em
    49,7 MB (limite 50).
- **C. Imagem e conflito.**
  - Imagem (png, jpg, gif, webp, heic, pdf de uma página): os dois lados pelo ImageIO, em três
    modos: lado a lado, deslizar (uma barra separa antes e depois) e sobrepor (opacidade). Comando
    git.review-image-mode. Acima de 20 MB, só os tamanhos e "Abrir o arquivo".
  - Conflito: arquivo com U abre em três vias (base `:1`, nossa `:2`, deles `:3`, lidas por
    `git show` no núcleo) e o resultado embaixo; por bloco, "Ficar com a nossa", "Ficar com a
    deles", "As duas" e editar à mão no resultado; "Marcar resolvido" grava e faz o stage. Comandos
    git.accept-ours, git.accept-theirs, git.accept-both, git.mark-resolved. Marcador de conflito que
    sobrou impede o "Marcar resolvido", com aviso.
- **D. Comentários e envio em lote.** Feature nova `review` (apps/macos/features/review/, a
  criar, só app): pasta com `CLAUDE.md`, testes e linha na tabela do `CLAUDE.md` da raiz. Ela não
  importa o source-control: o app liga a aba de revisão aos comentários pela porta de entrada de
  cada uma.
  - Passar o mouse numa linha mostra "+" na margem; clicar, arrastar ou c com o cursor na linha
    abre o comentário (Markdown, ⌘Enter salva, Esc cancela). Um intervalo fica dentro do trecho.
  - O comentário guarda o arquivo, o lado, as linhas, o texto delas e 3 linhas de contexto; quando
    o diff muda (o agente mexeu de novo), ele é reposicionado pelo contexto; sem achar, fica
    "desatualizado" no topo do arquivo, com o trecho antigo, até o dono apagar ou mover.
  - "Enviar ao agente" (review.send-comments) junta todos num texto só, na ordem dos arquivos: para
    cada um, o caminho, as linhas, o trecho citado e o comentário. Vai por bracketed paste, sem
    Enter, para o terminal do agente da worktree (o do plano 19), só num programa que aceita
    colagem segura; senão, para a área de transferência com aviso. Enviados saem da lista e ficam
    num histórico da worktree.
  - Guardados por worktree em `~/Library/Application Support/Cadex/review/<repo>/<worktree>.json`
    (a criar) até enviar ou apagar; sobrevivem a reiniciar o app.
  - Comandos review.add-comment, review.edit-comment, review.delete-comment, review.send-comments,
    review.clear-comments, review.show-sent. Features: review, source-control, worktrees, agents,
    terminal.
- **E. Autoria por linha.** Na feature `review`, com o hook da ADR 0027.
  - O hook PostToolUse (entra pelo kit da sessão do plano 18; `cadex hook` manda ao app.sock do
    plano 19) leva a sessão, a ferramenta, o arquivo e as linhas escritas. Testado em 2026-11-14
    (Claude Code 2.1.325): o `tool_response` de um Edit traz `structuredPatch` com `oldStart`,
    `newStart` e as linhas (`-`/`+`), o que acerta mesmo quando o `new_string` aparece mais de uma
    vez; o mesmo `tool_response` traz `originalFile` (o arquivo inteiro), que o `cadex hook` corta:
    ao socket vai só o patch, nunca o arquivo. Write sem patch marca o arquivo todo. O que ficar
    ambíguo fica sem marca, nunca marcado errado. Grava por arquivo uma lista de intervalos
    agente/dono, contra a mesma base da revisão.
  - Mudança no disco sem evento do agente (o watcher do explorer avisa) compara com a última versão
    conhecida e passa as linhas tocadas para "dono".
  - O diff mostra uma marca discreta na margem das linhas do agente; review.toggle-authorship liga e
    desliga; review.export-authorship salva um JSON (arquivo, intervalos, sessão) onde o dono
    escolher.
  - Guarda em `~/Library/Application Support/Cadex/review/<repo>/<worktree>-authorship.json` (a
    criar): intervalos, não conteúdo; a última versão conhecida de cada arquivo tocado fica em disco
    só até a worktree ser removida, com limite de 2 MB por arquivo (o mesmo do diff) e 50 MB por
    worktree, e depois disso a autoria daquele arquivo para.
  - Custo esperado: um evento por edição do agente e uma leitura do arquivo editado; parado, nada.
    Configuração review.authorship (ligada); desligada, a feature não contribui o hook
    PostToolUse ao kit. Features: review, agents, worktrees, explorer.
- **F. Peso e fechamento.** Cenário no `tools/perf/run.py`: uma worktree falsa com 50 arquivos e 5
  mil linhas mudadas, a aba de revisão aberta e rolando, 20 comentários e autoria ligada com 200
  eventos falsos; limites de memória e tempo para abrir escritos ao lado com o motivo; tudo
  desligado igual ao de hoje. Todos os ids novos em `MAC_ONLY` de `tools/check_command_parity.py`:
  o Windows ganha o núcleo, mas nenhum comando, até o port trazer a aba. README com a revisão.
  Notas da release em inglês.

## Como validar
- `make check` passa a cada fase, com os ids novos aceitos pelo `tools/check_command_parity.py`.
- Fase A: a ADR 0027 cita os hooks do plano 19 e o kit do plano 18; docs/spec/review.md e
  `docs/spec/source-control.md` com critérios; `make manifests` passa.
- `make core-test` (fase B1): repo_test.zig ganha diff contra base (ponto de partida e merge-base),
  diff entre duas worktrees, stage e
  unstage de um trecho e de linhas soltas (o índice fica com só aquelas linhas), arquivo novo com
  linha parcial, conflito com os três lados lidos e "marcar resolvido" recusado com marcador
  sobrando; tudo em repositórios temporários e sem vazamento.
- Fase B2: numa worktree do plano 19 com commits do agente, a revisão mostra tudo desde o ponto de
  partida; trocar a base para outro branch muda a lista; comparar duas worktrees mostra só o que
  difere entre elas; j/k/n/p andam certo; stage de uma linha aparece no painel do Git como staged
  parcial.
- Fase C: um png alterado nos três modos; um conflito de merge num repositório de teste resolvido
  por bloco e commitado.
- Fase D: comentários em 3 arquivos, o agente muda uma linha comentada e o comentário acompanha;
  apagar o trecho deixa o comentário "desatualizado"; "Enviar ao agente" cola o texto no terminal
  da worktree sem Enter; com outro programa na frente, vai para a área de transferência.
- Fase E: com eventos falsos de Edit (com `structuredPatch`, inclusive o caso de `new_string`
  repetido) e Write, as linhas certas ficam marcadas como do agente; o `originalFile` nunca chega
  ao socket; editar uma delas no editor do Cadex ou no disco passa para o dono; com
  review.authorship desligado, o kit gerado não tem PostToolUse e nada é gravado.
- `make perf` nas fases B a F: o cenário de 5 mil linhas dentro dos limites; tudo desligado igual
  ao de hoje.
- Conferência à mão pelo método do `docs/plans/README.md` (`CADEX_BACKGROUND=1`, menus,
  `screencapture -l`), numa tarefa real feita por um agente numa worktree.
