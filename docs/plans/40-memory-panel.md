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
- Adaptado ao Cadex só no que ajuda: um projeto ou uma sessão levam também ao projeto e ao
  terminal no Cadex; o idioma é o do Cadex.

## O que eu não quero
- WebView (ADR 0001): as telas são nativas.
- Mudar o que existe: a seção Memória da página do projeto, o item Memory da barra de baixo e o
  inspector continuam como estão.
- Editar os crates do upstream (ADR 0028): o engine os usa e expõe os dados.
- O que é de servidor com vários usuários: login, Sair, troca de senha, a escolha de idioma.
- Ler os dados reais da memória do dono para outra coisa que não a referência da fase A, e nunca
  o original: uma cópia, apagada no fim.

## Como eu quero
- [ ] A. Referência e mockups. O painel do upstream rodando sobre uma cópia do banco do dono, por
  um programa de exemplo do engine (só nos testes: o ai-memory-web como dependência de
  desenvolvimento, nunca no binário), e um print de cada tela; o inventário de cada uma (o que
  mostra, de onde vem o dado: a API JSON do upstream ou só o HTML); os mockups com os tokens do
  Cadex num .dc.html, revisados por um agente de UX contra os prints e os estudos da barra lateral;
  o dono aprova antes do código.
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

Cada fase de tela: o print do Cadex ao lado do print do upstream da fase A, e o que difere
escrito com o motivo.

## Como validar
- `make check` ao fim de cada fase; testes do engine para cada rota nova.
- Os prints lado a lado de cada tela (instância de teste com os dados de teste, nunca os do dono).
- Sem o `make perf`, a menos que o dono peça.
