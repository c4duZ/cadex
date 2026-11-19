# 0039 — Uma barra lateral com Trabalho e Arquivos, a fila "Precisa de você" e o lugar em cima

Data: 2026-11-19 · Status: aceita (o dono, 2026-11-19: "a estrutura ideal dele para mim tá ótima",
e depois da revisão visual, "pode fazer") · Substitui a `docs/adr/0038-rail-and-side-column.md`
(o trilho e a coluna lateral) e, da `docs/adr/0035-work-frame.md`, a barra de cima; o resto da 0035
vale · Referência para construir: `docs/design/sidebar/6-estrutura-ideal.html`

## Contexto
Depois da 0038, uma auditoria de UX passou pelo app inteiro e outra pela estrutura da janela, as
duas julgando só por princípios (o dono pediu que a opinião dele e as decisões de antes não
contassem): `docs/design/sidebar/4-auditoria-estrutura.html`. Os achados de estrutura:
- a janela não dizia "você está aqui" onde se olha primeiro: o projeto era uma letra no trilho e um
  texto apagado embaixo, e dentro de uma tarefa a única pista era "‹ projeto";
- "precisa de você" aparecia em oito lugares, com três linguagens, e sumia junto com o que o
  continha (a aba no "» N", o projeto rolado para fora do trilho);
- o trilho misturava três tipos de coisa com a mesma cara (lugares, painéis e páginas globais), e os
  ícones das páginas mudavam de altura a cada projeto;
- a coluna não dizia o que era nem de quem era, e três das cinco páginas repetiam a página do projeto.

O dono pediu outras estruturas, sem apego a nada, com uma regra só: nada de painel à direita. O
estudo `docs/design/sidebar/5-estruturas-alternativas.html` desenhou seis (árvore, duas fileiras em
cima, comando primeiro, caixa de entrada, espaços, mosaico) e a que o pesquisador construiria. O
dono ficou com esta, com três ajustes: a barra de baixo fica ("é parte do coração do Cadex"),
Trabalho é a primeira vista e Arquivos a segunda ("eu dou muita importância para arquivos"), e
Mudanças existe mas discreta ("ninguém vai usar… pode até ter").

## Decisão
- **Cada região, um trabalho:** em cima, onde estou e o que está aberto aqui; à esquerda, para onde
  vou e quem precisa de mim; no centro, os terminais e documentos; embaixo, o ambiente.
- **A barra de cima**, da esquerda para a direita:
  - o botão da barra lateral (⌘B), na borda de entrada, como no Finder e no Xcode;
  - **o lugar**: a imagem e "projeto › tarefa ▾". O clique abre o menu do lugar: trocar de projeto ou
    de tarefa (com busca), voltar ao main e abrir a página do projeto;
  - as abas do lugar (terminais com a peça de estado, arquivos com o ícone de arquivo), o "» N" com a
    peça mais urgente das que esconde, e o "+";
  - **Revisar**, só dentro de uma tarefa: um botão com contorno depois de um fio, não uma aba;
  - **Buscar ⌘K** no fim.
  - Saem da barra de cima: a conta, o quadro, o sino e a engrenagem (⌘, e o menu bastam). A conta e o
    café ficam só na barra de baixo; o quadro vai para o pé da barra lateral; o sino vira a fila.
- **A barra lateral** (248 pt):
  - **a fila "Precisa de você"**: um cartão âmbar preso no topo, em qualquer vista e largura, que só
    aparece com pedido; cada linha diz o agente, o projeto, o que ele pede em frase ("quer rodar
    `npm install stripe`") e há quanto tempo; o clique leva ao terminal, onde está o diálogo do
    próprio Claude;
  - **o seletor "Trabalho | Arquivos"**, na largura toda, com palavras (⇧⌘1 e ⇧⌘2); Trabalho é o
    padrão;
  - **Trabalho**: os projetos, cada um com o avatar, o nome, o estado e quantos terminais; aberto,
    o main e as tarefas presos por um fio guia; o clique no nome vai ao último lugar usado, num item
    põe as abas dele em cima; o aceso é onde você está; projeto fechado com pedido leva a etiqueta
    âmbar com o número (o único âmbar da lista); uma marca na borda da lista rolada diz quem espera
    fora da vista; "Novo projeto…" no fim;
  - **Arquivos**: a árvore do lugar, com o cabeçalho em palavras ("tarefa de cadex · contra main"),
    o M e o A alinhados à direita e, no fim, "N mudanças · ver", que mostra **Mudanças** na própria
    barra (Commit, Abrir PR); Esc volta;
  - **o pé**, fixo e separado: Quadro, Automações e Máquinas (esta só com algum host).
- **A barra de baixo fica**, com os itens de hoje, cada um com o seu cartão e montada pelo dono: o
  projeto · branch (o clique abre Mudanças), os agentes trabalhando (o clique abre o quadro), a
  gaveta, a Memory, o uso da conta (o clique troca de conta), o café e o ambiente. Ela não conta
  pedidos: a casa deles é a fila.
- **Sessões, Memória e o grafo do git** saem da barra lateral: moram na página do projeto, que abre
  pelo menu do lugar e pelo ⌘K, e o grafo também abre como página.
- **A atenção sobe para o que está à vista:** com a barra lateral fechada, uma pílula na barra de
  cima diz quem espera ("checkout-copy precisa de você"); com o app atrás de outros, a notificação do
  sistema e o número no Dock, que contam só pedidos.
- **Janela estreita** (abaixo de 1000 pt): a barra lateral vira uma faixa de 56 pt com a caixa âmbar
  dos pedidos, os quadrados dos projetos (as tarefas ficam no menu do lugar) e, no pé, Arquivos (que
  abre por cima do centro) e Quadro; a barra de baixo encurta, cada item com a palavra, o resto no
  "…". Alargar devolve a barra inteira na vista em que estava.
- **Nada aberto:** a barra lateral mostra os recentes (com a cara dos projetos), Novo projeto… e
  Abrir pasta… ⌘O, sem o seletor de vistas; o centro é a tela de início; a barra de baixo só com o que
  vale sem projeto (gaveta, conta, café, ambiente).

## Alternativas recusadas
- **Manter o trilho e a coluna (0038), só arrumando** (o estudo 4): resolvia os sintomas, mas
  continuava com ícones sem nome e três tipos de coisa numa faixa.
- **Árvore com os terminais, sem abas:** a melhor em "onde estou", mas três níveis numa barra
  lateral, e com dezenas de terminais quem espera rola para fora da vista.
- **Duas fileiras de abas em cima, sem barra lateral:** a maior largura para o terminal, mas quebra
  com mais de uns seis projetos e não tem onde pôr os arquivos.
- **Caixa de entrada ou mosaico de agentes como casa:** ótimos para não perder pedido, ruins para o
  terminal comum; o mosaico fica como o quadro, uma vista que se abre.
- **Tirar a barra de baixo** (a proposta do pesquisador): o dono a quer; ela fica com o que é
  ambiente e sem a contagem de pedidos.

## Consequências
- O trilho (`apps/macos/features/sidebar/`) dá lugar à barra lateral; a coluna lateral (a feature
  `inspector`) deixa de existir como coluna: Files e Changes viram vistas da barra, Sessions, Memory
  e Git graph ficam na página do projeto.
- A tarefa deixa de ser item da barra de abas (plano 36 D): as tarefas estão na barra lateral e no
  menu do lugar, e o "‹ projeto" sai.
- O sino sai da barra de cima; o feed dele (o histórico dos avisos) continua no ⌘K.
- Os quadrados grandes com imagem viram avatares na lista; voltam como quadrados na janela estreita.
- A 0038 fica como histórico, com a nota "substituída pela 0039"; o plano 38 constrói esta.
