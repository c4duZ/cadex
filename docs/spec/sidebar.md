# sidebar

## Para que serve
A coluna à esquerda da janela: uma fileira de ícones no topo escolhe a página (arquivos, busca, git,
agentes...) e, logo abaixo, as sub-abas da página escolhida. Quem usa decide quais ícones aparecem e
em que ordem.

## Comportamento
- No topo, ao lado dos botões da janela, a fileira de ícones (Phosphor), agrupada numa moldura
  arredondada de fundo leve, como o grupo de botões da barra de título; personalizar fica à parte. Clicar num ícone mostra a
  página dele; clicar no ícone da página aberta recolhe a barra lateral (como view.toggle-sidebar).
- Os ícones padrão, nesta ordem: Files (⇧⌘E, explorer.focus), Git (⇧⌘G, git.show), Agents (⇧⌘J,
  agents.show) e Accounts (⇧⌘U, agents.show-accounts, de uso); Agents e Accounts separados para cada
  um ter o próprio ícone e atalho (o dono, 2026-10-21). Git History (⇧⌘L, git.show-history, de log)
  existe escondido e pode ser ligado. Atalhos de ⇧⌘ com a inicial, para lembrar (2026-10-22).
- ⌃⌘1 a ⌃⌘9 (sidebar.page-1 a -9) mostram a página do ícone daquela posição, na ordem que
  aparece, sem nunca recolher a barra lateral (só o clique no ícone aberto recolhe), como ⌘1 a ⌘9 nas abas; ⇧⌘ não, porque ⇧⌘3 a ⇧⌘5 são as capturas de tela do macOS.
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
- Embaixo da fileira, o título da página à esquerda e as sub-abas dela à direita, num controle
  segmentado (nenhuma página usa hoje: Sessions e Accounts viraram páginas). Página sem sub-aba mostra
  só o título (Files mostra o nome da pasta do workspace).
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
- [ ] Clicar em cada ícone mostra a página dele; clicar no da página aberta recolhe a barra.
- [ ] Esconder o Git no painel tira o ícone na hora em todas as janelas; reabrir o app mantém.
- [ ] Arrastar o Agents para o primeiro lugar muda a ordem, e o settings.json guarda a ordem nova.
- [ ] Cada ação do painel também está no ⌘K.
- [ ] As sub-abas trocam a vista sem trocar a página, e a escolhida volta ao reabrir.
