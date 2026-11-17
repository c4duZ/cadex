# home (app macOS)

## O que eu quero
- A tela de início (`../../../../docs/spec/home.md`; mockup Home, components.home): a saudação, a
  caixa do pedido com o agente e o lugar, os quatro cartões e os projetos recentes, no centro da
  janela quando nenhum projeto está aberto e pelo home.show.

## O que eu não quero
- Abrir agente, ler projeto ou rodar comando daqui: a tela diz o que o dono pediu (`HomeActions`) e
  o app faz (`../../app/HomeWiring.swift`).
- Valor de desenho digitado: só DesignTokens.Home (`../../../../tools/check_design_literals.py`).
- Ficar na memória sem estar na tela: o app a monta ao mostrar e a solta ao sair.

## Como eu quero
- `HomeModel.swift`: o que a tela mostra, puro e testado: `HomeState` (o projeto, o agente, o lugar,
  os recentes), `HomeRecent` (o estado em cor: precisa de você, terminou, aberto, fechado, pasta
  sumida) e `HomeWords` (a saudação pela hora, o "quando", o estado de um projeto aberto, o ~, a pasta que o
  `git clone` cria).
- `HomeView.swift`: a coluna de 760 pt (a saudação, a caixa do pedido com o nome do projeto como
  botão, "@" abrindo o mesmo menu e o Enter mandando o pedido; os chips do agente e do lugar; o que
  o Enter faz), `HomeCard` (os quatro cartões e os comandos que o app liga) e `HomeCardGrid` (4, 2 ou
  1 coluna pela largura, a altura como tamanho intrínseco). Os atalhos dos cartões são lidos a cada
  `show`: a tela pode nascer antes do mapa de teclas.
- `HomeParts.swift`: as peças (a caixa com o anel de 3 pt de fora, o chip, o cartão que mede a
  altura na largura dele, a linha de recente posta à mão: o nome e o "quando" fixos, o estado do
  tamanho das palavras, o caminho com o resto; Remove na pasta sumida).

## Como validar
- `make macos-test` (HomeTests): a saudação, o estado e o "quando", e a tela (o projeto na caixa, o
  Enter, o "@", o Remove); com CADEX_SNAPSHOT_DIR, salva home.png.
