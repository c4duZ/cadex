# 0038 — A esquerda em trilho e coluna lateral; a coluna da direita sai

Data: 2026-11-18 · Status: aceita (o dono, 2026-11-18: "pode deixar o open terminal, escreve a
ADR") · Revê, da `docs/adr/0035-work-frame.md`, a "Esquerda, a árvore do trabalho" e a "Direita, a
seleção"; o resto dela vale · Mockups em `docs/design/sidebar/` (1 a 3)

## Contexto
O dono não gosta da coluna da direita (o inspector, ⌥⌘I): ela tira largura dos terminais e esconde
Changes, Files, History e Memory atrás de um atalho. Ele quer a barra lateral só à esquerda e os
terminais com o resto da janela (2026-11-18). O estudo comparou VS Code, Cursor 3, Orca, Conductor,
Terax, Xcode e JetBrains e pesou pelo uso: quem usa o Cadex conduz agentes, não escreve código o dia
todo, e a maior parte das features é passiva (memória, automações, máquinas, preview). Os princípios
que decidiram: proximidade (o controle fica perto do que controla), um lugar para cada coisa,
reconhecer em vez de lembrar, o estado sempre à vista, lugar fixo para o que não muda, e o global
separado do que é do projeto. O próprio dono não reconheceu o ícone do History, o que tirou ícone
sem nome de onde ele não tem apoio.

## Decisão
- **A esquerda vira duas partes:** o **trilho** (56 pt) e, ao lado, a **coluna lateral** (260 pt,
  arrastável, a largura salva). Juntos ocupam 316 pt, o mesmo que a árvore de hoje sozinha. A
  coluna da direita (inspector) sai.
- **O trilho é global e só tem projetos.** Cada projeto é um quadrado com a imagem e o nome que o
  dono deu (não o nome da pasta), a peça de estado no canto (o mais urgente dos terminais dele) e um
  ponto embaixo quando há terminal aberto. Os fixados ficam sempre, na ordem arrastada; o "+" cria
  um projeto (nome, imagem, pasta). No pé do trilho, o que vale para todos e se usa de vez em
  quando: **Projects**, **Automations** e, só havendo algum host, **Remote** (ver abaixo).
- **Clicar num projeto do trilho** põe os terminais dele nas abas de cima e a coluna lateral nele.
  Um projeto fixado sem terminal abre um terminal novo na pasta dele.
- **A coluna lateral é do projeto escolhido** e mostra uma página por vez. No topo, só os ícones
  das páginas, nesta ordem: **Files, Changes, Sessions, Memory e Git graph** (o nome sob o ponteiro;
  o número de arquivos no Changes e um ponto no Memory quando aprendeu algo). Nada de título,
  projeto, branch ou caminho no topo: o projeto está aceso no trilho e a branch, na barra de status.
  O que cada página precisa de ação desce para um pé (como o briefing do Memory): a checagem, Commit,
  Open PR e a branch com ↑↓ no Changes; a pasta e criar e buscar no Files.
- **Os terminais ficam só nas abas de cima**, sem lista na coluna lateral. Uma tarefa (worktree) é
  uma aba com o ícone de branch e a seta: clicar troca a barra para os terminais dela, e "‹ projeto"
  volta. Quando as abas não cabem, "» N" no fim abre a lista de todos; o ⌘J acha qualquer terminal.
- **Files e Changes seguem o projeto escolhido, não o `cd` do terminal**, para a coluna lateral e as
  abas falarem sempre do mesmo lugar.
- **A página Projects** (o ícone no pé do trilho) mostra um cartão por projeto, e o cartão abre a
  **página do projeto** (Overview, Sessions, Memory, Automations, Settings, com Open terminal e New
  task). A página Projects não edita projetos: nome, imagem e fixar ficam nas Settings do projeto e
  no clique direito do trilho.
- **Com tudo fechado**, fica a tela de início (ver "Decidido depois").
- **Clique direito num projeto:** New terminal, New task, Edit name and image, Pin ou Unpin,
  Project settings, Show in Finder, Copy path, Close terminals e Remove from the sidebar (não apaga
  nada do disco). Os projetos e os ícones das páginas se arrastam para mudar a ordem.
- **A coluna lateral fecha** com o quadro aberto (o clique no ícone do quadro de novo o fecha e a
  devolve), com ⌘B, numa janela estreita (abaixo de 1000 pt) e sem projeto aberto; o trilho fica.
  Abrir uma página no centro (Projects, a página do projeto) não fecha a coluna, para nada pular.
- Toda ação nova é comando (ADR 0005): trocar de projeto, cada página da coluna, fixar, editar,
  a página Projects.

## Alternativas recusadas
- **A árvore de hoje com as abas da direita descidas para baixo dela:** muda o lugar, não a
  estrutura; o dono quer o trilho.
- **Todas as abas de todos os projetos em cima, agrupadas por projeto:** não aguenta um projeto
  com dez terminais nem as tarefas.
- **A lista de terminais na coluna lateral:** repete as abas de cima e gasta altura; o que ela tinha
  de único (o pedido de outro projeto) já está na peça de estado do trilho.
- **Os ícones das páginas no pé do trilho:** ficam longe da coluna que trocam.
- **Abas escritas no topo da coluna:** cinco nomes não cabem em 260 pt; os ícones com o nome sob o
  ponteiro e o pé de cada página bastam.
- **Um quadrado "~" para os terminais sem projeto e a página Projects para editar projetos:** o
  dono não reconheceu o primeiro e não quer o segundo.

## Decidido depois (o dono, 2026-11-18)
- Com tudo fechado fica a tela de início de hoje (`docs/spec/home.md`). A página Projects é outra
  coisa e só abre pelo botão no pé do trilho.
- O terminal aberto sem projeto fica em abas sem projeto, que a barra mostra quando nenhum projeto
  está aceso no trilho.
- ⌘1 a ⌘9 continuam nas abas, contando as que a barra mostra naquela hora.

O pé do trilho tem Projects, Automations e **Remote** (as máquinas da tailnet e os hosts do
`~/.ssh/config`, se respondem, conectar numa aba), este só quando há algum host. O item SSH da
barra de status, que mostrava isso, vem desligado por padrão e quase ninguém o via. O quadro, o
sino e as configurações ficam na barra de cima.

## Levantado junto (fora da sidebar, cada um no seu plano)
- **Controlar o Claude pelo celular** (o dono, 2026-11-18): o telefone na tailnet entra no Mac por
  SSH e se liga à mesma sessão que o Cadex mostra (o daemon do terminal já é dono dos shells,
  `docs/adr/0022-terminal-daemon.md`), em vez de abrir outra. Estudar antes: o `cadex attach`, o que
  aparece no telefone e o pedido de permissão respondido de lá.
- **Contas na barra de cima:** trocar de conta ainda é difícil; gerenciar (criar, compartilhar,
  remover) sai da janela Customize e vai para o menu da conta na barra de cima.
- **Servidores rodando:** o item Ports da barra de status aparece sozinho quando um terminal abre
  uma porta, e o clique abre o preview.
- **Computer-use:** um aviso na barra de status enquanto o agente usa outro app, com o clique para
  parar.
- **Todas as sessões:** um link na página Projects (hoje só o ⌘J e o ⌘K).
- O item Memory da barra de status passa a abrir a página Memory da coluna lateral.

## Consequências
- A ADR 0035 ganha a nota "esquerda e direita revistas pela 0038".
- A feature `inspector` sai; as quatro abas dela viram páginas da coluna lateral da `sidebar`. A
  árvore da `sidebar` dá lugar ao trilho. As specs `sidebar`, `inspector`, `tabs` (a aba de tarefa,
  o "» N"), `projects` (nome, imagem, fixar, ordem) e `home` mudam no plano que fizer isto.
- O app do Windows segue depois; os comandos novos entram no `MAC_ONLY` da paridade até lá.
- O `make perf` confere que a coluna fechada não lê nada, como o inspector fechado não lia.
