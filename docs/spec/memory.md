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
- De cada ferramenta fica um trecho do que ela devolveu (até 2.000 bytes, o padrão do ai-memory;
  numa gravação de arquivo, a resposta do Claude traz o conteúdo gravado), para a busca achar "onde mexemos no login" pelo conteúdo. Tudo fica na pasta da memória, no Mac.
  Arquivos que não devem entrar ficam de fora pelo `[capture] ignore_paths` do `.ai-memory.toml`
  (abaixo): a chamada a um deles não é gravada.

### O `.ai-memory.toml` do repositório
- Numa tela (plano 32 D): a página Settings do projeto (ao lado de Overview) mostra as chaves que o
  Cadex lê, com palavras simples, e grava na hora só essas, deixando comentários e o resto do
  arquivo; um arquivo novo só nasce quando algo difere do padrão. Os padrões de todos os projetos
  ficam em Configurações › Memória.
- O mesmo arquivo do ai-memory, com as mesmas regras: o mais perto subindo da pasta da sessão (até a
  pasta pessoal; fora dela, até a raiz do repositório). Um arquivo só com `[capture]` não esconde o
  de cima para o resto.
- Vale: `project` e `workspace` (o nome do projeto e do espaço), `project_strategy`,
  `[capture] ignore_paths` (com `[capture]` inválido, das ferramentas de arquivo e terminal só fica o
  nome, como no ai-memory), `[briefing] inject_on_session_start` e `max_chars`,
  `inject_on_subagent_start`, `[recall] default_global`, `drop_subagent_captures`,
  `[profile] contribute`/`consume`, `[handoff]` e `[recovery] deliver_on_session_start`.
- Diferenças do Cadex: o briefing já nasce ligado (no ai-memory é preciso pedir), e o `workspace`
  da conta (com o compartilhamento entre contas desligado) vale mais que o do arquivo, porque é a
  escolha de privacidade do dono. Não vale: `identity`, `aliases`, `server` e as rotas do
  `~/.ai-memory.toml` (o Cadex é local e nomeia o projeto pela raiz do repositório principal).
- Ao fim de cada sessão: uma página da sessão e, se o trabalho ficou no meio, um handoff para a
  próxima. O handoff diz o que a sessão fez, só com o que foi capturado e só em frases de fato: os
  prompts (a primeira linha de cada, até 12), os arquivos editados (cada um uma vez, até 40), as
  ferramentas usadas com a contagem, o último prompt e, quando há, a última chamada que falhou.
  Sessão sem nada que valha um handoff fica sem. Sessão que caiu sem fim (aba fechada, cota
  estourada) vira um retrato da sessão interrompida, com as últimas observações.
- As memórias que o próprio Claude salva (a memória automática dele), nas sessões que o Cadex abre
  e no `claude` digitado numa aba, caem numa pasta por projeto dentro da memória do Cadex (por conta,
  com o compartilhamento desligado): a raiz, as subpastas e as worktrees do repositório dividem a
  pasta. O índice dessas memórias (o MEMORY.md) é refeito pelo Cadex a cada gravação, para que
  sessões simultâneas não apaguem a entrada umas das outras: as linhas que existem ficam (menos o
  link para memória apagada), cada memória sem linha ganha uma, e acima do que o Claude lê (200
  linhas, 25 KB) saem as entradas das memórias mais velhas, nunca uma linha escrita à mão.
- Cada uma dessas memórias vira também uma página da wiki do projeto (`auto/<arquivo>`), que a
  busca acha e o git guarda, com a sessão que a salvou; apagar a memória apaga a página. O que
  mudou com o processo da memória fora do ar entra quando ele sobe.

### O histórico que já existe
- Na primeira sessão de um projeto com a memória vazia, as conversas antigas do projeto entram
  sozinhas, em segundo plano e sem IA: de todas as contas (ou só da conta, com o compartilhamento
  desligado), da raiz, das subpastas e das worktrees, até 200 sessões por agente e 50 mil eventos.
  Viram sessões e observações que a busca acha, não páginas. Acontece uma vez; nunca numa memória
  que já tem conteúdo. Ficam as mais novas, gravadas na ordem em que aconteceram, sem deixar
  handoff. Se o processo sai no meio, a importação continua na próxima sessão do projeto.
- "Organize History with AI" (memory.bootstrap), na página Memory, escreve as páginas de decisões,
  armadilhas e conceitos a partir do histórico importado, pelo agente de memória
  (`docs/adr/0029-memory-agent.md`). Mostra a estimativa de custo antes e só roda no clique.

### O `claude` digitado à mão
- Nas abas do Cadex com zsh (o shell padrão do Mac), o `claude` digitado recebe o mesmo kit das
  sessões que o Cadex abre: grava na memória e recebe o briefing, na conta da aba. Com bash ou
  fish, a sessão entra na memória pela importação, sem briefing.
- Só sessões interativas. `claude -p`, `claude --version`, `claude --help` e todo subcomando
  (`mcp`, `plugin`, `update`, `doctor`, `auth`…, inclusive depois de opções, como
  `claude --model haiku mcp list`) saem exatamente iguais aos de fora do Cadex. `--bg`,
  `--remote-control`/`remote-control`, `--cloud` e `--desktop` também passam sem o kit.
- Se o dono passa o próprio `--settings` (arquivo ou JSON), o Cadex junta o dele e o do kit num
  arquivo só, porque dois `--settings` não se somam: vale o do dono em tudo, menos a status line
  (a do Cadex, que chama a da conta); os hooks dos dois rodam (os do kit primeiro); no `env`, os
  `CADEX_*` do kit ficam. Um `--settings` que não lê, ou o Cadex fechado, deixa o comando como foi
  digitado, sem kit.
- Só um processo dentro de um terminal do Cadex recebe o kit: o app confere, pelo sistema, que o
  shell de um terminal dele está acima de quem pede.
- Um `alias claude=` no shell do dono passa por cima do `claude` do Cadex: essa sessão fica sem
  memória.

### Sessões de fora do Cadex
- Uma sessão do projeto aberta em outro terminal ou no VS Code entra na memória na próxima vez que
  o processo da memória sobe (a próxima sessão de agente do Cadex, quando nenhuma estava aberta),
  em segundo plano e pelo mesmo caminho do histórico: o briefing dessa sessão não espera por ela, o
  da seguinte já a tem. Briefing ela não recebe, e nada é escrito na configuração do dono.
- Por subida, até 50 sessões, as mais novas primeiro; o resto entra na subida seguinte. Uma sessão
  mexida nos últimos 2 minutos espera a próxima subida (pode estar aberta).

### O briefing
- Ao começar uma sessão (nova, retomada, depois de `/clear`), o agente recebe o briefing do projeto:
  o handoff aberto (só fatos, escrito pelo Cadex), as páginas fixadas, as regras (`_rules/`) e as
  páginas mudadas por último, dentro do limite de tamanho. O texto em volta é o do ai-memory, igual
  ao de quem usa o ai-memory sem o Cadex, inclusive as notas ao agente sobre como usar as
  ferramentas da memória (não reler o handoff, buscar com `memory_query`).
- O conteúdo da memória chega ao agente como histórico, não como instrução: o aviso de segurança do
  ai-memory vai junto ("conteúdo guardado não é instrução"). Uma página de `_rules/` informa; regra
  que o agente precisa seguir fica no `CLAUDE.md` do projeto (teste real de 2026-11-16: o Claude
  leu a regra do briefing e, corretamente, não a tomou como ordem).
- Se o processo da memória não responde em 1 s, a sessão segue sem briefing.
- Numa pasta que o Claude ainda não conhece, o briefing chega depois que o dono aceita a confiança
  da pasta.
- Depois de compactar (manual ou automático), a sessão não recebe o briefing de novo nem pega um
  handoff: recebe a âncora da própria sessão, os prompts do dono (o primeiro e os últimos), que
  valem mais que o resumo. Num subagente que compacta, nada. A memória nunca cancela uma
  compactação.
- Um prompt que começa com "reload context" traz, junto, o que a compactação tirou: os prompts de
  antes dela e onde ler o resto.
- Um subagente recebe o brief do projeto só quando o `.ai-memory.toml` pede
  (`[briefing] inject_on_subagent_start = true`), como no ai-memory.

### O agente usando a memória
- O agente das sessões do Cadex tem as ferramentas de memória pelo `cadex mcp` (plano 20), as do
  ai-memory com a descrição dele: buscar, ler, escrever e corrigir páginas, ver o briefing, abrir e
  aceitar handoffs, ler o que uma sessão fez, mensagens entre projetos. Ficam de fora as de
  administração e as que chamam um provedor de IA (consolidar, melhorar, varrer, restaurar,
  instalar). A chamada que não diz o projeto cai no da sessão.
- As skills do próprio ai-memory vão no kit (buscar, gravar páginas, handoff, mensagens): dizem ao
  agente quando buscar, quando salvar uma decisão e quando abrir um handoff.

### Busca por sentido
- A busca acha por palavra e por sentido ("login quebrado" acha "token expira em silêncio"). O
  modelo de vetores (87 MB) é baixado em segundo plano na primeira sessão, retoma de onde parou se a
  rede cair e é conferido (SHA-256 fixado pelo ai-memory; arquivo errado é apagado); até lá, a busca
  é só por palavra. Sem rede, tenta de novo depois de 10 minutos ou na próxima vez que o processo sobe.
- Medido (2026-11-16, `make memory-eval`: as 56 ADRs e specs do Cadex como páginas, 30 perguntas de
  quem desenvolve o Cadex, em português e inglês, escritas sem as palavras do título): a página
  certa em 1º lugar em 19 de 30 só por palavra e 21 com o modelo; entre as 5 primeiras, 25 e 28.
  Gravar as 56 páginas: 1,6 s e 11 s; a busca típica: 6 ms e 15 ms (release, Apple Silicon). O
  modelo é treinado em inglês e ainda assim ajuda nas perguntas em português ("como o Swift conversa
  com o núcleo": 5º lugar por palavra, 1º com o modelo).
- O modelo só fica na memória do computador enquanto é usado: depois de 60 s parado
  (fixo, sem opção nas configurações), sai, e o processo volta ao peso de parado.

### Continuar em outro agente
- "Continue in…" (agents.continue-in-agent) escolhe agente e conta no ⌘K (ou "o último agente que trabalhou aqui") e abre uma aba na pasta do
  projeto com `cadex continue claude` ou `cadex continue codex` (que o dono também pode digitar numa
  aba do Cadex). É o `ai-memory run` do ai-memory, com o mesmo registro: o trabalho do projeto é um
  workstream; o agente que já rodou nele volta à própria sessão (`--resume`), e o outro agente começa
  uma sessão nova com o pacote do workstream no briefing e um dossiê da conversa anterior, só de
  leitura, apagado quando ele fecha. Dois agentes nunca pegam o mesmo workstream ao mesmo tempo: o
  segundo espera um pouco e é recusado. Ao fim, a conversa entra na memória (também a do Codex,
  que não tem hooks).
- Claude numa outra conta não acha a sessão da primeira: começa uma nova no mesmo workstream, com o
  pacote. Para levar a conversa inteira, "Continue in Another Account" no histórico (uma cópia).
- O Codex recebe as ferramentas de memória por argumento (`-c mcp_servers…`); os hooks dele só
  rodariam com uma pasta de configuração do Codex que o Cadex gerenciasse, nunca na `~/.codex` do dono.

### Consolidação na sessão
- Em marcos (a tarefa marcada como pronta, o contexto acima de memory.consolidateAtContext, 70%, ou
  "Consolidate Memory Now", memory.consolidate-now), o agente recebe, ao terminar a resposta, o
  pedido de consolidar a sessão, e escreve ele mesmo as páginas pelas ferramentas da memória: a da
  sessão e as de decisões, armadilhas, regras e conceitos que a sessão deixou. Uma vez por marco;
  nunca dois pedidos seguidos. O pedido aparece na conversa como uma mensagem do usuário ("Stop hook
  feedback"), e a tela do Claude Code mostra "Stop hook error occurred": é o nome que ele dá a um
  bloqueio no fim da resposta, não uma falha.
- O contexto que conta é o que o Claude Code mostrou na última atualização da linha de status, que
  vem depois do fim da resposta: o pedido chega no fim da resposta seguinte à que passou do limite.
- As regras do pedido são as do ai-memory (as que o consolidador dele dá ao modelo: só o que a
  sessão mostrou, nada inventado, o estado final vale, preferências do projeto em
  `_prompts/consolidation.md`), e as páginas saem nos caminhos e tipos dele. Sem chave e sem outro
  modelo: quem escreve é o Claude da sessão.
- "Consolidate Memory Now" cola o pedido curto no agente com foco, sem Enter; ao ser enviado, o
  pedido completo vai junto.
- memory.consolidateInSession (ligada) liga e desliga isso.

### Manutenção
- Ao subir o processo da memória e a cada fim de sessão, nunca por relógio, rodam no máximo uma vez
  por dia as limpezas do ai-memory, com os padrões dele: apaga páginas com validade vencida, tira
  da wiki as páginas de sessão e outras episódicas sem leitura há uns 80 dias (ficam marcadas no
  banco e somem de vez depois de 180 dias), apaga projetos vazios e fecha sessões paradas há 48 h;
  o lint por regras escreve `_lint/report.md` em cada projeto. Ao subir, gera os vetores que faltam.

### Agente de memória de fundo
- Ligado por padrão (memory.backgroundAgent; `../adr/0037-memory-agent-on-by-default.md`, o dono,
  2026-11-17: "sempre tem que nascer ligado"); quem desligou à mão continua desligado. Ligado, faz o que não cabe na sessão aberta com o
  `claude -p` da conta do projeto (Haiku, sem ferramentas, sem hooks, sem guardar sessão na conta,
  com teto por chamada), sempre por evento: quando uma sessão termina, consolida a página dela (a
  não ser que o próprio Claude da sessão já tenha consolidado), atualiza o perfil de trabalho e, no
  ritmo do ai-memory, propõe regras e lições (auto-improve, experience); depois de compactar,
  consolida o que houve; com o Mac parado há 10 minutos e nenhuma sessão aberta, reorganiza a wiki
  (dream), e para quando o dono volta. São os passos do próprio ai-memory, com o Claude da conta no
  lugar de um provedor com chave. Ver `docs/adr/0029-memory-agent.md`.
- Sessão sem nenhum prompt e sem nenhuma ferramenta (um painel aberto e fechado) não vira página e
  não chama o agente: o ai-memory já a fecha assim, e o agente segue a mesma regra; fica só uma
  linha sem custo no registro (plano 35 C).
- Teto por dia (memory.dailyBudgetUsd, US$ 1,00): passou, nada mais roda no dia; cada trabalho fica
  registrado com custo e versão do Claude Code. Propostas esperam aprovação na página Memory
  (memory.requireApproval: desligada por padrão pela ADR 0037, como no ai-memory, e as propostas
  entram registradas, com desfazer; ligada, esperam aprovação). "Pause or Resume the Memory Agent" (memory.pause-agent) segura a
  fila; "Reorganize Memory Now" (memory.run-dream) pede um dream.
- "Organize History with AI…" (memory.bootstrap) mostra antes a estimativa de custo (folgada) e só
  roda no sim, mesmo com o agente desligado, com o mesmo teto: o Claude da conta lê as sessões
  importadas e escreve as decisões, armadilhas e conceitos (o bootstrap do ai-memory).
- A tela de configurações avisa que os Termos de Consumidor da Anthropic (§3.7) restringem o uso
  automatizado da assinatura e sugere uma chave de API no Claude Code da conta (apiKeyHelper); o
  Cadex nunca guarda nem lê a chave.

### Página Memory
- A seção Memória da página do projeto (desde o plano 38; antes, uma página da coluna lateral), memory.show. A wiki em árvore (pastas,
  páginas mais novas primeiro), aberta e editada como Markdown; salvar com ⌘S faz da edição um
  commit (o reindex do projeto). Edição fora do Cadex entra com memory.reindex. Apagar uma página
  pede confirmação. "Show Memory History" (memory.show-history) abre os commits da wiki (cada
  gravação, reindexação e aprovação é um) na aba do Git History.
- Cada página mostra de onde veio: sessão, conta e hora, com "Abrir a sessão".
- "What the Agent Will See" (memory.show-briefing): o briefing exato da próxima sessão neste
  projeto.
- O estado do processo e do modelo de vetores (baixando, pronto, carregado); o histórico importado
  (quantas sessões, de quais contas, contado a partir desta versão); o agente de fundo (ligado,
  pausado, o gasto do dia contra o teto, a fila e os últimos trabalhos com custo); as propostas, com
  memory.approve e memory.reject (no ⌘K, a lista das pendentes).
- Com o processo parado, a página mostra a árvore e não o sobe; só "What the Agent Will See" sobe.

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
- Sessão com 10 edições -> o handoff lista os 10 arquivos.
- Sessão aberta sem pasta conhecida -> a memória automática dela fica na pasta padrão do Claude.
- Processo da memória com erro grave -> volta sozinho, sem perder evento da fila; janela e terminais
  não sentem.
- Briefing grande -> cortado no limite do ai-memory.
- Conta com `--settings` próprio no `claude` digitado -> os hooks dele e os do kit rodam juntos.
- Wiki editada em outro editor -> entra no índice ao subir o processo ou com memory.reindex.
- Codex sem pasta de configuração do Cadex -> só as ferramentas de memória, sem hooks.

## Limites conhecidos
- `alias claude=` do dono desativa o `claude` do Cadex naquela aba.
- Sessões de fora do Cadex não recebem briefing; só ensinam a memória depois, e só quando o
  processo da memória sobe de novo (com sessões do Cadex abertas o tempo todo, esperam).
- Sessão antiga cuja pasta foi apagada (uma worktree removida) não é importada.
- Uma sessão que o Cadex já gravou e que depois continuou fora dele não é importada de novo.
- O Codex foi testado sem login (2026-11-15): o caminho das ferramentas funciona; o dos hooks está
  pronto e só se confirma com uma conta.
- O pedido de consolidar fica na conversa como mensagem do usuário.
- A última resposta do assistente não entra no handoff: a captura dela está desligada.
- A memória automática das sessões de fora do Cadex, e a salva antes desta versão, fica na pasta
  padrão do Claude, fora do índice do Cadex e da wiki.
- Na hora em que o Cadex troca o texto do handoff de uma sessão que acabou de terminar (milésimos),
  uma sessão que começa não acha handoff; se ela já tinha pegado o do engine, fica com aquele.
- Se o Claude grava o MEMORY.md no mesmo instante (microssegundos) em que o Cadex grava o índice
  refeito, a gravação do Claude se perde; a entrada de cada memória volta na próxima reconstrução,
  uma linha escrita à mão naquele instante não.
- O Codex não foi testado de verdade (sem conta): o "Continue in…" para ele está pronto e testado com
  um Codex falso; os hooks dele não rodam (só a importação no fim).
- O `cadex continue` tem as opções e os agentes do `ai-memory run` (`--yolo`, `--jail`, perfis,
  `--env`, OpenCode, Kimi, Grok…), menos a instalação automática de hooks: o Cadex não grava na
  configuração dos agentes; fora do Claude e do Codex, a conversa entra na memória só pela
  importação no fim. Sem o processo da memória o agente roda mesmo assim e o próximo `cadex
  continue` recupera a conversa. Com o ai-jail, o acesso ao socket da memória de dentro da jaula não
  foi conferido com o ai-jail de verdade (só com um falso).
- Do `.ai-memory.toml`, o Cadex não lê `identity`, `aliases`, `server` nem as rotas do arquivo da
  pasta pessoal; e não confere o `ignore_paths` de outro repositório numa chamada daqui
  (`cat ../outro/segredo.env` entra).
- O código de senhas do engine e as bibliotecas de rede para baixar o modelo ficam no binário,
  sem uso por quem não pede.

## Critérios de aceite
- [ ] Abrir o Cadex sem sessão de agente não roda `cadex-memory` (`ps`).
- [ ] Uma decisão salva numa sessão aparece no briefing da seguinte, em outra conta do projeto.
- [ ] O briefing nunca passa do limite e chega com o aviso de que memória não é instrução.
- [ ] Uma worktree nova recebe o briefing do repositório na primeira sessão.
- [ ] Com memory.shareAcrossAccounts desligada, duas contas não veem a memória uma da outra.
- [ ] Quatro sessões simultâneas salvando memória deixam as quatro entradas no MEMORY.md.
- [ ] O primeiro projeto importa o histórico de todas as contas, subpastas e worktrees uma vez, sem
      atrasar a sessão; reabrir não importa de novo.
- [ ] `claude` digitado numa aba do Cadex grava e recebe briefing; `claude -p`, `claude --version`,
      `claude mcp list` e `claude --model haiku mcp list` saem iguais aos de fora.
- [ ] Uma sessão do projeto num terminal de fora entra na memória quando o processo sobe de novo,
      sem atrasar o briefing; na sessão seguinte a busca a acha.
- [ ] Com o processo morto, os eventos esperam e entram quando ele volta.
- [ ] Depois de uma compactação a sessão recebe a âncora com os prompts do dono, sem gastar o
      handoff; "reload context" traz o que a compactação tirou.
- [ ] O modelo baixa (e retoma), carrega, sai depois de parado, e o processo volta ao peso de parado.
- [ ] Marcar a worktree como pronta faz o agente escrever as páginas uma vez, sem chave configurada.
- [ ] O contexto passando de memory.consolidateAtContext pede a consolidação uma vez; com
      `stop_hook_active` nunca pede.
- [ ] "Organize History with AI" mostra o custo antes e só roda no clique.
- [ ] Numa instalação nova, memory.backgroundAgent vem ligada; desligada, nenhum `claude -p` roda.
- [ ] Editar uma página na Memory gera commit; "Abrir a sessão" leva à conversa certa.
- [ ] O briefing mostrado na Memory é igual ao que a sessão recebeu (conferido no transcript).
- [ ] O `~/.claude` e a `~/.codex` do dono não mudam.
