# 0033 — O Cadex abre agentes com prompt: corrida, orquestração e automação

Data: 2026-11-16 · Status: aceita · Revê `docs/adr/0019-agents-observe-only.md` ("o Cadex não
inicia agente") e a linha "launcher de agentes" do `CLAUDE.md` da raiz · Generaliza
`docs/adr/0021-cadex-managed-accounts.md` (abrir sem prompt) e `docs/adr/0029-memory-agent.md` (o
agente de memória) · Amplia a lista de comandos do agente de `docs/adr/0024-agent-tools.md` · Plano
`docs/plans/24-many-agents.md`

## Contexto
O dono quer vários agentes trabalhando de uma vez, sem sair do Cadex (2026-11-14, sobre o Orca:
"automações, orquestração, mesma tarefa em três agentes… muito bons"): a mesma tarefa em N agentes
para comparar, uma execução com tarefas encadeadas despachadas a agentes que reportam, e um prompt
que roda sozinho num horário.

Até aqui o Cadex abre agente só **sem prompt**: o agente de uma conta (ADR 0019), retomar,
continuar em outra conta, nova tarefa e relançar depois de hibernar (ADR 0021), sempre digitando
um comando numa aba. A única exceção com prompt é o agente de memória (ADR 0029), um `claude -p`
fora das abas, desligado e com teto. A ADR 0024 deu ao agente uma lista fechada de comandos do
Cadex e disse que só outra ADR a amplia (esta).

Visto em 2026-11-14 (Claude Code 2.1.325):
- `claude "<prompt>"` interativo, com o prompt como **argumento do exec**, passa aspas, `$HOME`,
  crases, `;`, `&&`, `|` e quebras de linha intactos, e o turno começa sozinho;
- numa pasta nunca confiada, o interativo segura o prompt no diálogo de confiança e o `claude --bg`
  sai com "Workspace not trusted"; numa worktree, vale a confiança do repositório principal
  (`docs/spec/worktrees.md`, testado em 2026-11-15);
- `claude --bg` + `claude agents --json` + `claude attach <id>` roda e acompanha uma sessão sem aba
  (a página Agents já mostra essas sessões, `docs/spec/agents.md`).

Os termos: a posição da ADR 0029 vale aqui sem mudar. Uso automatizado da assinatura, sem o dono
disparando, é zona cinzenta pelos Consumer Terms §3(7) ("automated or non-human means" fora de
chave de API); por isso vem desligado, com teto, e com a chave de API pelo `apiKeyHelper` do
Claude Code sugerida. A página de legal and compliance do Claude Code (lida em 2026-11-14) aceita o
`claude` do usuário usado por ele, sem intermediar credencial.

## Decisão
- **O Cadex abre agentes com prompt, nas sessões dele.** Uma aba de terminal com `claude` e o prompt
  inicial, na conta escolhida pelo `CLAUDE_CONFIG_DIR`, com o kit da sessão dos planos 18 a 20
  (hooks, status line, `cadex`, MCP, skills). Só em quatro casos, todos ligados pelo dono: corrida,
  orquestração, automação (feature `orchestration`, `docs/spec/orchestration.md`) e o agente de
  memória (ADR 0029, que não muda).
- **O prompt nunca passa pelo shell.** O Cadex grava o prompt num arquivo dele
  (`…/Cadex/orchestration/prompts/<despacho>.md`, 0600) e digita na aba só
  `cadex claude --cadex-prompt-file <caminho>` e as opções (conta, modelo, modo de permissão), todas
  com valores que o próprio Cadex gera e confere (nada do texto do dono). O `cadex claude` (o mesmo
  do `claude` digitado, plano 22 C) lê o arquivo, apaga e passa o conteúdo como **um elemento do
  argv** no exec do `claude`. Vale para o despacho, para a sub-tarefa que o agente pede
  (`spawn`: o texto vira arquivo, não comando) e para a automação. Outra porta qualquer para o
  prompt (concatenar no comando digitado, colar no prompt da TUI) está recusada.
- **Em outra máquina** (o mínimo do "Rodar em", ADR 0031), onde não há `cadex`: o texto vai pela
  entrada padrão de um `ssh` à parte (BatchMode, sem terminal) para um arquivo novo do `mktemp` lá,
  que devolve o caminho; o Cadex confere que o caminho só tem letras, números, `/`, `.`, `_` e `-`,
  e a aba roda `claude "$(cat <caminho>)"` e apaga o arquivo: o texto só existe como saída de uma
  substituição entre aspas, que o shell não expande de novo (a entrada do `ssh` da aba é o teclado
  do dono, por isso o texto não vai por ela). Sem kit lá, o despacho remoto não reporta (só o estado do
  `claude agents --json`), como a ADR 0031 já diz.
- **O prompt não volta.** O arquivo é apagado ao ser lido, e os argumentos guardados para relançar
  depois de hibernar (plano 19) não levam o `--cadex-prompt-file`: relançar é `--resume`.
- **Confiança antes.** Antes de abrir, o Cadex confere que a pasta (ou o repositório principal da
  worktree) já é confiada pelo Claude Code, lendo sem escrever; sem confiança, a execução não
  começa e o dono é avisado. O Cadex não escreve no `.claude.json` (ADR 0021).
- **Separação por caso, para os termos:**
  - **Corrida e orquestração disparadas pelo dono** (um clique ou o ⌘K, com o dono vendo antes o
    que vai rodar) são o `claude` sem modificação numa aba, o dono usando o Claude Code: o caso que
    a página de legal and compliance aceita. Um coordenador que é agente e despacha sub-tarefas
    continua dentro da execução que o dono abriu e aprovou, com os tetos dela.
  - **Automação por horário** é o caso automatizado da ADR 0029: desligada por padrão, com teto de
    gasto e de duração por execução; a automação nova sugere a chave de API pelo `apiKeyHelper` da
    conta, e usar a assinatura é **escolha explícita do dono, por automação**, com o aviso na tela
    de ligar. O Cadex não guarda, lê nem passa a chave: quem a usa é o Claude Code.
- **Tetos sempre.** Cada execução tem teto de gasto (o `cost` da sessão que o `cadex statusline`
  grava, ADR 0021), de duração e de agentes (orchestration.maxAgents, padrão 6), e sub-agentes têm
  profundidade máxima (orchestration.maxDepth, padrão 2). Passou do teto, o Cadex encerra o agente
  (SIGTERM no `claude`, como a hibernação) e marca o motivo. Parar um agente para os filhos dele.
- **Desligado por padrão e de custo zero desligado:** orchestration.enabled e
  orchestration.automations nascem desligadas; desligadas, nenhum banco aberto, nenhum timer,
  nenhum LaunchAgent (`docs/adr/0034-scheduled-automations.md`).
- **Nada de stream-json nem Agent SDK.** O Cadex não lê a resposta do agente nem conversa com ele:
  sabe do agente pelos hooks, pelo OSC 7501 e pelo que o agente reporta (abaixo). O motor
  stream-json fica para outra ADR. Nada de proxy, token ou login tocado (ADR 0021).
- **Aba ou `--bg`:** a aba é o padrão (o dono vê e responde ali); rodar com `claude --bg` e
  acompanhar pelo `claude agents --json` foi pesado na fase B do plano 24 (2026-11-16) e ficou de
  fora por ora: sempre aba, até um teste mostrar que os hooks e a status line do kit chegam a uma
  sessão em segundo plano (o registro guarda o modo, para entrar sem mudar o banco).

### A lista de comandos do agente, ampliada (ADR 0024)
Entram seis comandos, só aceitos de uma sessão que tem `CADEX_DISPATCH_ID` (um despacho de uma
execução, posto pelo kit) e só sobre a execução desse despacho:
- orchestration.report-done (o despacho terminou, com um resumo) e orchestration.report-heartbeat
  (sinal de vida): o Cadex precisa saber que o agente acabou ou segue vivo sem ler a conversa; os
  hooks dizem "parou", não "concluiu a tarefa".
- orchestration.ask: a pergunta vai ao coordenador ou ao dono, na caixa de entrada da execução;
  sem isso o agente supervisionado só tem a TUI, que ninguém olha numa execução de vários.
- orchestration.send-message: um recado a outro despacho da mesma execução, entregue pela caixa de
  entrada dele (o agente lê com `cadex`, o Cadex não digita no terminal do outro).
- orchestration.inbox: o agente lê a própria caixa (respostas às perguntas, recados); só leitura,
  e só a do despacho dele. Sem ela, o `ask` e o `send-message` não teriam volta.
- orchestration.spawn: uma sub-tarefa, dentro dos tetos e da profundidade; o texto vira arquivo de
  prompt, e o dono vê a sub-tarefa no quadro antes de ela passar por um portão, se houver.
Fora da lista continuam: aprovar ou recusar portão, parar despacho, ligar automação, escolher
vencedor de corrida e tudo que a ADR 0024 já recusava. Portão é do dono, sempre.

Acrescentado na fase D2 (2026-11-16), com a spec que já dizia "nova tentativa só pelo dono ou pelo
coordenador": orchestration.retry, aceito só da sessão do coordenador de uma execução (um agente
coordenador tenta de novo a tarefa que falhou, sem esperar o dono). E o kit libera os sete
comandos e o `cadex skills get` no `permissions.allow` do Claude Code: perguntados a cada vez, uma
execução de vários agentes pararia no dono a cada reporte; eles só mexem no estado do Cadex, e o
app os recusa de qualquer sessão que não seja de um despacho ou coordenador.

### O que muda na ADR 0019 e na raiz
- "O Cadex não inicia agente" passa a: o Cadex abre agentes sem prompt nos casos da ADR 0021, e com
  prompt só nos quatro casos acima, sempre ligados pelo dono e com teto.
- A linha do `CLAUDE.md` da raiz passa a: "Modo em blocos e terminal privado ficaram de fora.
  Agentes rodam em abas de terminal; o Cadex os abre com prompt só quando o dono liga corrida,
  orquestração, automação ou o agente de memória, sempre com teto."
- O resto da 0019 continua: o Cadex observa pelo que o Claude Code grava, não embute chat, não
  chama modelo e não lê resposta.

## Alternativas recusadas
- **Pôr o texto do prompt dentro do comando digitado**, mesmo escapando aspas: um escape errado e
  um `$()` ou uma crase do prompt vira execução no shell do dono; o argv do exec não passa por shell
  nenhum, e no remoto o texto só chega por arquivo.
- **Colar o prompt na TUI depois de abrir:** depende do tempo da TUI subir, mistura com o que o
  dono digitar e é indistinguível de digitação automatizada.
- **Stream-json ou Agent SDK agora:** o Cadex passaria a ler e escrever a conversa, o que é outro
  produto e outra discussão de termos; a aba já dá o que o dono pediu.
- **Liberar ao agente aprovar portões ou parar despachos:** o portão existe para o dono decidir.
- **Ligado por padrão, ou sem teto:** agente que gera agente gastando o plano do dono sem ele ver.
- **Copiar o Orca pelo código:** ADR 0004; só o comportamento descrito na documentação dele.

## Consequências
- Feature nova `orchestration`, só no app macOS (`docs/spec/orchestration.md`); o kit ganha
  `CADEX_DISPATCH_ID`; o `cadex claude` ganha `--cadex-prompt-file`; a lista do agente em
  `docs/spec/agent-tools.md` ganha os seis comandos.
- Os critérios dizem que nenhum prompt com aspas, `$()` ou quebra de linha é executado pelo shell,
  e que nada roda com orchestration.enabled desligada.
- Propor abrir agente sem o dono ligar, tirar os tetos, passar o prompt pelo shell ou deixar o
  agente aprovar portão é desfazer esta decisão.
