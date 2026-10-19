# app — entrada do app macOS

## O que eu quero
- Só o ponto de entrada: criar o NSApplication, as janelas e ligar as features.

## O que eu não quero
- Lógica de feature aqui. Cada coisa que a janela mostra vem de uma feature, pela porta de
  entrada dela (os tipos `public` do módulo).

## Como eu quero
- `PaletteWiring.swift`: a paleta nas cores do tema, os prefixos do ⌘K (`/` arquivos, `#` texto,
  `@` abas e spaces) e as aberturas (`openers`), primeiro no ⌘K e no menu do "+" das abas.
- `SpacesWiring.swift`: os spaces na janela (abas de cada space ligadas à barra de status e ao
  preview, documentos reabertos, pasta do workspace devolvida); `tabs` em `main.swift` é sempre a
  do space que aparece, então os comandos agem nela. Sair e fechar a janela perguntam uma vez por
  todos os spaces e salvam.
- `FolderFollow.swift`: o workspace segue o terminal com foco; a cada `cd` vai para a raiz do
  repositório git da pasta (ou a própria pasta), a menos que explorer.followTerminal desligue.
- `main.swift` registra os comandos de cada feature (e o view.toggle-sidebar da casca), monta menu e
  atalhos a partir deles, e abre a janela. Como delegate, pergunta às abas antes de fechar a janela
  ou sair (shouldCloseAll). Liga a barra de status ao terminal com foco. Cria o `WorkspaceFolder` do explorer, abre a
  primeira aba na pasta dele; pastas e arquivos da linha de comando ou soltos no ícone do Dock
  (`application(_:open:)`, o Dock só com o pacote .app do plano 7): pasta vira workspace, arquivo
  abre numa aba, endereço http(s) abre no preview. `FileOpener.swift` decide o que abre (mídia pelo
  tipo, o resto no editor; diffs do git num DiffDocument, o histórico num HistoryDocument que recebe
  as mudanças em .git, páginas web num PreviewDocument) e onde: ao lado do painel com foco ou em
  nova aba, por general.openFiles (opensBeside em `SettingsBridge.swift`), ou pela escolha do explorer; quem
  pede (o histórico abrindo um diff) fica no painel dele. `makeDocument(identity:)` refaz os
  documentos salvos nos spaces. Passa as mudanças do disco aos documentos abertos e monta a aparência do editor (`EditorLooks`).
- A casca da janela, no estilo do Terax: título transparente com barra de ferramentas compacta
  (38 pt, botões da janela centrados); `TitleBarView.swift` (um grupo à esquerda com painel
  lateral, busca/paleta "⌘K" e spaces, o space só o ícone de pilha com um space e o nome com mais;
  depois as abas, "+" e as configurações à direita; cada controle um `TitleBarButton.swift` de
  26 pt com fundo ao passar e ao clicar,
  busca, todos por comando), `WorkspaceView.swift` (painéis arredondados de `PanelView.swift`,
  painel lateral recolhível, barra de status) e `SidebarView.swift` (duas páginas, Arquivos e Git, trocadas por abas largas embaixo do painel, como no Terax, que rodam explorer.focus e git.show). O explorer é criado
  junto com os comandos, antes de as configurações montarem os atalhos.
  As cores vêm do tema; a cor da moldura vai na janela, não numa camada da view, porque uma
  camada pintada cobria os botões da janela.
- Tela cheia: a barra de ferramentas (vazia, só dá a altura da barra de título) some ao entrar e
  volta ao sair, porque o macOS a punha numa faixa por cima da barra do app. Tamanho mínimo da
  janela 480×300.
- `WindowBackdrop.swift`: imagem de fundo atrás da área do terminal (desfoque calculado uma vez) e,
  com vibrância, a moldura fosca; depois de ligar, os botões da janela voltam para cima da camada.
- Sem pacote .app (make run), `main.swift` põe o ícone de `docs/cadex-icon.png` no Dock; no .app ele
  vem do AppIcon.icns.
- Abrir para teste com CADEX_BACKGROUND=1: a janela aparece sem tomar o foco do teclado. Abas, spaces e a paleta
  entram aqui conforme as features existirem.

## Como validar
- `make app` compila; `make run` abre a janela com um shell.
