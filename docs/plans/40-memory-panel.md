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
- [ ] B. O engine: a API JSON do upstream (`/api/v1`: projetos, visão geral, páginas, histórico,
  recentes, briefing, handoffs, sessões, observações, busca, grafo) no socket da memória, e rotas
  nossas para o que só existe no HTML (caixa de entrada, workstreams, revisão de aprendizado, saúde,
  agentes e uso de tokens), pelas funções do upstream.
- [ ] C. A página Memória no pé da barra lateral, com as seções, e a Visão geral: os cinco
  números, a saúde da captura, o aviso da caixa de entrada e os cartões dos projetos com filtro.
- [ ] D. O projeto: a árvore de páginas e a atividade recente, a página (Markdown e metadados), o
  histórico com diff, a sessão (linha do tempo) e o agente (sessões e uso).
- [ ] E. Pesquisar na memória e o grafo de conhecimento (o geral e o do projeto).
- [ ] F. A caixa de entrada e os workstreams.
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
