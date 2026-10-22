# sidebar

## Para que serve
A coluna à esquerda da janela: uma fileira de ícones no topo escolhe a página (arquivos, busca, git,
agentes...) e, logo abaixo, as sub-abas da página escolhida. Quem usa decide quais ícones aparecem e
em que ordem.

## Comportamento
- No topo, ao lado dos botões da janela, a fileira de ícones (Phosphor), sem moldura (uma moldura
  arredondada foi testada e saiu, o dono, 2026-10-22), com personalizar no fim. Clicar num ícone mostra a
  página dele, o da página aberta também: o clique nunca recolhe a barra lateral (o dono, 2026-10-22;
  ⌘B recolhe). Os ícones e o de personalizar formam um bloco centrado, 2 pt entre eles.
- Os ícones padrão, nesta ordem: Files (⇧⌘E, explorer.focus), Git (⇧⌘G, git.show), Agents (⇧⌘J,
  agents.show) e Accounts (⇧⌘U, agents.show-accounts, de uso); Agents e Accounts separados para cada
  um ter o próprio ícone e atalho (o dono, 2026-10-21). Git History (⇧⌘L, git.show-history, de log)
  existe escondido e pode ser ligado. Atalhos de ⇧⌘ com a inicial, para lembrar (2026-10-22).
- ⌃⌘1 a ⌃⌘9 (sidebar.page-1 a -9) mostram a página do ícone daquela posição, na ordem que
  aparece, sem recolher a barra lateral, como ⌘1 a ⌘9 nas abas; ⇧⌘ não, porque ⇧⌘3 a ⇧⌘5 são as capturas de tela do macOS.
- Só entra na barra o que mostra uma página nela. Search saiu: é o ⌘P e o ⇧⌘F, não uma página (o dono,
  2026-10-22); Web Preview e Spaces abriam coisa em outro lugar e saíram (2026-10-21). Numa lista
  salva, esses ids somem sem aviso (SidebarLayout.retired).
- Git History na barra lateral: cada commit em duas linhas, o grafo e a descrição (com as
  etiquetas de branch e tag) sobre o autor, há quanto tempo e o hash curto. Clicar num commit abre
  os arquivos dele logo abaixo, com o grafo continuando por trás; clicar de novo fecha; clicar
  num arquivo abre o diff no painel principal. Parar o mouse num commit mostra, em 0,2 s, a
  descrição inteira, as branches e tags, o autor com e-mail, a data completa e o hash inteiro; num
  arquivo, o caminho completo. Sem painel de detalhes na barra: o clique direito
  (e o ⌘K) tem "Show Commit Details in a Tab", que abre a aba do histórico com o commit escolhido,
  "Copy SHA" e "Open on Remote".
  Fora de um repositório, "Not a Git repository". A aba do histórico (git.history) continua igual.
- Página que ninguém abriu não existe: o histórico só é lido na primeira vez que a página aparece.
- Cada ícone pode ter um sinal pequeno: o Git, o número de mudanças; o Agents, um ponto quando algum
  agente espera resposta. O sinal some quando não há nada a dizer.
- Cabeçalho da página: uma linha só, igual em todas, 6 pt abaixo dos ícones e com 28 pt de altura;
  o conteúdo começa logo embaixo. Nenhuma página tem cabeçalho próprio: um título sobre o cabeçalho
  do explorer repetia o nome da pasta com um vão grande, e tirar o título só em Files deixava as
  páginas diferentes (o dono, 2026-10-22).
  - À esquerda, o nome, em 12 pt seminegrito na cor discreta, como escrito (sem maiúsculas): Files
    mostra o nome da pasta (o caminho na dica); Git, a branch com o ícone de branch e ↑ ↓, e o clique
    troca de branch (git.switch-branch), ou "Git" fora de um repositório; as outras, o nome da página.
  - À direita, os botões da página, do mesmo tamanho e com o mesmo espaço, até 3; o resto vai para
    o "⋯". Sempre à vista, discretos, acesos sob o ponteiro. Cada um roda um comando.
  - Files: novo arquivo, nova pasta, recolher tudo; no "⋯", buscar arquivo e recarregar.
  - Git: fetch, pull, push, e um indicador girando enquanto uma ação roda; no "⋯", trocar de branch,
    tudo para o stage, tudo fora do stage e atualizar.
  - Git History: abrir o histórico numa aba. Accounts: atualizar o uso e personalizar as contas.
    Agents: só o nome.
  - Sub-abas, se uma página tiver (nenhuma tem hoje: Sessions e Accounts viraram páginas), ficam
    antes dos botões.
- Personalizar: o último ícone da fileira (controles deslizantes) abre a janela "Customize", uma só
  para o app e com uma aba por coisa a arrumar (Sidebar, Status Bar), como a de configurações e por
  cima do app em tela cheia; na aba Sidebar, a lista dos ícones (arrastar para reordenar, chave para mostrar ou esconder). O mesmo vale arrastando
  o próprio ícone na fileira, e pelo ⌘K: "Customize Sidebar" e "Show or Hide a Sidebar Page" (a
  lista das páginas, cada uma marcada como aparece ou escondida).
- A escolha vale para todas as janelas na hora e fica no settings.json (sidebar.items, a lista em
  ordem; o que não está nela fica escondido).
- A página aberta e a sub-aba de cada página voltam ao reabrir o app (com os spaces).

## Estados
- **Todos os ícones escondidos**: a fileira mostra só o ícone de personalizar; a barra lateral
  mostra "No pages. Customize to add one." com o botão.
- **Página desligada pelas configurações** (por exemplo, Agents com as leituras desligadas): o ícone
  continua se estiver na lista, e a página explica o que está desligado e como ligar.

## Casos de borda
- Barra lateral estreita (abaixo de 200 pt): os ícones que não cabem vão para um menu "…" no fim da
  fileira, na mesma ordem.
- Atalho de uma página escondida: mostra a barra lateral com a página, sem pôr o ícone na fileira.
- settings.json com id de página desconhecido: o id é ignorado e vira aviso; o resto vale.

## Critérios de aceite
- [ ] Clicar em cada ícone mostra a página dele; clicar no da página aberta não recolhe a barra.
- [ ] Esconder o Git no painel tira o ícone na hora em todas as janelas; reabrir o app mantém.
- [ ] Arrastar o Agents para o primeiro lugar muda a ordem, e o settings.json guarda a ordem nova.
- [ ] Cada ação do painel também está no ⌘K.
- [ ] As sub-abas trocam a vista sem trocar a página, e a escolhida volta ao reabrir.
