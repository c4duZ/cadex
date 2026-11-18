# As telas da moldura nova, descritas

Cada mockup desta pasta descrito em texto: o que aparece, em que ordem, os textos, o que cada
clique faz e as variações. Vale junto com o mockup (o desenho) e com `tokens.json` (os valores);
se o link do canvas sumir, isto e os arquivos `.dc.html` bastam. Os textos da interface estão em
inglês, como no app (português é opção, ADR 0015). Escrito em 2026-11-17.

## O que eu quero
- Quem implementa uma tela lê a seção dela e sabe tudo o que o mockup decide, sem adivinhar.
- Toda tela tem seção aqui e toda seção é citada por um plano da moldura (linha "Telas:" de cada
  plano); `tools/check_design_tokens.py` confere os dois sentidos.

## O que eu não quero
- Descrição que contradiz o mockup: mudou um, muda o outro na mesma tarefa.
- Dados de exemplo (nomes de tarefa, valores, horários) tomados como regra: são só para mostrar.

## Como eu quero
As peças de toda tela (barra de título, árvore, painel da direita, barra de status) estão descritas
uma vez, nas seções das peças, no fim; as telas dizem só o que muda nelas.

### Home.dc.html — 0 · Tela de início
- **Quando aparece:** sem projeto aberto, e pelo comando de mostrar a tela de início. Quem já
  estava trabalhando abre direto onde parou.
- **Moldura:** barra de título sem abas de terminal, árvore à esquerda, painel da direita fechado,
  barra de status.
- **Centro, uma coluna de 760 centrada, de cima para baixo:**
  1. "Good evening" (saudação pela hora) e, abaixo, "Pick up where you were, or start something."
  2. A caixa do pedido: "What do you want to do in **cadex**?" com o cursor; embaixo, separadas por
     uma linha, as escolhas "◆ Claude · bkdg ▾" (agente e conta) e "In this folder ▾" (onde roda) e,
     à direita, "↩ opens a terminal with Claude". Enter abre um terminal no projeto com o agente
     escolhido e o pedido (ADR 0033); "In this folder" pode virar uma cópia separada (vira tarefa).
  3. Quatro cartões lado a lado, cada um com ícone, título, uma frase e o atalho:
     - Terminal: "A shell in the project's folder. Nothing else." (⌘T);
     - Agent: "A terminal already running Claude or Codex, in the account you pick." (⌘⇧A);
     - Task: "A separate copy on a new branch, so it works in parallel with you." (⌘N);
     - Race: "The same task given to 2–3 agents; you keep the best." (⌘N, then + agent).
  4. "RECENT PROJECTS" e, à direita, "Open folder ⌘O · Clone…"; uma linha por projeto: nome,
     caminho, estado em cor (âmbar "2 terminals open · 1 needs you", verde "Claude finished", cinza
     "nothing open") e quando.

### NewTask.dc.html — 0b · Nova tarefa (⌘N)
- **Folha** centrada sobre a tela da tarefa, com o fundo escurecido.
- **De cima para baixo:**
  1. "New task" e "in cadex" (o projeto).
  2. O campo do pedido, com várias linhas.
  3. "WHERE": duas opções lado a lado. "○ In the project's folder" (Works on your files, on main.
     One at a time.) e "● Separate copy · branch cache-evict" (Runs in parallel; you review and
     merge after.), a escolhida com borda azul e fundo azulado. O nome do branch sai do pedido e
     pode ser editado.
  4. "WHO DOES IT": uma linha por agente (número, agente e conta, quanto do limite já usou, ✕);
     "+ Add another agent". Com 2 ou mais, aparece o aviso âmbar "⚑ With 3 agents this is a race:
     each gets its own copy, you compare and keep one. Cap US$ 1.00 · 20 min each."
  5. Rodapé: "Opens as terminals in the sidebar under cadex", Cancel e o botão principal, que diz
     "Start task ⌘↩" com um agente e "Start race ⌘↩" com dois ou mais.
- O que hoje são perguntas em sequência (autorizar a pasta, hooks novos, confiança do Claude)
  aparecem como linhas desta folha (plano 29).

### Map.dc.html — 1 · A moldura (diagrama)
Não é tela: mostra as cinco regiões e o que mora em cada uma (barra de título, esquerda, centro,
direita, barra de status), com as mesmas regras das seções das peças abaixo. Fora da conferência
de tokens.

### Main.dc.html — 2 · Uma tarefa
- **Barra de título** com "cadex › orchestration-e" e as abas dos terminais da tarefa: "Claude"
  (ativa, anel azul), "npm run dev" (ponto verde), "make macos-test" (anel azul pequeno), "Review",
  e "+". Botão do painel da direita aceso.
- **Árvore** com orchestration-e selecionada e os três terminais dela abertos embaixo.
- **Centro:** um painel com foco (contorno e halo), o Claude Code vestido (ver Pane, tela 10): o
  cabeçalho "Claude · orchestration-e · Opus · bkdg · US$ 0.31 · 4 min", a conversa e a caixa de
  entrada.
- **Direita:** o painel da direita na aba Changes (ver a peça Inspector).

### Terminals.dc.html — 3 · A mesma tarefa em três terminais
- Painel da direita fechado; a aba da barra de título vira "Terminals · 3".
- **Centro:** à esquerda, o Claude grande (com foco); à direita, empilhados, "npm run dev" (ponto
  verde, a etiqueta azul "Open :5173 in preview" no cabeçalho, a saída do Vite com o endereço
  sublinhado) e "make macos-test" (anel azul, "running 38 s", as linhas "ok" em verde e "…
  TerminalTests" em azul). Os sem foco ficam com 92% de opacidade.
- Dividir: ⌘D à direita, ⇧⌘D para baixo; arrastar o cabeçalho move o painel; o vão entre painéis
  é de 8.

### PreviewOne.dc.html — 3b · Um terminal e o preview
- Na tarefa checkout-copy (bhband-site): o Claude à esquerda, o preview à direita, meio a meio.
- **O Claude** rodou o `npm run dev` ele mesmo; a caixa de entrada mostra a etiqueta azul
  "[button.pay]" seguida do pedido, porque o dono escolheu o elemento no preview.
- **O preview:** barra com ‹ › ⟳, o endereço "localhost:5173/checkout" com ponto verde, "⌖ Pick
  element" (etiqueta azul) e os tamanhos ▭ ▯; a página do site; o elemento escolhido com contorno
  azul de 2 e a etiqueta "button.pay · sent to Claude" em azul acima dele.

### PreviewMany.dc.html — 3c · Vários terminais e o preview
- À esquerda, empilhados: o Claude (maior), "npm run dev" (":5173 · in preview") e "npm test --
  --watch" ("12 passed", linhas ✓ em verde, "… watching for changes" em azul); à direita, o
  preview como em 3b.

### Project.dc.html — 4 · A página de um projeto
- Abre no centro ao clicar no nome do projeto na árvore (o cabeçalho do projeto fica marcado).
  Abas na barra de título: Overview (ativa), Automations, Conversations. Painel da direita na aba
  Memory.
- **De cima para baixo:**
  1. "cadex" grande, o caminho, o branch com "↑3" e o remoto; à direita "Race…" e "New task ⌘N".
  2. Quatro números em cartões: Tasks open (4; "1 working · 1 needs you"), This week (US$ 6.40;
     "23 sessions · 3 accounts"), Merged (11 PRs; "last: bell-cards, 22m"), Memory (214 pages;
     "+3 today").
  3. Duas colunas: "RECENT CONVERSATIONS" (uma linha por sessão: estado, título, tarefa · agente ·
     conta, quando; inclui as sessões abertas fora do Cadex) e "AUTOMATIONS" (nome, quando roda e
     o último resultado, liga/desliga verde), e embaixo "ACCOUNTS USED HERE" (etiquetas com o uso,
     âmbar acima de 80%).

### Bell.dc.html — 5 · O sino
- Popover de 400 que desce do sino da barra de título.
- **Cabeçalho:** "Needs you" com o número em âmbar e, à direita, "Activity" (a outra vista).
- **Cartões dos pedidos abertos**, o mais urgente primeiro:
  - permissão: "Wants to run Bash", "1 min", o comando em monoespaçada ("make perf"), "projeto ·
    tarefa · agente · conta", e Allow, Deny e, à direita, "Go to tab";
  - pergunta: "Asks a question", "now", a pergunta, a origem, um campo "Answer…" e "Go to tab".
    Enviar a resposta digita no terminal do agente (`docs/adr/0036-owner-words-reach-the-agent.md`);
    pergunta com opções mostra também um botão por opção, acima do campo.
- **"EARLIER":** linhas curtas com estado, o que houve e quando ("bell-cards finished · PR #41
  ready", "hero-images failed · exited", "Memory learned 3 pages · cadex").
- Responder aqui responde no terminal; no painel do agente fica o diálogo do Claude, e responder
  num fecha o outro (o cartão no pé do painel da tela 10 saiu no plano 33, pelo dono).

### Switcher.dc.html — 6 · ⌘J
- Painel de 600 no alto da tela, com o fundo escurecido.
- Campo "Jump to a task, or type to start one" e "⌘J".
- Grupos por atenção, nesta ordem: "NEEDS YOU", "FINISHED", "WORKING"; cada linha com o estado, o
  nome, "projeto · o que espera ou faz" e o atalho ⌘1, ⌘2…; a primeira linha vem marcada.
- No fim, "+ New task in **cadex**… ⌘N": digitar algo que não acha tarefa vira o pedido da Nova
  tarefa.

### Board.dc.html — 7 · O quadro
- Abre no centro pelo botão do quadro na barra de título; painel da direita fechado.
- **Filtros** em pílulas: "All" (ativa), "Race: kite (3)", "Run: release-2.4 (5)", "Automations";
  à direita "New race" e "New task".
- **Quatro colunas por estado**, com o estado, o nome e a contagem: "Needs you" (cartões com fundo
  âmbar escuro), "Working", "In review" (roxo), "Done" (fundo verde escuro).
- **Cartão:** estado, nome, idade; o que está fazendo ou esperando; "projeto · agente" e +/−; e,
  quando faz parte de algo, a etiqueta azul "Race: kite #1" ou "Run: release-2.4".

### Race.dc.html — 8 · Uma corrida
- Abre no centro. Barra de título "cadex › race kite" com as abas "Contenders · 3" e "Compare".
- Acima das colunas: o pedido entre aspas, "from main · cap US$ 1.00, 20 min each" e "Compare…".
- **Uma coluna por concorrente:** "#1 Claude Opus · bkdg", tempo; "Working / Finished / Waiting for
  you", custo e "+88 −41 in 4 files"; a barra do teto (cinza, âmbar acima de 80%); a saída do
  terminal dele; "Review" e "Pick winner". A coluna com foco tem o contorno com halo.

### Drawer.dc.html — 9 · A gaveta de terminais
- Sobe de baixo, por cima do centro (entre a árvore e o painel da direita), com 340 de altura e
  sombra para cima.
- Abas: "zsh ~/Cadu/Trabalho" (ativa), "ssh pc" (ponto verde), "htop", "+"; à direita "⌃` show or
  hide · drag up to resize · ⌘↩ move to a task".
- Para terminais rápidos que não são de projeto nenhum; ⌘↩ leva o terminal da gaveta para um
  projeto.

### Pane.dc.html — 10 · O painel do Claude Code, hoje e vestido
- **Esquerda, "TODAY":** como o Claude Code aparece hoje (fora da conferência de tokens).
- **Direita, "DRESSED BY CADEX":**
  1. Cabeçalho do painel: estado, "Claude", "orchestration-e · Opus · bkdg", à direita custo e
     tempo.
  2. A conversa nas cores do tema: a mensagem do dono com fundo próprio; ⏺ por passo (verde para
     ferramenta que terminou, âmbar para Bash); "⎿ Read 196 lines"; o diff com fundos verde e
     vermelho suaves; "✻ Wiring the wake check… 12s · esc to interrupt" em azul.
  3. A caixa de entrada com borda arredondada e a status line numa linha só: modelo, contexto com
     barrinha, custo, a pasta e o modo à direita.
  4. Barra de rolagem de 8 com uma marca por mensagem do dono (âmbar onde o agente pediu algo).
  5. O cartão de permissão no pé: ponto âmbar com halo, "Wants to run Bash", o comando, Allow e
     Deny. Saiu no plano 33 (o dono, 2026-11-18): dentro do painel fica o diálogo do próprio Claude;
     o cartão fica no sino.
- A geometria do que o Claude desenha é dele; o Cadex dá a moldura, as cores, o respiro, a status
  line, as marcas e o cartão (plano 28, fase A, mede o que vale).

### Anatomy.dc.html — 11 · A linha de tarefa, os estados, o uso e para onde foi cada página
- **A linha de tarefa:** estado, nome (negrito quando há novidade, sem número), etiqueta de PR/CI
  quando há (verde aberto, âmbar checagens falhando, roxo mesclado), idade (desde a última troca de
  estado); embaixo, agente · conta, o diff e o que espera em âmbar. Passar o mouse mostra o
  comentário da tarefa e Go to Tab / Review / Hibernate; sub-agentes dobram sob a linha.
- **Seis estados, e nada mais em cor:** Working (o único que se mexe: o anel gira), Needs you
  (conta no sino e no Dock), Done, Failed, Idle e In review. Superfícies cinza neutras, texto em
  três tons; o destaque do tema só marca foco e linha escolhida.
- **O uso:** a etiqueta da barra de status ("Claude bkdg 84% · resets 3h") abre um popover com
  cada conta (nome, plano, quando zera, barra, "84% of the 5-hour window · 61% of the week") e
  "Open an agent on… · Add account · Accounts settings".
- **Para onde vai cada página de hoje** (a mesma tabela de `inventory.md`).

### Sidebar.dc.html — peça · A árvore do trabalho (esquerda)
- **Topo:** "New task ⌘N" e o botão de filtro e agrupamento.
- **Projetos:** cabeçalho dobrável com ▾, nome, branch e a contagem de tarefas; clicar no nome abre
  a página do projeto (marcado quando aberta).
- **Linha de tarefa** como na anatomia; a selecionada com fundo e contorno, e embaixo dela os
  terminais dela (ponto de estado, nome, uma nota: "Opus", ":5173", "38s").
- "+ Add project".
- **Pé:** "Automations · 2 on · next 09:00" e "Archive & history ⌘⇧H".
- Projeto sem tarefa mostra só os terminais da pasta dele (plano 27).

### Rail.dc.html — peça · O trilho e a coluna lateral (ADR 0038, plano 36)
- **Trilho (56 pt):** os projetos em quadrados de 38 pt com a marca (a imagem do projeto, depois a
  letra), o escolhido com um halo suave, do mesmo tamanho dos outros; a peça de estado no canto (só o que se deve ver) e o ponto de
  terminal aberto embaixo; o "+"; no pé, depois de uma linha, Projects e Automations, aceso o da
  página aberta.
- **Coluna lateral (260 pt):** no topo, só os ícones das páginas (Files, Changes, Memory, Git
  graph), o aceso com o fundo escolhido; a página; no pé, a linha de contexto com os botões da
  página.

### Inspector.dc.html — peça · O painel da direita
- **Abas:** Changes, Files, History, Memory e "⌥⌘I"; a ativa sublinhada.
- **Linha de contexto:** "orchestration-e · against main" (ou, em Memory, "cadex · the project's
  memory, shared by every task and account"), e à direita os botões da aba, ícones de 14 em caixas
  de 24, até três e o "⋯" (Changes: fetch, pull, push; Files: novo arquivo, nova pasta, recolher;
  History: abrir numa aba; Memory: organizar, reindexar, o briefing).
- **Changes:** seletor "Last turn / Task / Uncommitted"; um arquivo por linha (M âmbar ou A verde,
  nome, pasta, +/−); no pé, "make check passed · 2 min ago" com ponto verde e os botões "Commit…" e
  "Open PR".
- **Memory:** "Search what this project knows"; "LEARNED TODAY" com cartões (título e "tipo · de
  qual tarefa · agente"); "WIKI" com Decisions, Gotchas, Concepts e Sessions e as contagens; no pé,
  "Each new agent here starts with a 2 KB briefing of this. See the briefing".
- **Files e History não foram desenhadas:** são a árvore de arquivos e o histórico do git de hoje,
  com as linhas e os tokens das abas acima (plano 26 desenha as duas antes de implementar).

### InspectorFiles.dc.html — peça · O painel da direita, aba Files (a aprovar)
- A árvore de arquivos da seleção (a pasta da tarefa ou do projeto), uma linha de 28 por item:
  ▸/▾ nas pastas, o ícone do tipo (o Material do app, no lugar dos blocos coloridos do desenho),
  o nome em 13, e à direita a letra do git (M âmbar, A verde); arquivo mudado tem o nome em âmbar.
  Cada nível recua 16. O arquivo aberto no centro fica com o fundo e o contorno da linha escolhida.
- As ações de hoje continuam no cabeçalho da aba e no clique direito (novo arquivo, nova pasta,
  recolher, renomear, revelar…).

### InspectorHistory.dc.html — peça · O painel da direita, aba History (a aprovar)
- Os commits da seleção, do mais novo para baixo, cada um em duas linhas: à esquerda a faixa do
  grafo (linha de 2 e um ponto de 10: azul cheio no commit de onde se está, contorno nos outros);
  a mensagem em 13 (seminegrito no atual) com as etiquetas de branch e tag; embaixo "autor · há
  quanto · hash curto".
- Clicar num commit abre os arquivos dele logo abaixo (letra, caminho, +/−) e marca a linha;
  clicar num arquivo abre o diff no centro. O resto como hoje (`docs/spec/inspector.md`).

### StatusBar.dc.html — peça · A barra de status
- Esquerda: "cadex · main ↑3", "● 3 working" (azul), "● 2 need you" (âmbar).
- Direita: "Terminal ⌃`", "Memory · 214 pages", a etiqueta âmbar "Claude bkdg 84% · resets 3h" (só
  acima de 80%; abaixo, texto comum), "Local" (ou a máquina onde roda).

### TitleBar.dc.html — peça · A barra de título
- Os botões da janela do macOS; a busca "Search ⌘K"; onde se está ("cadex › orchestration-e");
  as abas do que está aberto, cada uma com o estado do que roda nela; "+" (novo terminal no
  projeto ou na tarefa).
- À direita: o quadro, o sino (com o número em âmbar) e o botão do painel da direita (aceso quando
  aberto). Por tela, as abas mudam: tarefa (os terminais e Review), terminais divididos
  ("Terminals · 3"), projeto (Overview, Automations, Conversations), quadro (Board), corrida
  (Contenders, Compare).

## Como validar
- `tools/check_design_tokens.py` falha se um `.dc.html` não tem seção aqui ou se uma seção não é
  citada por nenhum plano da moldura.
