# 0036 — O que o dono escreve no Cadex chega ao agente: o pedido inicial e a resposta pelo sino

Data: 2026-11-17 · Status: aceita · Amplia `docs/adr/0033-cadex-launches-agents.md` e
`docs/adr/0023-answer-agent-permissions.md` · Planos `docs/plans/26-frame.md` (o sino) e
`docs/plans/29-entrances.md` (a tela de início e a Nova tarefa)

## Contexto
Os mockups da moldura nova (`docs/adr/0035-work-frame.md`) têm dois lugares onde o dono escreve para
o agente sem ir ao terminal:
- a caixa "What do you want to do?" da tela de início e o campo do pedido da folha Nova tarefa
  (⌘N): Enter abre o agente já trabalhando no pedido;
- o campo "Answer…" do cartão de pergunta no sino.

A ADR 0033 deixa o Cadex abrir agente com prompt só quando o dono liga corrida, orquestração,
automação ou o agente de memória, para o Cadex nunca gastar a conta sozinho. A ADR 0023 deixa o
Cadex responder só permissões, pelo hook do kit; pergunta não tem esse canal. O dono, 2026-11-17:
"1. sim" (responder pelo sino) e "pode ser" (o pedido como prompt).

## Decisão
- **O pedido que o próprio dono escreve abre o agente com esse prompt.** Vale para a caixa da tela
  de início e para a folha Nova tarefa (uma tarefa ou uma corrida): é o dono quem pede, como se
  digitasse `claude` e colasse o pedido. O prompt vai como na ADR 0033: argumento do exec ou
  arquivo lido pelo `claude`, nunca dentro de um comando de shell. Nada abre sem o Enter (ou o
  botão) do dono, e a corrida continua com o teto dela.
- A linha do `CLAUDE.md` da raiz passa a dizer: "o Cadex os abre com prompt quando o dono escreve o
  pedido (tela de início, Nova tarefa) ou liga corrida, orquestração, automação ou o agente de
  memória, sempre com teto no que roda sem ele".
- **A pergunta do agente pode ser respondida pelo sino.** O Cadex digita a resposta no terminal
  daquele agente, pelo mesmo digitar que já usa para comandos (espera o terminal pronto), e só se,
  logo antes de digitar, o agente ainda está naquela pergunta (o estado de pergunta do hook e do
  OSC 7501); se ele já seguiu, a resposta não é digitada e o cartão diz "The agent moved on".
  Pergunta com opções (o menu da TUI) mostra as opções como botões no cartão, e o Cadex manda a
  tecla da opção; texto livre vai como texto mais Enter. Permissões continuam pela ADR 0023, pelo
  hook.

## Consequências
- O agente que nasce do pedido do dono não conta como "o Cadex iniciou sozinho": não precisa de
  orchestration.enabled. A corrida (2+ agentes) continua precisando dela ligada e do teto.
- O cartão de pergunta no sino ganha o campo e os botões das opções (plano 26, fase D); a
  pergunta respondida some do sino como some na TUI.
- Responder pelo sino uma sessão aberta fora do Cadex não é possível (o Cadex não tem o terminal
  dela): o cartão tem só "Go to tab".
