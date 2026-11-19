# sidebar

## Para que serve
O trilho: a faixa estreita na borda esquerda da janela, sempre à vista, com os projetos e o que é
de todos eles, para trocar de projeto e saber o que precisa de você sem abrir página nenhuma
(`../adr/0038-rail-and-side-column.md`; a peça Rail de `../design/work-frame/screens.md`; os
estudos aprovados em `../design/sidebar/`). Os terminais ficam só nas abas de cima (`tabs.md`); o
que se sabe do projeto fica na coluna lateral, ao lado do trilho (`inspector.md`). A árvore do
trabalho que ocupava este lugar (ADR 0035) saiu com a ADR 0038.

## Comportamento
- **Largura:** 56 pt, fixa. O trilho nunca fecha: ⌘B fecha e abre só a coluna lateral.
- **Projetos, no topo:** um quadrado por projeto (`projects.md`) com a imagem dele, senão o emoji,
  senão a primeira letra do nome, sobre a cor do projeto. O nome na dica. O escolhido tem um halo em
  volta, do mesmo tamanho dos outros. A peça de estado no canto (o estado mais urgente dos terminais
  do projeto: precisa de você, trabalhando, pronto, falhou; parado não tem peça) e um ponto embaixo
  quando há terminal aberto, como o Dock.
- **Ordem:** os fixados primeiro, na ordem do dono; depois de uma linha, os abertos não fixados.
  Arrastar um quadrado muda a ordem ao vivo (os outros abrem caminho); soltar acima da linha fixa,
  abaixo solta. Um projeto sem terminal não desce da linha (solto e vazio, nada o manteria). A ordem
  fica no arquivo dos projetos.
- **Clique num quadrado:** mostra as abas do projeto e a coluna nele; sem terminal, abre um na pasta
  dele; uma página aberta no centro (Projects, Automations) dá lugar aos terminais.
- **Clique direito num quadrado:** New Terminal, New Task…, Edit Name and Image…, Pin ou Unpin,
  Project Settings…, Show in Finder, Copy Path, Close Terminals e Remove from the Sidebar (fecha e
  solta; nada do disco sai). Cada um é um comando que age naquele projeto.
- **Soltar uma imagem num quadrado** a faz a imagem do projeto (cortada quadrada, pequena, copiada
  para a pasta das imagens dos projetos).
- **"+"** depois dos projetos abre a folha de projeto novo (project.create): a pasta, o nome, a
  imagem ou o emoji e a cor; o projeto criado nasce fixado.
- **As páginas da coluna**, depois de outra linha: os ícones de Files, Changes, Sessions, Memory e
  Git graph (a ordem do dono: arrastar reordena, salva em inspector.order). O clique abre a coluna
  naquela página; no ícone aceso (a página que a coluna mostra), fecha a coluna, como a barra de
  atividades do VS Code.
- **Pé:** Projects (a página Projetos, project.show-all), Automations (a página Automações,
  orchestration.show-automations) e Remote (os hosts do `~/.ssh/config` e as máquinas da tailnet numa
  lista, remote.show; escolher conecta numa aba), este só quando há algum host. O da página aberta
  fica aceso.
- **Terminais sem projeto:** os da pasta pessoal não viram quadrado; enquanto se está neles nenhum
  quadrado fica aceso (`tabs.md`, abas sem projeto).
- O trilho não lê nada a cada tecla: muda com os avisos que já existem (estado dos agentes pelos
  hooks, abas abertas ou fechadas, projetos editados).
- Toda ação do trilho é comando e está no ⌘K (ADR 0005): trocar de projeto (⇧⌘S), cada página,
  fixar, editar, criar, a página Projetos, o Remote.
- A árvore que saiu da tela ainda junta o que o sidebar.find e o ⌘J listam (os projetos, as
  tarefas e os terminais).

## Estados
- **Nenhum projeto:** o trilho mostra só o "+", os ícones das páginas e o pé; o centro mostra a tela
  de início (`home.md`).
- **Projeto fixado sem terminal:** o quadrado fica, sem o ponto; o clique abre um terminal.
- **Sem host SSH nem máquina da tailnet:** o pé sem Remote.

## Casos de borda
- Muitos projetos: o trilho ainda não rola; os que não cabem passam por baixo dos ícones das
  páginas (falta resolver; ⇧⌘S acha qualquer um).
- Nome sem letra nem número: o quadrado mostra "•".
- Imagem que some do disco: o quadrado volta ao emoji ou à letra.

## Critérios de aceite
- [x] Um quadrado por projeto, o escolhido com o halo, a peça de estado só fora de parado, o ponto
  com terminal aberto, o clique escolhe (teste da feature).
- [x] Arrastar um aberto para cima da linha o fixa e fica na ordem ao reabrir (conferido no app).
- [x] Os ícones das páginas abrem a coluna na página; o aceso a fecha; arrastar reordena e salva.
- [x] O pé com Projects e Automations, acesos com a página deles; Remote só com algum host.
- [ ] O clique direito e a imagem solta conferidos com o mouse de verdade.
