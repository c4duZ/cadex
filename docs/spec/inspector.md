# inspector

## Para que serve
A coluna opcional à direita da janela: o que se sabe do projeto ou da tarefa selecionada, em quatro
abas (Changes, Files, History, Memory), sem tirar os terminais do centro
(`../adr/0035-work-frame.md`; mockup e texto em `../design/work-frame/screens.md`, seção Inspector).
São as páginas que ficavam na barra lateral de ícones (Git, Files, Git History, Memory), no lugar
novo.

## Comportamento
- ⌥⌘I (inspector.toggle) e o botão à direita da barra de título abrem e fecham a coluna; o botão
  fica aceso com ela aberta. Largura padrão 320 pt; arrastar a borda muda e fica salva. Aberta ou
  fechada e a aba escolhida voltam ao reabrir.
- **Abas no topo:** Changes, Files, History e Memory, a ativa sublinhada, e "⌥⌘I" à direita. Cada
  uma tem comando para abrir a coluna já nela: git.show (⇧⌘G) abre Changes, explorer.focus (⇧⌘E)
  abre Files, git.show-history (⇧⌘L) abre History, memory.show abre Memory.
- **Linha de contexto** abaixo das abas: de que se trata ("orchestration-e · against main" numa
  tarefa; o nome do projeto fora de tarefa; em Memory, "cadex · the project's memory, shared by every
  task and account").
- **O que a coluna mostra** segue a seleção: a tarefa da aba com foco, ou o projeto quando o foco
  está num terminal fora de tarefa ou na página do projeto.
- **Cabeçalho de cada aba:** uma linha só, igual em todas, com o nome à esquerda (a pasta em Files,
  com o caminho na dica; a branch em Changes, com o ícone de branch e ↑ ↓, e o clique troca de
  branch, git.switch-branch, ou "Git" fora de um repositório) e até 3 botões à direita (o resto no
  "⋯"), sempre à vista, discretos, acesos sob o ponteiro, cada um rodando um comando:
  - Changes: fetch, pull, push e um indicador girando enquanto uma ação roda; no "⋯", trocar de
    branch, tudo para o stage, tudo fora do stage e atualizar.
  - Files: novo arquivo, nova pasta, recolher tudo; no "⋯", buscar arquivo e recarregar.
  - History: abrir o histórico numa aba.
  - Memory: inicializar, reindexar, ver o briefing; no "⋯", o histórico da memória, pausar o agente
    de memória e atualizar.
- **Changes** (o painel de `source-control.md`): o seletor "Last turn / Task / Uncommitted" (o que
  o agente mudou na última rodada, tudo da tarefa contra o ponto de partida, ou o que não tem
  commit); um arquivo por linha com M (âmbar) ou A (verde), o nome, a pasta e +/−; no pé, o último
  resultado da checagem do projeto ("make check passed · 2 min ago") e os botões "Commit…" e "Open
  PR". Clicar num arquivo abre o diff no centro. As ações de hoje (stage, unstage, descartar, abrir
  diff ao lado ou em aba) continuam, no clique direito e no ⌘K.
- **Files** (o explorer de `explorer.md`): a árvore de arquivos da pasta da seleção, com as mesmas
  ações de hoje.
- **History** (o histórico de `git-history.md`): cada commit em duas linhas, o grafo e a descrição
  (com as etiquetas de branch e tag) sobre o autor, há quanto tempo e o hash curto. Clicar num commit
  abre os arquivos dele logo abaixo, com o grafo continuando por trás; clicar de novo fecha; clicar
  num arquivo abre o diff no centro. Parar o mouse num commit mostra, em 0,2 s, a descrição inteira,
  as branches e tags, o autor com e-mail, a data completa e o hash inteiro; num arquivo, o caminho
  completo. O clique direito (e o ⌘K) tem "Show Commit Details in a Tab", "Copy SHA" e "Open on
  Remote". Fora de um repositório, "Not a Git repository".
- **Memory** (a página de `memory.md`): "Search what this project knows"; "LEARNED TODAY" com o que
  os agentes aprenderam (título e "tipo · de qual tarefa · agente"); "WIKI" com Decisions, Gotchas,
  Concepts e Sessions e as contagens; no pé, o tamanho do briefing que cada agente novo recebe e
  "See the briefing".
- Aba que ninguém abriu não lê nada; com a coluna fechada, nenhuma aba lê (o mesmo de as páginas
  de antes só lerem enquanto apareciam).
- O Changes desenhado tem o mockup; Files e History ainda não: são desenhadas no canvas com os
  tokens das abas e vistas pelo dono antes de implementar (plano 26).

## Estados
- **Sem seleção** (nenhum projeto): a coluna mostra "Open a project to see its changes, files,
  history and memory."
- **Fora de um repositório git:** Changes e History mostram "Not a Git repository"; Files e Memory
  funcionam.
- **Memória desligada** (memory.enabled): Memory explica o que está desligado e tem o botão para
  ligar.

## Casos de borda
- Janela estreita (abaixo de 1000 pt com a árvore aberta): abrir a coluna recolhe a árvore, e
  fechar a coluna devolve.
- Muitas mudanças (milhares de arquivos): a lista mostra os primeiros 500 e "N more", com o filtro.

## Critérios de aceite
- [ ] ⌥⌘I abre e fecha; o botão da barra de título acende com a coluna aberta.
- [ ] ⇧⌘G, ⇧⌘E, ⇧⌘L e memory.show abrem a coluna na aba deles.
- [ ] Trocar de tarefa no centro troca o que Changes mostra.
- [ ] Com a coluna fechada, nada é lido (medido no `make perf`).
- [ ] Toda ação que existia nas páginas Git, Files, Git History e Memory está na aba nova e no ⌘K.
