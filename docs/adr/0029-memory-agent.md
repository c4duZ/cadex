# 0029 — Agente de memória: um `claude -p` na conta, desligado por padrão

Data: 2026-11-15 · Status: aceita · Revê `docs/adr/0019-agents-observe-only.md` e a linha
"launcher de agentes" do `CLAUDE.md` da raiz, **só para o agente de memória**. Apoia-se em
`docs/adr/0028-project-memory.md`

## Contexto
O engine da memória (ADR 0028) tem tarefas que precisam de IA e que não cabem na sessão aberta:
consolidar uma sessão que parou sem marco, propor regras e armadilhas a partir de várias sessões
(auto-improve, experience), reorganizar a wiki com o computador parado (dream), montar o perfil de
trabalho do dono (profile) e organizar o histórico importado (bootstrap). No ai-memory, quem faz
isso é um provedor de LLM com chave de API ou com o token da assinatura; no Cadex, nenhum dos dois
(ADR 0021, ADR 0028).

Sobra o Claude Code do próprio usuário, numa sessão nova pelo CLI (o dono, 2026-11-14: "ele abriu
uma sessão nova pelo CLI"). Testado em 2026-11-14 (Claude Code 2.1.325): `claude -p` com o
`CLAUDE_CONFIG_DIR` de uma conta usa o login da assinatura dela e custa menos de US$ 0,01 por
chamada curta no haiku.

Os termos pesam: os Consumer Terms §3(7) proíbem acessar os serviços por "automated or non-human
means" fora de chave de API ou de permissão explícita. Um `claude -p` que o Cadex dispara sozinho,
sem o dono pedir, fica na zona cinzenta. Um que o dono dispara com um clique é o dono usando o
Claude Code.

A ADR 0019 diz que o Cadex não inicia agente, e o `CLAUDE.md` da raiz deixa "launcher de agentes" de
fora. A ADR 0021 ampliou o que o Cadex abre, sempre digitando um comando numa aba, sem prompt.

## Decisão
- **O agente de memória é um `claude -p` novo na conta**, aberto pelo `cadex-memory` com: o
  `CLAUDE_CONFIG_DIR` da conta do projeto, `--model` barato (haiku por padrão),
  `--max-budget-usd`, `--no-session-persistence`, `--mcp-config` só com as ferramentas de memória,
  `--allowedTools` limitado a elas e o ambiente limpo pelo kit da sessão. Não é sessão de terminal,
  não aparece nas abas e não fica no histórico da conta.
- **Desligado por padrão** (memory.backgroundAgent). Ligado, roda só por evento (sessão parada,
  depois de compactar, a cada N sessões, computador parado para o dream, que para quando o dono
  volta), nunca por relógio.
- **Teto de gasto:** memory.dailyBudgetUsd por dia, e o `--max-budget-usd` em cada chamada. Fila no
  `cadex-memory`, um trabalho por vez, cada um registrado com custo e versão do Claude Code.
- **Propostas passam pelo dono.** O que o auto-improve propõe (regras, armadilhas) vai para aprovação
  na página Memory (memory.requireApproval, ligada).
- **Organizar o histórico com IA** (bootstrap) só roda no clique do dono (memory.bootstrap), depois
  de mostrar a estimativa de custo. Por ser disparado pelo dono, roda mesmo com o agente de fundo
  desligado, com o mesmo teto.
- **A posição sobre os termos**, fixada aqui e citada por quem vier depois (a ADR 0033 do plano 24):
  uso automatizado da assinatura, sem o dono disparando, é zona cinzenta pelos Consumer Terms §3(7).
  Por isso vem desligado, com teto, e a tela de ligar diz isso e sugere chave de API pelo
  `apiKeyHelper` do Claude Code, configurado pelo dono na conta, como alternativa. O Cadex não guarda
  nem lê a chave: quem a usa é o Claude Code.
- **Prova antes:** a fase G do plano 22 só começa com a prova num script fora do app (login da conta,
  custo de um trabalho real, bloqueio por impressão digital), registrada com versão e custo. Sem a
  prova passando, a fase para.

### O que muda na ADR 0019 e na raiz
- "O Cadex não inicia agente" ganha uma exceção: o agente de memória, nas condições acima.
- A linha "Modo em blocos, terminal privado e launcher de agentes: ficaram de fora do Cadex" passa a
  dizer que o launcher de agentes ficou de fora, exceto o agente de memória (ADR 0029).

## Alternativas recusadas
- **Provedor de LLM por chave guardada no Cadex:** o Cadex não guarda chave (ADR 0021).
- **O token da assinatura** (o `claude setup-token`, o `anthropic-oauth` do ai-memory): intermediar
  credencial, proibido pelos termos e pela ADR 0021.
- **Proxy ou endpoint "compatível com OpenAI" na frente do `claude -p`:** a Usage Policy de
  2026-11-12 proíbe "route requests through consumer subscriptions".
- **Ligado por padrão:** uso automatizado sem o dono pedir, na zona cinzenta dos termos, gastando o
  plano dele.
- **Fazer tudo só na sessão aberta:** a consolidação em marco cobre o principal (ADR 0028), mas
  sessão que cai, dream e organizar o histórico não têm sessão aberta.

## Consequências
- Comandos memory.run-dream, memory.bootstrap e memory.pause-agent; configurações
  memory.backgroundAgent, memory.dailyBudgetUsd e memory.requireApproval.
- Desligado, nenhum `claude -p` roda (`ps`). A página Memory mostra a fila, o custo e as propostas.
- Propor ligar por padrão, tirar o teto ou disparar o agente por relógio é desfazer esta decisão.
