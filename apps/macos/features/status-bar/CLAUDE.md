# status-bar (app macOS)

## O que eu quero
- A barra embaixo da janela montada por quem usa: itens à esquerda e à direita, em ordem, escondidos
  ou não, arrastados entre os lados (plano 17, fase B), na cara da moldura nova (plano 26, fase B;
  components.statusBar). Sem configuração, a do mockup: Project e Agents à esquerda; Memory, o uso,
  o café, a atualização e o ambiente à direita (StatusBarLayout.defaultLeft e defaultRight; a
  barra padrão de antes passa para essa uma vez, pelo SettingsFile.migrate da feature settings).

## O que eu não quero
- Item escondido, ou janela fora da tela, pesando: sem timer, sem leitura, sem requisição (regra do
  dono, 2026-10-21).
- Informação que muda a cada tecla causando redesenho da janela.
- Esta feature importando outra: o app passa os itens de branch e terminais, com os dados deles.

## Como eu quero
- `StatusItem.swift`: o item (id, título, linha do Customize, ícone, lado de costume, view) e
  `onVisible`, que liga e desliga a leitura dele; `StatusLabel`, a cara da maioria (ícone, ponto de
  estado, texto, cor de alerta, dica, clique que roda um comando), nos tokens da barra.
- `SlidingStack.swift`: cada lado da barra; os itens que mudam de lugar deslizam do lugar antigo
  (transform, sem mexer no layout) e os textos que mudam esmaecem. StatusLabel.maxTextWidth corta
  um texto longo (o branch).
- `StatusBarLayout.swift`: as regras puras: os lados salvos contra os ids conhecidos (desconhecido
  ou repetido sai e vira aviso), mostrar/esconder, a lista Left/Right do Customize e a volta.
- `StatusBarView.swift`: a porta de entrada. Os itens próprios (folder, environment) e os que o app
  soma (`add`), `setLayout` com statusBar.left/right, `onLayoutChange` para o app salvar, o menu do
  botão direito (cada item com marca e "Customize Status Bar…") e a aba Status Bar
  (`customizePage`) da janela única de `../../shared/customize/`, que o app abre. Avisa cada item quando ele pode ser visto (na barra e a janela na
  tela, pela oclusão). `path`, `canNavigate` e `onNavigate` vão para a trilha; `itemView` dá a view de um item para o app
  pôr o cartão dele.
- Plano 38 G: `only` mostra só os ids dados (nada aberto: gaveta, conta, café, ambiente) e
  `compact` (janela estreita) guarda o primeiro da esquerda e os dois primeiros da direita, o resto
  no "…" (`folded`, um menu com cada um; escolher faz o que o clique dele faz); os lados salvos não
  mudam. A regra pura é StatusBarLayout.shown.
- `FolderTrail.swift`: a trilha "Home › … › cadex" com o menu de subpastas de cada pedaço (o do app,
  `../../shared/menus`, para cima); só se refaz quando a pasta muda. `Breadcrumb.swift`: os pedaços
  e as subpastas, puros e testados.
- `SystemStats.swift`: RAM (app + wired + comprimida, como o Monitor de Atividade), CPU (pela
  diferença de ticks) e a memória do próprio Cadex (phys_footprint), lidos a cada 2 s uma vez para o
  app inteiro, só com alguém olhando; sem ninguém, sem timer. `SystemItems.swift`: os itens RAM,
  CPU e Cadex memory, cada um com o cartão dele (`SystemCards.swift`: o uso em partes, os processos
  deste usuário e o que roda nos terminais do Cadex, que o app dá; lidos só com um cartão aberto).
  `ProcessTable.swift`: os processos deste usuário (os do sistema exigem admin), CPU pela diferença
  entre duas amostras e a memória (phys_footprint), o nome do `claude` pelo caminho.
- `ListeningPorts.swift`: as portas TCP em LISTEN (com o pid de cada uma, `listeners`, para o cartão) dos processos de um grupo (o da frente de cada
  terminal), pelo libproc, sem lsof; o app faz o item Ports (`../../app/SSHWiring.swift`), lido a
  cada 10 s e na troca de aba só enquanto aparece, e só com algum terminal rodando programa.
- `StatusBarCommands.swift`: statusBar.customize, statusBar.toggle-item (a lista no ⌘K) e
  statusBar.activity-monitor (o botão dos cartões de RAM, CPU e memória; o clique no item não faz nada desde a 3.1).
- O app (`../../app/StatusBarWiring.swift`) soma Git branch (do status que o painel do Git já lê) e
  Terminals, e salva os lados.
- Spec em `../../../../docs/spec/status-bar.md`. Status: fases B a E no código (itens Agents, Agent usage, SSH e Ports somados pelo app).
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: a trilha, as regras dos lados, a barra de antes sem configuração, a lista
  do Customize e a volta, e que escondido ou fora da tela o medidor não roda. Com
  CADEX_SNAPSHOT_DIR, o teste salva status-bar.png.
