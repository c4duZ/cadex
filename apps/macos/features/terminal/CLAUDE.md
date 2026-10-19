# terminal (app macOS)

## O que eu quero
- Desenhar o terminal em Metal, com fonte, cursor, seleção, links e true color.
- Teclado completo, colagem (texto, caminhos de arquivo e imagem como arquivo temporário), arrastar
  arquivos. A ordem da colagem está em `../../../../docs/spec/terminal.md`.
- Busca dentro do terminal.
- Comportamento inicial igual ao terminal do Terax, e de preferência mais leve.
- Texto nítido: desenhado na resolução real da tela, alinhado aos pixels. SF Mono 13 pt por padrão.

## O que eu não quero
- Modo em blocos e terminal privado.
- Lógica de terminal no app: o estado vem do núcleo.
- Redesenhar a tela inteira quando só uma linha mudou.
- Texto borrado: renderizar numa resolução e escalar depois.
- ⌘K indo para o shell: abre a paleta. Limpar a tela é ⌘L.

## Como eu quero
- Só desenha e repassa entrada; fala com a feature terminal do núcleo.
- Teclado: `KeyEncoding.swift` só decide a rota (edição estilo Mac, tecla para o núcleo via
  `cadex_terminal_key`, ou texto pelo sistema de entrada, que compõe acentos). Sequências de
  terminal só na tabela da edição estilo Mac, que é convenção do app. Option esquerdo como Meta
  pelo default "terminal.optionAsMeta" (desligado; a janela de configurações vai gravá-lo).
- Mouse em `TerminalMouse.swift`: roda e trackpad viram linhas (`TerminalGeometry.swift`,
  ScrollAccumulator), clique e arrasto vão à seleção do núcleo, timer de autoscroll a cada 15 ms.
  `TerminalGeometry.swift` converte pontos em célula (padding e escala).
- Área de transferência: só ⌘C escreve nela. "Copiar ao selecionar" pelo default
  "terminal.copyOnSelect" (desligado); ligado, copia ao soltar o botão com seleção feita.
- Colar e arrastar em `TerminalPaste.swift`; a ordem do ⌘V (arquivos, imagem, texto) em
  `PasteboardContent.swift`. Imagem vira PNG em cadex-paste/ dentro da pasta temporária, apagado
  depois de 7 dias (ao abrir o app). Várias linhas sem bracketed paste pedem confirmação, que o
  default "terminal.confirmMultilinePaste" desliga.
- Links em `TerminalLinks.swift`: com ⌘ pressionado, o link sob o ponteiro é sublinhado; ⌘+clique
  abre a URL no navegador e mostra o arquivo no Finder (até os visualizadores, plano 5).
- Busca: `TerminalFind.swift` liga o ⌘F ao núcleo; `TerminalFindBar.swift` é a barra no canto
  superior direito ("3 de 12", ↩ próxima, ⇧↩ anterior, Esc fecha).
- ⌘C, ⌘A, ⌘F, ⌘↑ e ⌘↓ estão no `performKeyEquivalent` até a paleta existir (plano 2).
- Ações do terminal (limpar, buscar, copiar, colar) registradas como comandos.
- Status: janela com um shell, desenho em Metal (SF Mono, nítido), teclado básico e colagem de
  texto, teclas pelo núcleo (modo de aplicação, F-keys, modificadores, kitty, Option como Meta).
  Rolagem com barra discreta, seleção (arrastar, duplo e triplo clique, Shift+clique, ⌘A) e ⌘C.
  Colagem de texto (bracketed paste), arquivos e imagem, e arrastar arquivos.
  Links com ⌘ e busca (⌘F) no histórico.

## Como validar
- `make macos-test` passa.
