# memory

## Para que serve
O projeto lembra. O que cada sessão de agente fez, as decisões, as armadilhas e os conceitos passam
de uma sessão para a próxima, de uma conta para outra e do Claude para o Codex, sem o dono repetir
nada. O dono vê e edita essa memória como Markdown, com o histórico do git, e vê exatamente o que o
agente recebe ao começar (`docs/adr/0028-project-memory.md`, plano `docs/plans/22-memory.md`).

## Comportamento
### Ligada desde o começo
- A memória nasce ligada (memory.enabled), com a busca por sentido. Abrir o Cadex não roda nada:
  o processo da memória (`cadex-memory`) só sobe quando a primeira sessão de agente abre num
  projeto, e sai quando a última fecha.
- A memória é por repositório: a raiz, as subpastas e todas as worktrees dele dividem a mesma
  memória desde a primeira sessão.
- memory.shareAcrossAccounts (ligada): todas as contas do projeto veem a mesma memória. Desligada,
  cada conta tem a sua (para contas de clientes diferentes).
- Os dados ficam em `~/Library/Application Support/Cadex/memory/`: a wiki (Markdown em git), o
  índice, os eventos e o modelo de vetores. Nada vai para o repositório do projeto nem para a
  configuração das contas.
- Na primeira abertura do app depois de instalar ou atualizar, o Cadex prepara o processo em
  segundo plano, para a primeira sessão não esperar por isso.

### O que entra na memória, sozinho e sem IA
- Nas sessões que o Cadex abre (e no `claude` digitado numa aba do Cadex, abaixo): os prompts, as
  ferramentas que o agente usou e em quais arquivos, as compactações, os subagentes e o fim da
  sessão. A sessão nunca espera por isso; com o processo fora do ar, os eventos esperam numa fila e
  entram quando ele volta.
- Ao fim de cada sessão: uma página da sessão (prompts, arquivos editados, último estado) e, se o
  trabalho ficou no meio, um handoff para a próxima. Sessão que caiu sem fim (aba fechada, cota
  estourada) vira um retrato da sessão interrompida, com as últimas observações.
- As memórias que o próprio Claude salva (a memória automática dele) caem na pasta da memória do
  Cadex e entram no índice. O índice dessas memórias (o MEMORY.md) é refeito pelo Cadex a cada
  gravação, para que sessões simultâneas não apaguem a entrada umas das outras.

### O histórico que já existe
- Na primeira sessão de um projeto com a memória vazia, as conversas antigas do projeto entram
  sozinhas, em segundo plano e sem IA: de todas as contas (ou só da conta, com o compartilhamento
  desligado), da raiz, das subpastas e das worktrees, até 200 sessões por agente e 50 mil eventos.
  Viram sessões e observações que a busca acha, não páginas. Acontece uma vez; nunca numa memória
  que já tem conteúdo.
- "Organize History with AI" (memory.bootstrap), na página Memory, escreve as páginas de decisões,
  armadilhas e conceitos a partir do histórico importado, pelo agente de memória
  (`docs/adr/0029-memory-agent.md`). Mostra a estimativa de custo antes e só roda no clique.

### O `claude` digitado à mão
- Nas abas do Cadex, o `claude` digitado recebe o mesmo kit das sessões que o Cadex abre: grava na
  memória e recebe o briefing, na conta da aba.
- Só sessões interativas. `claude -p`, `claude --version`, `claude --help` e todo subcomando
  (`mcp`, `plugin`, `update`, `doctor`, `auth`…, inclusive depois de opções, como
  `claude --model haiku mcp list`) saem exatamente iguais aos de fora do Cadex. `--bg` e
  `remote-control` também passam sem o kit.
- Se o dono passa o próprio `--settings`, ele continua valendo inteiro, e os hooks do kit rodam
  junto.
- Um `alias claude=` no shell do dono passa por cima do `claude` do Cadex: essa sessão fica sem
  memória.

### Sessões de fora do Cadex
- Uma sessão do projeto aberta em outro terminal ou no VS Code entra na memória quando termina,
  pelo mesmo caminho do histórico. Briefing ela não recebe, e nada é escrito na configuração do dono.

### O briefing
- Ao começar uma sessão (nova, retomada, depois de `/clear`, depois de compactar), o agente recebe o
  briefing do projeto: o handoff aberto, as páginas fixadas, as regras (`_rules/`), as decisões e
  armadilhas recentes. Só frases de fato, nunca ordens, dentro do limite de tamanho.
- Se o processo da memória não responde em 1 s, a sessão segue sem briefing.
- Numa pasta que o Claude ainda não conhece, o briefing chega depois que o dono aceita a confiança
  da pasta.
- Antes de compactar, o Cadex acrescenta ao resumo um ponto de controle da sessão (manual ou
  automático); a sessão que segue depois da compactação o recebe de volta. A memória nunca cancela
  uma compactação.

### O agente usando a memória
- O agente das sessões do Cadex tem as ferramentas de memória pelo `cadex mcp` (plano 20): buscar,
  ler, escrever e corrigir páginas, ver o briefing, abrir e aceitar handoffs, ler o que uma sessão
  fez. Só escreve dentro da memória do projeto.
- Uma skill no kit diz ao agente quando buscar, quando salvar uma decisão e quando abrir um handoff.

### Busca por sentido
- A busca acha por palavra e por sentido ("login quebrado" acha "token expira em silêncio"). O
  modelo de vetores (87 MB) é baixado em segundo plano na primeira sessão, retoma se a rede cair e é
  conferido; até lá, a busca é só por palavra.
- O modelo só fica na memória do computador enquanto é usado: depois de memory.embedIdleSecs (60 s)
  parado, sai, e o processo volta ao peso de parado.

### Continuar em outro agente
- "Continue in…" (agents.continue-in-agent) leva o trabalho de uma sessão para outro agente ou
  conta. Claude → Claude é o "Continue in Another Account" (a conversa inteira, numa cópia). Claude ↔
  Codex abre o outro agente com o workstream e um dossiê do que a sessão anterior fez, só de
  leitura, apagado quando a sessão fecha. Dois agentes nunca pegam o mesmo workstream ao mesmo tempo.
- O Codex recebe as ferramentas de memória por argumento; os hooks dele só rodam com a pasta de
  configuração do Codex que o Cadex gerencia, nunca na `~/.codex` do dono.

### Consolidação na sessão
- Em marcos (worktree marcada como pronta, contexto acima de memory.consolidateAtContext, 70%, ou
  "Consolidate Memory Now", memory.consolidate-now), o agente recebe, ao terminar a resposta, o
  pedido de consolidar a sessão, e escreve ele mesmo as páginas. Uma vez por marco; nunca dois
  pedidos seguidos. O pedido aparece na conversa como uma mensagem do usuário.
- memory.consolidateInSession (ligada) liga e desliga isso.

### Agente de memória de fundo
- Desligado por padrão (memory.backgroundAgent). Ligado, faz o que não cabe na sessão aberta
  (consolidar sessão parada, propor regras, reorganizar a wiki com o computador parado) com o
  `claude -p` da conta, com teto por dia (memory.dailyBudgetUsd). Propostas esperam aprovação
  (memory.requireApproval). Ver `docs/adr/0029-memory-agent.md`.

### Página Memory
- Página da barra lateral (ícone Phosphor), memory.show. A wiki em árvore, aberta e editada como
  Markdown; cada edição é um commit, com o histórico pelo Git History.
- Cada página mostra de onde veio: sessão, conta e hora, com "Abrir a sessão".
- "What the Agent Will See" (memory.show-briefing): o briefing exato da próxima sessão neste
  projeto.
- O estado do processo e do modelo de vetores (baixando, pronto, carregado); o histórico importado
  (quantas sessões, de quais contas); a fila do agente de fundo, com custo; as propostas, com
  memory.approve e memory.reject; memory.reindex para refazer o índice depois de editar a wiki fora
  do Cadex.

## Estados
- **Desligada:** nenhum hook a mais nas sessões, nenhum processo, a página Memory explica e oferece
  ligar.
- **Ligada, sem sessão de agente:** nenhum processo rodando; a página Memory lê a wiki e sobe o
  processo só para mostrar o briefing.
- **Primeira sessão do projeto:** memória vazia, importando o histórico e baixando o modelo em
  segundo plano; o briefing sai vazio ou só com o que já entrou.
- **Pronta:** briefing a cada sessão; busca por palavra e por sentido.
- **Processo caído:** a sessão segue sem briefing; os eventos esperam na fila; o processo volta
  sozinho.
- **Sem rede na primeira vez:** busca só por palavra até o modelo baixar, tentado de novo na
  próxima sessão.

## Casos de borda
- Quatro sessões do mesmo projeto salvando memória ao mesmo tempo -> as quatro entradas ficam no
  índice da memória automática do Claude.
- Worktree nova do repositório -> cai na mesma memória desde a primeira sessão.
- Sessão com 10 edições -> a página e o handoff listam as 10.
- Processo da memória com erro grave -> volta sozinho, sem perder evento da fila; janela e terminais
  não sentem.
- Briefing grande -> cortado no limite, nunca com ordens.
- Conta com `--settings` próprio no `claude` digitado -> os hooks dele e os do kit rodam juntos.
- Wiki editada em outro editor -> entra no índice ao subir o processo ou com memory.reindex.
- Codex sem pasta de configuração do Cadex -> só as ferramentas de memória, sem hooks.

## Limites conhecidos
- `alias claude=` do dono desativa o `claude` do Cadex naquela aba.
- Sessões de fora do Cadex não recebem briefing; só ensinam a memória depois.
- O Codex foi testado sem login (2026-11-15): o caminho das ferramentas funciona; o dos hooks está
  pronto e só se confirma com uma conta.
- O pedido de consolidar fica na conversa como mensagem do usuário.
- O código de senhas do engine e as bibliotecas de rede para baixar o modelo ficam no binário,
  sem uso por quem não pede.

## Critérios de aceite
- [ ] Abrir o Cadex sem sessão de agente não roda `cadex-memory` (`ps`).
- [ ] Uma decisão salva numa sessão aparece no briefing da seguinte, em outra conta do projeto.
- [ ] O briefing nunca passa do limite e não tem frase imperativa.
- [ ] Uma worktree nova recebe o briefing do repositório na primeira sessão.
- [ ] Com memory.shareAcrossAccounts desligada, duas contas não veem a memória uma da outra.
- [ ] Quatro sessões simultâneas salvando memória deixam as quatro entradas no MEMORY.md.
- [ ] O primeiro projeto importa o histórico de todas as contas, subpastas e worktrees uma vez, sem
      atrasar a sessão; reabrir não importa de novo.
- [ ] `claude` digitado numa aba do Cadex grava e recebe briefing; `claude -p`, `claude --version`,
      `claude mcp list` e `claude --model haiku mcp list` saem iguais aos de fora.
- [ ] Uma sessão do projeto num terminal de fora entra na memória quando termina.
- [ ] Com o processo morto, os eventos esperam e entram quando ele volta.
- [ ] A compactação automática leva o ponto de controle ao resumo.
- [ ] O modelo baixa (e retoma), carrega, sai depois de parado, e o processo volta ao peso de parado.
- [ ] Marcar a worktree como pronta faz o agente escrever as páginas uma vez, sem chave configurada.
- [ ] "Organize History with AI" mostra o custo antes e só roda no clique.
- [ ] Com memory.backgroundAgent desligada, nenhum `claude -p` roda.
- [ ] Editar uma página na Memory gera commit; "Abrir a sessão" leva à conversa certa.
- [ ] O briefing mostrado na Memory é igual ao que a sessão recebeu (conferido no transcript).
- [ ] O `~/.claude` e a `~/.codex` do dono não mudam.
