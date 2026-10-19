# app — entrada do app macOS

## O que eu quero
- Só o ponto de entrada: criar o NSApplication, as janelas e ligar as features.

## O que eu não quero
- Lógica de feature aqui. Cada coisa que a janela mostra vem de uma feature, pela porta de
  entrada dela (os tipos `public` do módulo).

## Como eu quero
- `main.swift` registra os comandos de cada feature (e o view.toggle-sidebar da casca), monta menu e
  atalhos a partir deles, e abre a janela. Como delegate, pergunta às abas antes de fechar a janela
  ou sair (shouldCloseAll). Liga a barra de status ao terminal com foco. Cria o `WorkspaceFolder` do explorer, abre a
  primeira aba na pasta dele; pastas e arquivos da linha de comando ou soltos no ícone do Dock
  (`application(_:open:)`, o Dock só com o pacote .app do plano 7): pasta vira workspace, arquivo
  abre numa aba. `FileOpener.swift` decide onde um arquivo abre (mídia pelo tipo, o resto no editor), passa as
  mudanças do disco aos editores abertos e monta a aparência do editor (`EditorLooks`).
- A casca da janela, no estilo do Terax: título transparente com barra de ferramentas compacta
  (38 pt, botões da janela centrados); `TitleBarView.swift` (painel lateral, paleta, abas, "+",
  busca, todos por comando), `WorkspaceView.swift` (painéis arredondados de `PanelView.swift`,
  painel lateral recolhível, barra de status) e `SidebarView.swift` (a árvore do explorer; o source control entra no plano 6). O explorer é criado
  junto com os comandos, antes de as configurações montarem os atalhos.
  As cores vêm do tema; a cor da moldura vai na janela, não numa camada da view, porque uma
  camada pintada cobria os botões da janela.
- `WindowBackdrop.swift`: imagem de fundo atrás da área do terminal (desfoque calculado uma vez) e,
  com vibrância, a moldura fosca; depois de ligar, os botões da janela voltam para cima da camada.
- Abrir para teste com CADEX_BACKGROUND=1: a janela aparece sem tomar o foco do teclado. Abas, spaces e a paleta
  entram aqui conforme as features existirem.

## Como validar
- `make app` compila; `make run` abre a janela com um shell.
