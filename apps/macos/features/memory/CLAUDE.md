# memory (app macOS)

## O que eu quero
- O que o app põe na memória do projeto (`../../../../docs/spec/memory.md`,
  `../../../../docs/adr/0028-project-memory.md`, plano `../../../../docs/plans/22-memory.md` fase C):
  os hooks da memória e o ambiente deles em toda sessão que o Cadex abre, pelo kit
  (`../../shared/session-kit/`), a pasta da memória automática do Claude por projeto, e o
  aquecimento do engine na primeira abertura de cada versão.
- Com memory.enabled desligada, nada disso: o app tira a parte do kit e não aquece.

## O que eu não quero
- Falar com o `cadex-memory` daqui: quem fala com o memory.sock é o cliente do núcleo
  (`../../../../core/features/memory/hook_client.zig`), que os hooks rodam.
- Os hooks da memória dependendo de agents.stateHooks: aquela chave é só dos hooks do app.
- Importar outra feature: o app (`../../app/MemoryWiring.swift`) liga esta ao kit e às configurações.

## Como eu quero
- `MemoryKit.swift`: `part` monta o `SessionKitPart` da memória: em `hooks`, um
  `cadex memory-hook <evento>` (5 s, sem matcher, então o PostToolUse pega toda ferramenta; o hook
  de autoria da revisão fica à parte e, numa edição, os dois rodam) em SessionStart,
  UserPromptSubmit, PostToolUse, PreCompact, PostCompact, SubagentStart, SubagentStop, Stop,
  StopFailure (o turno que um erro da API terminou, no lugar do Stop; ai-memory 3.5.0) e
  SessionEnd; na `env`, `CADEX_MEMORY_BIN` (o engine, `findEngine`: Contents/Helpers no pacote,
  senão o build de debug do `make app` em `core/features/memory/server/target/debug`),
  `CADEX_MEMORY_DIR` (`folder`: Application Support/Cadex/memory, ou o CADEX_MEMORY_DIR do app numa
  instância de teste) e, só numa instância de teste (CADEX_SOCKETS_DIR, CADEX_SESSIONS_DIR no
  ambiente do app), `CADEX_MEMORY_SOCKET` e `CADEX_SESSIONS_DIR`. Com
  memory.shareAcrossAccounts desligada, o `perAccount` da parte põe `CADEX_MEMORY_WORKSPACE` com a
  chave da conta da sessão (`accountKey` do kit): cada conta grava e lê a sua workspace no engine.
  Em `pluginDirs`, o plugin com as skills do próprio ai-memory (`findPlugin`: Resources/memory-plugin
  no pacote, senão o que o `make app` escreve em `core/features/memory/server/target`, pelo
  `cadex-memory export-plugin`; plano 22 fase D).
  Com memory.consolidateInSession (fase F), a `env` leva `CADEX_MEMORY_CONSOLIDATE_AT` (o
  memory.consolidateAtContext). `requestConsolidation` deixa o pedido de "tarefa pronta" de uma
  sessão (`<memória>/consolidate/requests/<sessão>.ready`, 0600, só id simples), que o hook lê no
  Stop seguinte; `consolidateNowText` é o que o memory.consolidate-now cola.
  O `perSession` da parte, quando quem abre a sessão sabe a pasta dela, põe `autoMemoryDirectory`
  na pasta do projeto (`MemoryProject.swift`); sem pasta conhecida, fica a padrão do Claude.
- `MemoryOff.swift` (plano 35 I; spec "Desligar"): o off-projects.json na pasta da memória
  (`write`, as raízes canônicas, 0600, por rename; `roots`), que o kit e o engine leem; `isOff` (a
  pasta sob uma raiz, ou o checkout principal dela, a worktree de uma tarefa fora da raiz: a regra
  do engine, `../../../../core/features/memory/server/src/off.rs`); a pausa de uma conversa em
  `paused/<sessão>` (`setPaused`, `isPaused`, só id simples, 0600; `prunePaused` tira as de mais de
  30 dias). O `appliesTo` da parte do kit (MemoryKit.part) a deixa de fora de uma sessão numa
  pasta desligada: sem hooks, sem CADEX_MEMORY_DIR (o `cadex mcp` não oferece as ferramentas da
  memória), sem plugin, sem `autoMemoryDirectory`. A `MemoryProjectForm` tem, como primeira linha,
  "Memória neste projeto" quando o app dá `setMemoryOn`; desligada, só essa linha aparece. Quem
  guarda o interruptor é o arquivo de projetos (feature projects) e quem liga tudo é o app
  (`../../app/MemoryOffWiring.swift`).
- `MemoryAgent.swift` (fase G, ADR 0029): `Config` (o que o dono escolheu: ligado, teto por dia,
  aprovação, a conta padrão e as de cada projeto, o `claude`) e `write`, o `<memória>/agent.json`
  (0600) que o engine lê a cada trabalho; `appToken`, o token do próprio app na pasta de tokens
  (memory-agent.token, feito uma vez); `environment` e `run`, o `cadex memory-agent` fora da linha
  principal, com o JSON de volta; também o texto puro (o briefing), os bytes (`runData`, o painel) e
  o stdin (write-page).
- A aba Memory do painel da direita (fase H; plano 26 fase C2c; refeita em 2026-11-18, o dono
  achou dura e difícil de ler): `MemoryView.swift`, numa rolagem só (antes a árvore da wiki rolava
  dentro da rolagem da aba), no desenho da proposta aprovada: desligada, o texto e "Turn On";
  ligada, sob o título "What the project knows" da linha de cima, "<projeto> · N pages · updated…",
  "Search memory" (memory.search), as seções com o número apagado, até 3 propostas com Approve/Reject, "LEARNED TODAY" (as páginas de hoje,
  sem os registros de sessão), "PROJECT RULES" (as da pasta _rules da wiki), "LAST SESSIONS" pelo título da
  conversa (`titleOf`, do índice do histórico: o nome dado, senão o do Claude), a conta e a pasta,
  sem as sessões vazias (plano 35 H, `listedSessions`: a página de sessão do upstream sem prompt nem
  ferramenta, ou a conversa que o histórico tem sem prompt, `isEmptySession`),
  "All sessions" (project.show-sessions) e "All N pages" (project.show-memory, com o estado do
  engine e do agente na dica); o clique numa linha abre a página do projeto nela (plano 34 G) e o cartão do pé, "Every new agent here starts with the briefing of this." com
  See What the Next Agent Gets e Configure; as sessões sem ícone, com o logo da conta na segunda linha.
  `MemoryRows.swift`: a linha (`MemoryRow`: o tipo como ícone colorido num quadradinho, `MemoryKind`;
  o título numa linha; a idade, `MemoryAge`; acende sob o ponteiro; clique abre, clique direito dá
  Open, Open the Session, Reveal in Finder e Delete Page) e `MemoryText`. `MemoryParts.swift` (a
  busca, os rótulos, os cartões das propostas, a nota), `MemorySearch.swift` (a busca no ⌘K pelas
  páginas: título, tipo, caminho e resumo), `MemoryWiki.swift` (a wiki lida da pasta: só .md, sem
  .git nem arquivos ocultos, pastas primeiro, páginas mais novas primeiro; o frontmatter e a origem:
  sessão, agente, hora), `MemoryData.swift` (o JSON do `overview`, do `status`, das `proposals` e o
  projects.json), `MemoryPageState.swift` (o que a página mostra e os textos do estado; os custos com
  as casas que importam) e `MemoryCommands.swift` (memory.show, memory.search, memory.show-briefing numa aba só de
  leitura, "The Next Agent Will Get" no título e no topo: a prévia do próximo início, não o que uma
  sessão recebeu (plano 35 H), memory.reindex, memory.refresh, memory.enable, memory.approve e memory.reject com a lista
  das propostas no ⌘K; memory.show-history, os commits da wiki na aba do Git History). As ações da
  aba ficam todas, com nome, no "…" da linha de cima (`../../app/InspectorWiring.swift`).
- `panel/` (plano 40 C; `../../../../docs/plans/40-memory-panel.md`): a página Memória, o painel do
  ai-memory redesenhado nativo, com o JSON das rotas do engine (o app as lê pelo `cadex memory-agent
  panel`, MemoryAgent.runData). `panel/PanelData.swift` (PanelOverviewData.parse: projetos,
  agentes, fila e captura; `MemoryPanelInfo`, a versão do upstream), `panel/PanelOverviewModel.swift`
  (o modelo puro: as somas, a ordem estável, o escopo, o filtro, "N de M"; `PanelWords`, os números,
  o "há 9 horas" e as frases), `panel/PanelOverviewView.swift` (a Visão geral: os cinco números
  clicáveis, a captura com o ⓘ, o aviso da fila, o filtro e os seletores, os cartões; setas, Enter e
  ⌘O), `panel/PanelCards.swift` (o número e o cartão, com o menu de contexto), `panel/PanelParts.swift`
  (o clique, o link, o ⓘ com popover e accessibilityHelp, o seletor no menu do app),
  `panel/PanelSections.swift` (`MemoryPanelSection`, os nove destinos em três grupos, e
  `MemoryPanelNav`, a busca e as linhas que o app põe na barra lateral) e `panel/PanelDocument.swift`
  (`MemoryPanelDocument`, a página; a Visão geral e as telas de um projeto desenhadas, as outras
  seções dizem "Em breve."). As telas de um projeto (plano 40 D): `panel/PanelPlace.swift`
  (`PanelPlace`, o lugar da página e os argumentos do memory.show-panel; a trilha; `PanelTrail`,
  voltar e avançar; `PanelPath`, os caminhos escapados), `panel/PanelNavigation.swift` (as rotas de
  cada lugar, `PanelLoads`; ir, voltar e avançar; ler uma rota de cada vez e montar a tela; uma
  leitura antiga que chega tarde não desenha), os dados puros (`panel/PanelProjectData.swift`:
  resumo, páginas, sessões, agentes, uso de tokens; `panel/PanelDetailData.swift`: a página, as
  evidências, o histórico e as linhas do diff; `panel/PanelSessionData.swift`: a linha do tempo, as
  recuperações e a barra de páginas; `panel/PanelProjectModel.swift`: a árvore do Conhecimento com o
  `is_system_page` do upstream e as palavras), a moldura das telas (`panel/PanelScreen.swift`: a
  rolagem, a trilha, o título, as abas; ⌘[ e ⌘]), as peças (`panel/PanelTable.swift`, a tabela e o
  selo; `panel/PanelSessionList.swift`, as sessões com "Abrir no Cadex" na linha sob o ponteiro, no
  clique direito e no ⌘O, Enter abre; `panel/PanelTokensBox.swift`, o uso de tokens com "Filtrar…" num
  popover com os dez filtros do upstream; `panel/PanelPagerBar.swift`; `panel/PanelPageTree.swift`) e
  as telas: `panel/PanelProjectView.swift` com `panel/PanelProjectTabs.swift` (o projeto e as cinco
  abas; um número abre a aba com o filtro do upstream), `panel/PanelPageView.swift` (a página, as
  evidências, Citada por), `panel/PanelMarkdown.swift` (o Markdown desenhado nativo, sem WebView: as
  linhas como o MemoryPageText e as marcas de cada linha pelo Foundation, como o AgentMarkdown; um
  link de página abre a página no painel), `panel/PanelHistoryView.swift` (o diff e as versões com De
  e Para), `panel/PanelSessionView.swift` (a linha do tempo; j/k e as setas),
  `panel/PanelRetrievalsView.swift` e `panel/PanelAgentView.swift`.
  Pesquisar e o grafo (plano 40 E): `panel/PanelSearchData.swift` (`PanelSearchQuery`, o lugar e a
  rota `extra/search`; `PanelSearchResult`; `PanelMarked`, o `<mark>` do engine em faixas e o título
  marcado pelas palavras, sem acento nem caixa), `panel/PanelSearchView.swift` (a tela: os seletores,
  o campo, "Explicar classificação", o rastro, os resultados; ↑ ↓ e Enter),
  `panel/PanelSearchParts.swift` (`PanelMarkedLabel`, o destaque único desenhado com o
  NSLayoutManager, e `PanelHitRow`, o resultado com a tabela dos streams numa dobra),
  `panel/PanelWhyRow.swift` (o "por que foi recuperada" da página: a busca que a abriu, guardada na
  página, recalculada com o rastro), `panel/PanelGraphData.swift` (os dois grafos lidos, o tipo de
  cada página, as conexões, as linhas de vazio), `panel/PanelForceLayout.swift` (o layout de forças
  puro e determinístico: os ligados no meio, os soltos em anéis na borda, sem sobrepor),
  `panel/PanelGraphCanvas.swift` (o desenho em Core Graphics, o balão, Tab e setas, um elemento de
  acessibilidade por nó, pinça e arrasto; fora da linha principal a partir de 40 nós) e
  `panel/PanelGraphView.swift` (a tela, a legenda e CONEXÕES).
  Tokens: components.memoryPanel.
- `MemorySessions.swift` (plano 35 H): `received`, o briefing que uma sessão recebeu, lido do disco
  em `<memória>/agent/briefings/<sessão>.md` (o engine o guarda, plano 35 D; só id simples, as linhas
  do marcador de backfill tiradas e aparado, como o hook entrega; nil sem arquivo), e
  `isEmptyPage`, a página de sessão do upstream sem as seções Prompts e Tool calls (sessão sem
  prompt e sem ferramenta; MemoryPage.emptySession). O app põe o briefing no detalhe da sessão
  (`../../app/ProjectSectionsWiring.swift`).
- `MemoryPageText.swift` (plano 34 D e E): uma página lida para mostrar renderizada: o corpo sem o
  frontmatter em títulos, parágrafos e itens (marcas de markdown viram texto), e as tags nas duas
  formas.
- `MemoryProject.swift`: a regra da chave do projeto (a raiz do repositório principal lida dos
  arquivos `.git`: a worktree e a subpasta dão a do checkout principal; fora do git, a própria
  pasta; os 16 primeiros hex do SHA-256 do caminho), a mesma de
  `../../../../core/features/memory/server/src/project_key.rs`, com o mesmo valor fixado num teste
  de cada lado; `autoFolder` cria `<memória>/auto/[<conta>/]<chave>` (0700; a conta só com
  memory.shareAcrossAccounts desligada) e grava nela um project.json (`root`, `account`) com que o
  engine acha o projeto. Lê arquivos, sem chamar o git: roda a cada sessão aberta.
- `MemoryMarker.swift` e `MemoryProjectForm.swift` (plano 32 D): o .ai-memory.toml do repositório
  numa tela, a seção Memória da página Settings do projeto (nome e espaço, o que fica de fora,
  briefing e seu tamanho, subagentes, handoff, retomada, busca em todos, perfil); cada mudança grava
  na hora só as chaves da tela, mantendo comentários e o resto do arquivo. O que o arquivo não diz
  vale o padrão do ai-memory (o briefing desligado; plano 35 B). O painel Memory leva até ela
  ("Configurar a memória deste projeto…", memory.configure-project).
- `MemoryMarkerPlace.swift` (plano 35 B): MemoryMarker.template (o que o `ai-memory project init`
  grava, `workspace` e `project`, mais `[briefing] inject_on_session_start = true`; o resto comentado
  com o padrão do upstream e um cabeçalho dizendo o que é o arquivo), `projectName` (a pasta da raiz
  do repositório principal, a regra do `MemoryProject.swift`) e `ensure`, que cria o arquivo só se
  não existe (por `link`, que falha se o nome já existe; nunca sobrescreve); quem chama é o app
  (`../../app/MemoryMarkerWiring.swift`). `MemoryMarkerPlace`: "Só neste Mac", a linha
  /.ai-memory.toml no `info/exclude` do diretório comum do git (MemoryProject.gitCommonDir, lido
  dos arquivos), posta ou tirada exatamente; a tela escolhe entre isso e "No repositório".
- `MemoryWarmUp.swift`: `start` roda `cadex-memory --warm --data-dir <pasta>` em segundo plano
  (QoS utility, saída em /dev/null) quando a versão do app difere da guardada no arquivo
  `warmed-version` da própria pasta da memória (não em UserDefaults: uma instância de teste, com
  outra pasta, dividia as preferências do app real e aquecia a pasta real; make perf,
  2026-11-16); guarda a versão só se o engine sai 0 (falhou, tenta na próxima abertura). No `make run` a versão é "0", aquecida uma vez também.

## Como validar
- `make macos-test` (MemoryTests; o painel, `tests/PanelTests.swift`, sobre o JSON do seed gravado
  em `tests/fixtures/`: a leitura, as somas, a ordem e o filtro, as palavras em português, os
  cliques e as teclas da Visão geral, as seções, a página, e com CADEX_SNAPSHOT_DIR o
  memory-overview.png; as telas de um projeto, `tests/PanelDetailTests.swift` e
  `tests/PanelScreenTests.swift`, sobre o JSON de cada rota gravado do seed: os lugares e a trilha,
  voltar e avançar, os caminhos, cada leitura, a árvore, as palavras, o diff, o Markdown e os links,
  a barra de páginas, a página indo de tela em tela com um engine falso, os cliques e as teclas, e
  com CADEX_SNAPSHOT_DIR um PNG de cada tela; Pesquisar e o grafo, `tests/PanelSearchTests.swift` e
  `tests/PanelGraphTests.swift`, sobre o `extra/search` e os grafos gravados do seed: a leitura, as
  marcas, a rota e os argumentos, a tela e as teclas, o "por que" recalculado, o layout (o mesmo a
  cada vez, ligados mais perto, sem sobrepor), o teclado, o balão e os nomes dos nós, e os PNGs
  memory-search*.png e memory-graph*.png; o briefing guardado de uma sessão e o id recusado, a página de
  sessão vazia fora das últimas sessões; o .ai-memory.toml lido como o engine lê, gravado sem perder linha;
  o modelo, o `ensure` que não sobrescreve, o nome numa worktree e a linha do exclude): os 9 eventos e o comando de cada um, a `env` do pacote e a do
  `make run`, a workspace só sem compartilhar, os hooks com agents.stateHooks desligada, a parte
  retirada, a chave do projeto (o valor fixado igual ao do engine, worktree e subpasta no
  checkout principal, fora do git a pasta), o `autoMemoryDirectory` de uma sessão no repositório,
  na worktree, sem compartilhar e sem pasta, e o aquecimento uma vez por versão e só com saída 0
  (um engine falso em script); a memória desligada (`tests/OffTests.swift`): a sessão num projeto
  desligado, na worktree dele e com `leaving` sem a parte, outro projeto com ela, de volta ao
  religar; a pausa com id simples, 0600, retomada e podada.
- No app, sem sessão real: o `--settings` de uma sessão do kit
  (Application Support/Cadex/kit) traz os 9 hooks e a `env` da memória.
