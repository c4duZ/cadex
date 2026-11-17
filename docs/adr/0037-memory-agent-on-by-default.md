# 0037 — O agente de memória nasce ligado

Data: 2026-11-17 · Status: aceita; o código vem pelo handoff `handoff-memoria-ligada.md` (Downloads do
dono) · Desfaz o "desligado por padrão" de
`docs/adr/0029-memory-agent.md`; o resto dela vale

## Contexto
A ADR 0029 fez do agente de memória (um `claude -p` na conta, aberto pelo `cadex-memory`, o
provedor do ai-memory) uma opção desligada por padrão, por ser uso automatizado da assinatura sem o
dono disparando, na zona cinzenta dos Consumer Terms §3(7), e recusou "ligado por padrão" com esse
motivo. O dono, 2026-11-17: "o agente de memória sempre tem que nascer ligado. É o ai memory. Faz
muita diferença." E, sobre as propostas aprovadas sozinhas como no ai-memory: "tudo isso é nascer
ligado aqui."

## Decisão
- memory.backgroundAgent passa a ser **ligado por padrão**, para quem instala e para quem nunca
  mexeu na chave; quem a desligou à mão continua desligado.
- memory.requireApproval passa a ser **desligada por padrão**, como no ai-memory (que aprova as
  propostas sozinho): as regras e lições que o agente propõe entram na wiki, registradas na página
  Memory com o que entrou e como desfazer. Quem a ligou à mão continua com a aprovação.
- Tudo o mais da ADR 0029 continua: roda por evento (nunca por relógio), com o teto
  memory.dailyBudgetUsd por dia e o `--max-budget-usd` por chamada, a fila de um trabalho por vez,
  o ambiente limpo e as ferramentas só de memória. Se o engine passa a ficar ligado o tempo todo
  (avaliado no handoff), vira outra ADR, que revê a 0028.
- O risco dos termos fica escrito: o dono escolheu o padrão ligado sabendo dele. A página Memory e
  a primeira abertura dizem que o agente está ligado, o que ele gasta e como desligar, e continuam
  sugerindo a chave de API pelo `apiKeyHelper` como alternativa.

## Consequências
- A ADR 0029 ganha a nota "padrão revisto pela 0037"; o "Alternativas recusadas → Ligado por padrão"
  dela fica como histórico.
- A spec de memória e o texto das configurações dizem ligado por padrão.
- O `make perf` passa a medir o agente ligado no cenário padrão (ele roda por evento, então parado
  não pesa).
