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
- Programas que pedem mouse recebem cliques, arrastos e a roda (`TerminalMouse.swift`); Shift
  força a seleção local. Foco, título da janela, sino (pisca a view, sem som) e cursor piscando em
  `TerminalSignals.swift`; o timer do cursor só roda com a janela na frente e o programa pedindo.
- Quem segura o terminal (aba, painel) usa `TerminalClose.swift` (hasForegroundProcess,
  currentDirectory, closeSession) e os ganchos onShellExit, onActivity e onProgramTitle do
  `TerminalView`; a pergunta ao fechar com programa rodando é da feature tabs. Botão "Cancelar" de
  alerta ganha Esc à mão: o NSAlert só dá Esc a "Cancel".
- Preferências: `TerminalPreferences.swift` (fonte, cursor, histórico, Option como Meta, copiar ao
  selecionar, perguntas, shell), preenchida pelo app a partir do settings.json; fonte e cursor
  valem na hora, histórico e shell nos terminais novos.
- Cores: `TerminalAppearance.swift` guarda as cores que todo terminal usa (quem aplica o tema
  preenche `current`); cada `TerminalView` passa ao núcleo e usa a cor de seleção do tema.
- Comandos do terminal em `TerminalActions.swift` (terminal.clear, terminal.find,
  terminal.scroll-top, terminal.scroll-bottom): ações da cadeia de responders que o `TerminalView`
  com foco responde, junto com copy:, paste: e selectAll: dos comandos de edição. O
  `performKeyEquivalent` só trata a edição estilo Mac (⌘← ⌘→ ⌘⌫ ⌘⌦), que é entrada para o shell.
- Ações do terminal (limpar, buscar, copiar, colar) registradas como comandos.
- Status: janela com um shell, desenho em Metal (SF Mono, nítido), teclado básico e colagem de
  texto, teclas pelo núcleo (modo de aplicação, F-keys, modificadores, kitty, Option como Meta).
  Rolagem com barra discreta, seleção (arrastar, duplo e triplo clique, Shift+clique, ⌘A) e ⌘C.
  Colagem de texto (bracketed paste), arquivos e imagem, e arrastar arquivos.
  Links com ⌘ e busca (⌘F) no histórico. Mouse para programas, foco, título, sino e cursor
  piscando. Desempenho medido em 2026-10-19: `cat` de 100 MB em 0,95 s,
  Ctrl+C sob saída contínua em menos de 0,2 s; o redesenho por linha suja ficou para quando
  medir lentidão.

## Como validar
- `make macos-test` passa.
