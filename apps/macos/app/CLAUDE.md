# app — entrada do app macOS

## O que eu quero
- Só o ponto de entrada: criar o NSApplication, as janelas e ligar as features.

## O que eu não quero
- Lógica de feature aqui. Cada coisa que a janela mostra vem de uma feature, pela porta de
  entrada dela (os tipos `public` do módulo).

## Como eu quero
- `main.swift` registra os comandos de cada feature (e o view.toggle-sidebar da casca), monta menu e
  atalhos a partir deles, e abre a janela. Como delegate, pergunta às abas antes de fechar a janela
  ou sair (shouldCloseAll). Liga a barra de status ao terminal com foco.
- A casca da janela, no estilo do Terax: título transparente com barra de ferramentas compacta
  (38 pt, botões da janela centrados); `TitleBarView.swift` (painel lateral, paleta, abas, "+",
  busca, todos por comando), `WorkspaceView.swift` (painéis arredondados de `PanelView.swift`,
  painel lateral recolhível, barra de status) e `SidebarView.swift` (vazio até os planos 4 e 6).
  As cores vêm do tema; a cor da moldura vai na janela, não numa camada da view, porque uma
  camada pintada cobria os botões da janela.
- `WindowBackdrop.swift`: imagem de fundo atrás da área do terminal (desfoque calculado uma vez) e,
  com vibrância, a moldura fosca; depois de ligar, os botões da janela voltam para cima da camada.
- Abrir para teste com CADEX_BACKGROUND=1: a janela aparece sem tomar o foco do teclado. Abas, spaces e a paleta
  entram aqui conforme as features existirem.

## Como validar
- `make app` compila; `make run` abre a janela com um shell.
