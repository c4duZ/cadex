# Plano 40 — O painel da memória, nativo

O painel web do ai-memory 3.5.0 (o crate ai-memory-web: Painel de memória, projetos, caixa de
entrada, workstreams, busca, grafo, revisão de aprendizado, saúde) trazido para o Cadex com as
mesmas telas, redesenhado em AppKit. O dono, 2026-11-19: "trazer com as mesmas telas, talvez um
pouco mais adaptado para o projeto, com o máximo de fidelidade possível [...] redesenhando nativo";
"talvez com uma aba de memória na esquerda, embaixo"; "pode seguir, escreve o plano 40 e começa
pela A".

Os nomes do upstream (crates, rotas, modelos de página) vão sem crase: não são caminhos deste
repositório. O código dele está no checkout do cargo, no commit fixado (411d90d).

## O que eu quero
- As telas do painel do upstream, uma a uma, com o mesmo conteúdo, a mesma ordem e os mesmos
  números, desenhadas com os tokens e componentes do Cadex.
- A página "Memória" no pé da barra lateral, ao lado de Quadro, Automações e Máquinas (as páginas
  do app inteiro, `docs/design/sidebar/6-estrutura-ideal.html`), com as seções dentro dela, como o
  menu da esquerda do upstream.
- Testado contra um banco falso e contra o próprio upstream (o dono, 2026-11-19: "é muito
  importante que a gente consiga testar as telas [...] contra um banco de dados falso [...] e testar
  o repositório do Fabio Akita contra o nosso [...] isso é capaz de quebrar, mesmo a gente portando
  o código idêntico"): cada número e cada lista das telas iguais aos do painel dele, sobre os
  mesmos dados, e nenhuma tela gravando na memória.
- Adaptado ao Cadex só no que ajuda: um projeto ou uma sessão levam também ao projeto e ao
  terminal no Cadex; o idioma é o do Cadex.

- Decisões do dono sobre os mockups (2026-11-19, depois da revisão de UX):
  - Uma barra lateral só: com a Memória aberta, a barra de Trabalho troca o conteúdo pelas seções
    do painel, com "‹ Trabalho" em cima; nada de segunda coluna.
  - A Memória entra no pé da barra lateral, e só isso: o item Memory da barra de baixo, a seção
    Memória da página do projeto, o inspector e Arquivo e Histórico ficam como estão, para estudar
    depois.
  - A Saúde e a linha "Captura" da Visão geral com os contadores do engine local (o cadex-memory é
    o servidor local do upstream na máquina da pessoa); sai só o que não existe localmente (os
    provedores remotos).

## O que eu não quero
- WebView (ADR 0001): as telas são nativas.
- Mudar o que existe: a seção Memória da página do projeto, o item Memory da barra de baixo e o
  inspector continuam como estão.
- Editar os crates do upstream (ADR 0028): o engine os usa e expõe os dados.
- O que é de servidor com vários usuários: login, Sair, troca de senha, a escolha de idioma.
- Ler os dados reais da memória do dono para outra coisa que não a referência da fase A, e nunca
  o original: uma cópia, apagada no fim.

## Como eu quero
- [x] A. Referência e mockups. O painel do upstream rodando sobre uma cópia do banco do dono, por
  um programa de exemplo do engine (só nos testes: o ai-memory-web como dependência de
  desenvolvimento, nunca no binário), e um print de cada tela; o inventário de cada uma (o que
  mostra, de onde vem o dado: a API JSON do upstream ou só o HTML); os mockups com os tokens do
  Cadex num .dc.html, revisados por um agente de UX contra os prints e os estudos da barra lateral;
  o dono aprova antes do código.
  Feito: o painel do upstream sobre a cópia (`core/features/memory/server/examples/web_reference.rs`),
  15 prints, o inventário (`docs/research/memory-panel-screens.md`), 13 boards Memory*.dc.html com
  `docs/design/work-frame/screens-memory.md`, revisados por um agente de UX; o dono viu os prints
  (um visualizador local dos .dc.html) e mandou montar para testar (2026-11-19). O grafo foge do
  upstream: layout de forças (as páginas ligadas se aproximam), não o círculo dele, que com muitas
  páginas vira emaranhado (o dono: "pode fazer o 2").
- [x] A2. O banco falso e a paridade, antes de qualquer tela:
  - Um seed no engine que cria uma pasta de memória de teste pelas funções do upstream (como os
    testes dele: Store, Wiki e o writer): projetos, sessões abertas e fechadas, eventos, páginas com
    histórico, regras e slots, mensagens na caixa de entrada, workstreams, propostas na revisão de
    aprendizado e uso de tokens. Sempre o mesmo resultado; os testes e os prints usam só ele.
  - Testes de paridade no `cargo test` do engine: o painel do upstream (ai-memory-web, só de
    desenvolvimento) e a nossa API sobre o mesmo seed. Onde ele tem JSON, o nosso igual; onde só tem
    HTML, os números e as listas tirados do HTML dele e comparados com o nosso JSON.
  - A memória intacta: depois de todas as rotas e telas, o banco e a wiki iguais byte a byte.
  - O `make memory-upstream-test` roda também a suíte do ai-memory-web.
  Feito: o seed (`core/features/memory/server/tests/panel/seed.rs`, e o exemplo panel_seed), os
  testes `core/features/memory/server/tests/panel_parity.rs` (todas as telas e a API do upstream
  sobre o seed, com os números; a pasta igual byte a byte depois) e a suíte do ai-memory-web no
  `make memory-upstream-test` (344 testes, 0 falhas, no Mac).
- [x] B. O engine: a API JSON do upstream (`/api/v1`: projetos, visão geral, páginas, histórico,
  recentes, briefing, handoffs, sessões, observações, busca, grafo) no socket da memória, e rotas
  nossas para o que só existe no HTML (caixa de entrada, workstreams, revisão de aprendizado, saúde,
  agentes e uso de tokens), pelas funções do upstream.
  Feito: `core/features/memory/server/src/page/panel/` sob `/cadex/memory/panel` (o token de
  sessão; quem pede é o dono): as rotas `/api/v1` que as telas usam, por handlers nossos com as
  mesmas leituras do upstream (o diff do histórico e as verificações da Saúde copiados, com a
  origem), e as rotas extra/ do que só existe no HTML; `cadex memory-agent panel --path`. O
  ai-memory-web voltou a ser só dos testes (o dono, 2026-11-19, escolheu deixar a documentação
  embutida de fora): com o `api_router` o engine crescia 4,3 MB, assim 0,35 MB (arm64). A
  Documentação abre os guias do upstream no GitHub. Paridade em `core/features/memory/server/tests/panel_api.rs`:
  cada rota igual ao `api_router` e às telas HTML do upstream sobre o seed, as recusas iguais, a
  pasta igual byte a byte depois.
- [x] C. A página Memória no pé da barra lateral, com as seções, e a Visão geral: os cinco
  números, a saúde da captura, o aviso da caixa de entrada e os cartões dos projetos com filtro.
  Feito: `apps/macos/features/memory/panel/` (os dados, o modelo puro da ordem e do filtro, a Visão
  geral, as seções, a página), a troca da barra em `apps/macos/features/sidebar/WorkSidebarMemory.swift`
  e `apps/macos/app/MemoryPanelWiring.swift` (memory.show-panel, memory.open-in-cadex); testes com o
  JSON do seed gravado (`apps/macos/features/memory/tests/fixtures/`) e o print memory-overview.png.
  Diferenças do board: as letras do cartão seguem a regra da barra lateral (cadex é CA, não CX);
  a aba da página fica sob a barra de cima, como Automações. Achado no caminho: no `make run` o app
  não achava o engine (o #filePath padrão era o do chamador), corrigido em MemoryKit.findEngine.
- [x] D. O projeto: a árvore de páginas e a atividade recente, a página (Markdown e metadados), o
  histórico com diff, a sessão (linha do tempo) e o agente (sessões e uso).
  Feito: as telas em `apps/macos/features/memory/panel/` (o projeto com as cinco abas, a página, o
  histórico com o diff, a sessão com o uso de tokens e "Filtrar…", as recuperações, o agente), cada
  lugar um memory.show-panel com `project=` e a tela, voltar e avançar (memory.panel-back e
  memory.panel-forward); memory.open-in-cadex com `session=` vai ao terminal da sessão. O Markdown é
  desenhado nativo (as linhas do MemoryPageText e as marcas pelo Foundation), sem o WebKit da
  feature markdown. Testes com o JSON de cada rota gravado do seed e um PNG de cada tela; os prints
  da instância de teste comparados com os boards. Diferenças: os ids curtos são os 8 últimos, como o
  `short_id` do upstream (o board tinha os primeiros); "Última captura" no cartão virou só a hora,
  com a frase na dica (cortava com os dois links); o histórico não pagina as versões (o seed tem 2).
  Achado: a sessão aberta do seed fecha na subida do engine; é o `close_abandoned_sessions` do
  forget sweep (sem atividade há 48 horas), o mesmo do servidor do upstream.
- [x] E. Pesquisar na memória e o grafo de conhecimento (o geral e o do projeto).
  Feito: a rota `extra/search` no engine (`core/features/memory/server/src/page/panel/search.rs` e
  `core/features/memory/server/src/page/panel/search_trace.rs`: os filtros, o rastro e as recentes da tela do upstream), igual à tela dele em dez
  buscas do seed (`core/features/memory/server/tests/panel/screen_search.rs`) e na leitura intacta;
  no app, Pesquisar (`apps/macos/features/memory/panel/PanelSearchView.swift`, o destaque único em
  título e trecho, o rastro numa dobra) e o "por que foi recuperada" da página, que recalcula a busca
  que a abriu (`apps/macos/features/memory/panel/PanelWhyRow.swift`); o grafo com layout de forças determinístico
  (`apps/macos/features/memory/panel/PanelForceLayout.swift`), desenhado em Core Graphics (`apps/macos/features/memory/panel/PanelGraphCanvas.swift`), com teclado,
  balão, pinça e memory.graph-fit. Diferenças do board: o grafo segue a decisão do dono (forças, não
  o círculo); a dica do nó geral diz "default/cadex"; a busca não manda formulário: cada seletor já
  pesquisa; o seed tem 4 projetos, então "4 resultados" e não 34. Os tokens novos em
  components.memoryPanel.graph (cores por tipo, aresta, legenda, coluna).
- [x] F. A caixa de entrada e os workstreams.
  Feito: no engine, enviar e editar uma mensagem na fila (`core/features/memory/server/src/page/panel/messages.rs`,
  as rotas POST do upstream com as mesmas regras, limites e recusas; `cadex memory-agent panel-post`),
  iguais ao upstream passo a passo, cada lado no seu seed (`core/features/memory/server/tests/panel_messages.rs`:
  enviar, as recusas, segurar, salvar, descartar, e a caixa no fim). No app, a Caixa de entrada
  (`apps/macos/features/memory/panel/PanelInboxView.swift`: a fila, o projeto, Recebidas e
  Enviadas, o estado, as mensagens que abrem, com Editar e o editor no lugar; Nova mensagem em
  `apps/macos/features/memory/panel/PanelComposeBox.swift`) e os Workstreams
  (`apps/macos/features/memory/panel/PanelWorkstreamsView.swift`). Cada escrita é um comando:
  memory.send-message, memory.edit-message, memory.save-message e memory.discard-message-edit;
  "Enviar mensagem a um agente" abre a caixa do projeto com o foco na Nova mensagem. Diferenças do
  board: a fila sob o título leva um link por projeto ("cadex · 2"); os selos dos estados nas
  palavras do upstream (pendente, coletada); o botão de enviar apagado até haver agente e texto.
  O que mudou nas telas de antes: o selo com bolinha saía espremido ("● semantic" da página), e no
  grafo o nó sem links virou um anel vazado (apagado, confundia com o cinza de "fact").
- [ ] G. A revisão de aprendizado, a saúde do servidor e a documentação.

Cada fase de tela: o print do Cadex ao lado do print do upstream sobre o mesmo seed, e o que difere
escrito com o motivo; o print aprovado fica como referência e o teste do app avisa quando a tela
muda.

- Telas: MemorySidebar.dc.html, MemoryOverview.dc.html, MemoryProject.dc.html, MemoryPage.dc.html,
  MemoryHistory.dc.html, MemorySession.dc.html, MemoryAgent.dc.html, MemorySearch.dc.html,
  MemoryGraph.dc.html, MemoryInbox.dc.html, MemoryWorkstreams.dc.html, MemoryReview.dc.html,
  MemoryHealth.dc.html, MemoryDocs.dc.html (descritas em `docs/design/work-frame/screens-memory.md`, com
  cada corte de texto em relação ao upstream; os prints do upstream em
  `docs/research/memory-panel-screens.md`).
- Tokens: components.memoryPanel (valores exatos em `docs/design/work-frame/tokens.json`).

## Como validar
- `make check` ao fim de cada fase; testes do engine para cada rota nova, cada um com a paridade
  contra o painel do upstream sobre o seed, e a memória intacta depois.
- Os prints lado a lado de cada tela (instância de teste com os dados de teste, nunca os do dono).
- Sem o `make perf`, a menos que o dono peça.
