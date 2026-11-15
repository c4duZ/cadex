# 0027 — Autoria por linha, local: o que o agente escreveu, pelos hooks das sessões do Cadex

Data: 2026-11-15 · Status: aceita · Apoia-se em `docs/adr/0021-cadex-managed-accounts.md` (o kit da
sessão, plano 18) e em `docs/adr/0022-terminal-daemon.md` (os hooks por `cadex hook` até o
`app.sock`, plano 19)

## Contexto
Na revisão de uma tarefa (`docs/plans/21-review.md`), o dono quer saber, linha a linha, o que o
agente escreveu e o que ele mesmo escreveu, para saber onde olhar com mais cuidado. O git não sabe
disso: o commit é de quem commita, e o agente edita e o dono commita (ou o contrário).

As sessões que o Cadex abre já mandam eventos ao app pelos hooks do kit da sessão (plano 19:
`cadex hook <evento>` até o `app.sock`). O Claude Code também tem o hook **PostToolUse**, que roda
depois de cada ferramenta. Testado em 2026-11-14 (Claude Code 2.1.325): depois de um Edit, o
`tool_response` traz `structuredPatch` (cada trecho com `oldStart`, `newStart` e as linhas `-`/`+`),
o que acerta a posição mesmo quando o texto trocado aparece mais de uma vez no arquivo; traz também
`originalFile`, o arquivo inteiro antes da edição.

## Decisão
- **A fonte são os eventos de ferramenta das sessões do Cadex.** A feature `review` contribui ao kit
  da sessão, pela porta do kit (ninguém monta o kit dela), um hook PostToolUse para Edit, Write,
  MultiEdit e NotebookEdit, ao lado dos hooks do plano 19. Ele vai por `cadex hook`, como os outros,
  e nunca espera o app. Sessão aberta fora do Cadex não tem autoria, e o log das conversas não é lido
  para descobrir quem escreveu.
- **Só intervalos, nunca conteúdo da conversa.** O `cadex hook` corta o `originalFile` e o conteúdo
  do Write antes de mandar: ao socket vão a sessão, a ferramenta, o arquivo e as linhas tocadas (o
  `structuredPatch`). O Cadex grava, por arquivo, uma lista de intervalos "agente" e "dono", contra a
  mesma base da revisão, em `~/Library/Application Support/Cadex/review/` (por repositório e
  worktree). Para saber o que o dono mudou depois, guarda a última versão conhecida de cada arquivo
  tocado, só enquanto a worktree existe, com limite de 2 MB por arquivo e 50 MB por worktree;
  passado o limite, a autoria daquele arquivo para.
- **Na dúvida, sem marca.** Write sem patch marca o arquivo todo como do agente; o que não der para
  posicionar com certeza fica sem marca, nunca marcado errado. Mudança no disco sem evento de agente
  (o watcher do explorer avisa) passa as linhas tocadas para "dono".
- **Nada vai para o git.** Nem nota, nem trailer, nem arquivo no repositório. Exportar
  (review.export-authorship, um JSON com arquivo, intervalos e sessão) é uma ação explícita do dono,
  para onde ele escolher.
- **Desligável e de custo zero parado.** `review.authorship` (ligada); desligada, a feature não
  contribui o hook PostToolUse ao kit. Ligada, o custo é um evento por edição do agente e uma
  leitura do arquivo editado; sem edição, nada roda.

## Alternativas recusadas
- **git blame / notas do git / trailer no commit:** o blame diz quem commitou, não quem escreveu;
  notas e trailers põem no repositório o que é do Cadex e espalham para quem clona.
- **Ler o log das conversas (`~/.claude/projects`):** depende de um formato interno do Claude Code,
  lê conteúdo da conversa e chega atrasado; o hook dá o patch na hora e sem o resto.
- **Comparar o disco a cada mudança sem eventos:** não diz se foi o agente ou o dono.
- **Mandar o `originalFile` ao app:** o arquivo inteiro a cada edição, sem necessidade; o patch
  basta.

## Consequências
- Spec: `docs/spec/review.md` (Autoria). O kit da sessão ganha um hook a mais, só com
  `review.authorship` ligada; `cadex hook` aprende a cortar o `tool_response` do PostToolUse.
- Propor guardar autoria no repositório, ler o log das conversas ou mandar o arquivo inteiro ao app
  é desfazer esta decisão.
