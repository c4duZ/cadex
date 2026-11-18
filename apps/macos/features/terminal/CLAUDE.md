# terminal (app macOS)

## O que eu quero
- Desenhar o terminal em Metal, com fonte, cursor, seleção, links e true color.
- Teclado completo, colagem (texto, caminhos de arquivo e imagem como arquivo temporário), arrastar
  arquivos. A ordem da colagem está em `../../../../docs/spec/terminal.md`.
- Busca dentro do terminal.
- Comportamento de um terminal moderno, e de preferência mais leve.
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
  depois de 7 dias (ao abrir o app), pelo `TempImageStore` compartilhado
  (`../../shared/temp-images/CLAUDE.md`). Várias linhas sem bracketed paste pedem confirmação, que o
  default "terminal.confirmMultilinePaste" desliga.
- Links em `TerminalLinks.swift`: com ⌘ pressionado, o link sob o ponteiro é sublinhado; ⌘+clique
  abre a URL no navegador e mostra o arquivo no Finder (até os visualizadores, plano 5).
- Imagem colada: `TerminalPastedImages.swift` liga a etiqueta `[Image #N]` que o agente mostra ao
  PNG da colagem (a primeira etiqueta nova em até 30 s; regra pura em `PastedImageTags.swift`,
  testada). Passar o mouse mostra `PastedImageHover.swift`; clique sem modificador abre pelo
  `onOpenFile` de quem segura o terminal. Comandos terminal.open-pasted-image-beside e
  terminal.open-pasted-image-in-tab (só no Mac por enquanto; a última imagem colada na aba).
- Preview: `TerminalOffer.swift` mostra "Abrir no preview" no canto de baixo por 10 s
  quando o núcleo acha um servidor local na saída (onLocalURL da sessão); só aparece se quem
  segura o terminal pôs `onOpenPreview`. Endereço que não é deste Mac (o núcleo reporta também
  `http://<nome>:<porta>` de um nome que pode ser da tailnet, plano 23) só com o sim do app
  (TerminalView.isOwnHost).
- Colar vindo de outra feature: `TerminalAppPaste.swift` (`pasteFromApp`, o elemento escolhido no
  preview), bracketed e sem Enter, sem perguntar; recusa (false) quando a colagem não é segura e
  quem chamou copia. Imagens vão depois do texto, cada caminho numa colagem própria e ligadas à
  etiqueta `[Image #N]` como as do ⌘V.
- Busca: `TerminalFind.swift` liga o ⌘F (comando edit.find da paleta, que chega pelo
  `showFind(_:)` de quem tem o foco) ao núcleo; `TerminalFindBar.swift` é a barra no canto
  superior direito ("3 de 12", ↩ próxima, ⇧↩ anterior, Esc fecha).
- Programas que pedem mouse recebem cliques, arrastos e a roda (`TerminalMouse.swift`); Shift
  força a seleção local. Foco, título da janela, sino (pisca a view, sem som) e cursor piscando em
  `TerminalSignals.swift`; o timer do cursor só roda com a janela na frente e o programa pedindo.
- Quem segura o terminal (aba, painel) usa `TerminalClose.swift` (hasForegroundProcess,
  currentDirectory, closeSession) e os ganchos onShellExit, onActivity, onProgramTitle e onAgentStatus do
  `TerminalView`; a pergunta ao fechar com programa rodando é da feature tabs. Botão "Cancelar" de
  alerta ganha Esc à mão: o NSAlert só dá Esc a "Cancel".
- Terminais mantidos (terminal.keepSessions, plano 19 fase E2): `TerminalDaemon.swift` (o programa,
  o socket, a pasta da saída gravada, iniciar uma vez, os nomes `<instância>-<uuid>`,
  `closeUnclaimed` depois de restaurar) e `TerminalKeep.swift` (`openSession`: abrir no daemon, religar
  por `keptID`, um shell novo com a saída gravada quando o daemon não tem mais, PTY próprio se o
  daemon falhar; `detachSession`). O `TerminalView` guarda `keptID`.
- Preferências: `TerminalPreferences.swift` (fonte, cursor, histórico, Option como Meta, copiar ao
  selecionar, perguntas, shell, keepSessions), preenchida pelo app a partir do settings.json; fonte e cursor
  valem na hora, histórico e shell nos terminais novos.
- Cores: `TerminalAppearance.swift` guarda as cores que todo terminal usa (quem aplica o tema
  preenche `current`); cada `TerminalView` passa ao núcleo e usa a cor de seleção do tema.
- Comandos do terminal em `TerminalActions.swift` (terminal.clear,
  terminal.scroll-top, terminal.scroll-bottom): ações da cadeia de responders que o `TerminalView`
  com foco responde, junto com copy:, paste: e selectAll: dos comandos de edição. O
  `performKeyEquivalent` só trata a edição estilo Mac (⌘← ⌘→ ⌘⌫ ⌘⌦), que é entrada para o shell.
- Ações do terminal (limpar, buscar, copiar, colar) registradas como comandos.
- GPU compartilhada (`TerminalGPU.swift`): uma fila de comandos e um pipeline por device para o app,
  e um atlas de glifos por fonte e escala, dividido pelos terminais com a mesma fonte e solto quando
  nenhum usa. O `TerminalView` (sessão, teclado, mouse, seleção, busca) desenha numa
  `TerminalCanvas.swift`, a `MTKView` que só existe com ele numa janela: aba escondida solta a
  canvas e o pool de drawables da camada; ao voltar, uma canvas nova desenha o primeiro quadro na
  transação da camada, sem piscar. A canvas não recebe eventos. Cada aba escondida pesava ~43 MB,
  agora 0 a 1 MB (`make perf`, 2026-10-21).
- Leitura (plano 15, fase C): `TerminalFont.swift` monta a fonte com a `Typesetting` (altura de linha,
  espaçamento centrado na célula, recursos OpenType); `TerminalShaders.swift` aplica o contraste
  mínimo no vertex shader, com o fundo de cada letra no `QuadInstance`; com "calt"/"liga",
  `QuadBuilder+Ligatures.swift` acha as sequências de símbolos e o joins do `GlyphAtlas.swift` diz se a fonte as
  junta, e a sequência vira uma imagem só. Mudar fonte refaz o atlas; mudar o contraste, não
  (`fontKey`).
- Status: janela com um shell, desenho em Metal (SF Mono, nítido), teclado básico e colagem de
  texto, teclas pelo núcleo (modo de aplicação, F-keys, modificadores, kitty, Option como Meta).
  Rolagem com a barra do mockup (marcas e polegar), seleção (arrastar, duplo e triplo clique, Shift+clique, ⌘A) e ⌘C.
  Colagem de texto (bracketed paste), arquivos e imagem, e arrastar arquivos.
  Links com ⌘ e busca (⌘F) no histórico. Mouse para programas, foco, título, sino e cursor
  piscando. Desempenho medido em 2026-10-19: `cat` de 100 MB em 0,95 s,
  Ctrl+C sob saída contínua em menos de 0,2 s; o redesenho por linha suja ficou para quando
  medir lentidão.

- Integração do zsh (plano 22, fase C; `../../../../docs/spec/terminal.md`):
  `shell-integration/zsh/.zshenv` é a pasta `ZDOTDIR` que o núcleo põe no zsh das abas: devolve o
  `ZDOTDIR` do dono, define a função `claude` (roda `$CADEX_TOOLS claude`, senão o `claude` de
  verdade) e lê o `.zshenv` do dono. `TerminalShellIntegration.swift` acha a pasta (Resources do
  pacote, onde o `../../packaging/build.sh` a copia, ou ao lado da fonte) e o app põe
  CADEX_ZSH_INTEGRATION e CADEX_TOOLS no próprio ambiente antes de qualquer terminal e do daemon
  (`../../app/main.swift`). TerminalSession.shellPid (e o do `TerminalView`) é o pid do shell, com que
  o app reconhece um `cadex claude` vindo de uma aba dele (`../../app/TypedClaudeWiring.swift`).
- `ClaudeDress.swift` (plano 33, fases B e C; `../../../../docs/spec/terminal.md`, As cores e as
  formas do Claude Code): enquanto o Claude se reporta pelo OSC 7501, o plano de cada quadro troca
  as cores fixas dele pelas do tema (`Palette`, tirada do `TerminalAppearance`), esconde o mascote e
  a linha do modo, põe o modo à direita da status line, e as formas (a caixa da entrada, o bloco da
  mensagem do dono) vão como retângulos arredondados (quad do tipo 3 no `TerminalShaders.swift`).
  O `QuadBuilder.swift` desenha com o plano (DrawOverlay.dressClaude); o texto não muda.
- `TerminalScrollbar.swift` (plano 28 fase D): a barra de rolagem do mockup Pane, uma coluna de 8 pt
  que o painel põe na borda da caixa (`scrollbar`), com o polegar e as marcas: cinza onde o dono
  mandou uma mensagem ao agente (Enter com agente rodando), âmbar onde o agente passou a esperar;
  clique e arrasto levam a vista até lá. A barrinha Metal de antes, que só aparecia rolando, saiu do
  `QuadBuilder.swift`. `footBar`: uma barra no pé do painel (o Review e Pick winner de um concorrente). `footCard`: um cartão que o app põe no pé do painel (o aviso de limite da conta, plano 33).
  `innerPadding`: o respiro que o terminal guarda em volta do texto, que a caixa desconta.
- `screenLines()` (em `TerminalPastedImages.swift`): o texto da tela, linha a linha, do mesmo quadro
  do desenho; para os testes e o CADEX_PERF_DUMP_SCREEN (a captura da janela não pega o Metal).
- `TerminalCommand.swift` (plano 29): o comando que roda e o último (TerminalView.command), lido do
  núcleo a cada mudança de título e carimbado com a hora, o endereço local que ele mostrou
  (`served`) e `openServed`; `shortName` ("npm run dev" de `PATH=… /usr/bin/npm run dev`), a
  duração e a porta. A integração do zsh manda as marcas OSC 133 por add-zsh-hook. A captura de
  teste desenha o terminal por `snapshotImage` (TerminalRenderer.image, fora da tela).
- `TerminalTypeAhead.swift` (plano 24, fase F): `typeWhenReady`, o texto que o app digita numa aba
  (o agente do New Task, um despacho, uma automação, o ssh) espera a primeira saída do shell e
  300 ms de silêncio, no máximo 5 s desde a abertura: o zsh descarta a entrada pendente ao montar a
  linha de edição, e um shell rápido perdia o comando (achado pelo `make perf`, 2026-11-16).
- `TerminalNotify.swift`: a notificação que um programa pediu (OSC 777, OSC 9) sai como o aviso
  TerminalView.programDidNotify; `isLookedAt` diz se você olha o terminal. O app posta
  (`../../app/ProgramNotifications.swift`).
- Hibernação (plano 19, fase F), em `TerminalAgent.swift`: `agentResume` (o que traz o agente de volta,
  preenchido pelo app pelos hooks), `isHibernated`, `agentQuietSince` (desde quando está done ou
  idle) e o aviso `didTakeFocus`; `TerminalOffer.swift` mostra "Reiniciar" (`offerRestart`, roda
  `onRestartAgent`), que digitar tira.
- `TerminalAgent.swift` e `TerminalAgentStatus.swift` (plano 19): o que o agente disse ao terminal
  pelo OSC 7501 (TerminalSession.agentStatus), só enquanto um programa roda em primeiro plano, e
  "terminou sem você ver" até o terminal ganhar o foco.

## Como validar
- `make macos-test` passa. TerminalTests roda um zsh de verdade com a pasta da integração: os
  arquivos do dono (no `$HOME` e num `ZDOTDIR` próprio) e o `claude` chegando ao `cadex`; e o texto
  digitado num zsh recém-aberto esperando o prompt e rodando.
