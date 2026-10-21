# status-bar (app macOS)

## O que eu quero
- A barra embaixo da janela montada por quem usa: itens à esquerda e à direita, em ordem, escondidos
  ou não, arrastados entre os lados (plano 17, fase B). Sem configuração, a de sempre: a trilha da
  pasta e o ambiente.

## O que eu não quero
- Item escondido, ou janela fora da tela, pesando: sem timer, sem leitura, sem requisição (regra do
  dono, 2026-10-21).
- Informação que muda a cada tecla causando redesenho da janela.
- Esta feature importando outra: o app passa os itens de branch e terminais, com os dados deles.

## Como eu quero
- `StatusItem.swift`: o item (id, título, linha do Customize, ícone, lado de costume, view) e
  `onVisible`, que liga e desliga a leitura dele; `StatusLabel`, a cara da maioria (ícone, texto,
  cor de alerta, dica, clique que roda um comando).
- `StatusBarLayout.swift`: as regras puras: os lados salvos contra os ids conhecidos (desconhecido
  ou repetido sai e vira aviso), mostrar/esconder, a lista Left/Right do Customize e a volta.
- `StatusBarView.swift`: a porta de entrada. Os itens próprios (folder, environment) e os que o app
  soma (`add`), `setLayout` com statusBar.left/right, `onLayoutChange` para o app salvar, o menu do
  botão direito (cada item com marca e "Customize Status Bar…") e a janela Customize compartilhada
  (`../../shared/customize/`). Avisa cada item quando ele pode ser visto (na barra e a janela na
  tela, pela oclusão). `path`, `canNavigate` e `onNavigate` vão para a trilha.
- `FolderTrail.swift`: a trilha "Home › … › cadex" com o menu de subpastas de cada pedaço (o do app,
  `../../shared/menus`, para cima); só se refaz quando a pasta muda. `Breadcrumb.swift`: os pedaços
  e as subpastas, puros e testados.
- `SystemStats.swift`: RAM (app + wired + comprimida, como o Monitor de Atividade), CPU (pela
  diferença de ticks) e a memória do próprio Cadex (phys_footprint), lidos a cada 2 s uma vez para o
  app inteiro, só com alguém olhando; sem ninguém, sem timer. `SystemItems.swift`: os itens RAM,
  CPU e Cadex memory.
- `StatusBarCommands.swift`: statusBar.customize, statusBar.toggle-item (a lista no ⌘K) e
  statusBar.activity-monitor (o clique em RAM, CPU e memória).
- O app (`../../app/StatusBarWiring.swift`) soma Git branch (do status que o painel do Git já lê) e
  Terminals, e salva os lados.
- Spec em `../../../../docs/spec/status-bar.md`. Status: fase B no código; Agents, Agent usage, SSH
  e Ports chegam nas fases C a E.
- Fontes e medidas principais da interface vêm de UILooks (`../../shared/looks/CLAUDE.md`): zoom, densidade e fonte da interface, lidos ao montar a tela.

## Como validar
- `make macos-test` passa: a trilha, as regras dos lados, a barra de antes sem configuração, a lista
  do Customize e a volta, e que escondido ou fora da tela o medidor não roda. Com
  CADEX_SNAPSHOT_DIR, o teste salva status-bar.png.
