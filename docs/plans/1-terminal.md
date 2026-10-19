# Plano 1 — Terminal completo

Spec: `docs/spec/terminal.md` · Features: terminal (núcleo e app) · Seis fases, uma por sessão.

## O que eu quero
O terminal no nível do Terax no uso do dia a dia, mais leve. Ao fim do plano, numa janela só (abas
e divisões são o plano 2):
- **A. Teclas pelo núcleo:** setas em modo de aplicação (vim, less, htop), F1–F12, Home/End/PgUp/PgDn
  com modificadores, protocolo de teclado do kitty quando o programa pede, Option como Meta
  (configurável). Mantém o que já funciona: edição estilo Mac (⌥← ⌥→ ⌘← ⌘→ ⌥⌫ ⌘⌫ ⌥⌦ ⌘⌦),
  acentos por tecla morta (ABNT2), ⌘K reservado à paleta, ⌘L limpa.
- **B. Rolagem, seleção e copiar:** histórico de 10 mil linhas rolado por trackpad e roda; digitar
  volta ao fim; ⌘↑/⌘↓ vão ao topo/fim; arrastar seleciona, duplo clique palavra, triplo linha,
  Shift+clique estende; ⌘C copia (sem seleção, nada); ⌘A seleciona tudo; barra de rolagem discreta.
- **C. Colar e arrastar:** ⌘V na ordem da spec (arquivos do Finder viram caminhos escapados; imagem
  vira PNG temporário e cola o caminho; texto com bracketed paste); colar várias linhas num shell
  sem bracketed paste pede confirmação; arrastar arquivos cola os caminhos.
- **D. Links e busca:** ⌘ sobre URL ou caminho sublinha; ⌘+clique abre a URL no navegador (caminhos
  abrem no Cadex quando os visualizadores existirem, plano 5; até lá, no Finder); ⌘F abre a busca
  no painel, destaca todas as ocorrências, Enter/Shift+Enter navegam, Esc fecha.
- **E. Programas de tela cheia e modos:** eventos de mouse para quem pede (vim, htop, tmux), rolagem
  vira setas na tela alternativa, eventos de foco, título da janela pelo OSC 0/2, sino discreto
  (pisca a aba, sem som), cursor piscando quando o programa pede, reflow ao redimensionar.
- **F. Fechar e desempenho:** fechar a janela com processo em primeiro plano pede confirmação;
  `cat` de 100 MB não trava e Ctrl+C interrompe em menos de 1 s; só redesenha o que mudou.

## O que eu não quero
- Lógica de terminal no Swift: o estado e os modos estão no núcleo. O Swift desenha, converte
  eventos do macOS e chama a API C (ADR 0002). Tabela de sequências no Swift só para a edição estilo
  Mac, que é convenção do app.
- Tipos da libghostty fora de `core/features/terminal/model.zig`, `core/features/terminal/render.zig`
  e dos novos arquivos desta feature que precisarem dela (ADR 0003). O header C usa tipos nossos.
- Quebrar o que já existe: acentos por tecla morta, nitidez, edição estilo Mac.
- Copiar com espaços no fim das linhas ou com quebras falsas onde o terminal quebrou por largura.
- Arquivos temporários de imagem acumulando: apagar os de mais de 7 dias ao abrir.

## Como eu quero
**Onde estamos.** Núcleo (Zig): `core/features/terminal/` com session.zig (shell num PTY, thread de
leitura, mutex da libc, callbacks), model.zig (libghostty-vt Terminal + TerminalStream, respostas
ao programa, agrupamento de grafemas ligado), render.zig (RenderState → quadro plano com RGB, UTF-8
e flags), pty.zig, shell_env.zig, c_api.zig; contrato em `core/include/cadex.h`. App (Swift):
`apps/macos/features/terminal/` com TerminalView.swift (MTKView, teclado, ⌘V texto, ⌘L, ⌘K),
TerminalSession.swift (API C, callbacks levados à thread principal), KeyEncoding.swift (tabela
fixa + edição Mac), QuadBuilder.swift (quadro → quads), TerminalRenderer.swift (Metal),
GlyphAtlas.swift (CoreText → textura), TerminalFont.swift, TerminalTextInput.swift.

**libghostty-vt** (MIT, fonte em core/zig-pkg/ghostty-*/ depois de um `zig build`; exemplos em
example/): teclas em src/input/key_encode.zig (exemplo c-vt-encode-key); colagem em
src/input/paste.zig (encode, isSafe; exemplo c-vt-paste); mouse em src/input/mouse_encode.zig
(c-vt-encode-mouse); rolagem em src/terminal/Terminal.zig (scrollViewport); seleção em
src/terminal/SelectionGesture.zig e Screen.zig (selectWord, selectLine, selectAll, selectionString;
exemplos c-vt-selection e c-vt-selection-gesture); busca em src/terminal/search/ (c-vt-search);
links pelos hyperlinks OSC 8 das células e detecção de URL no texto; recursos ligados no build em
`core/build.zig` (vt_features).

**Armadilhas já pegas (não repetir):**
- Campos `style` e `grapheme` do RenderState são indefinidos em certas células: ver
  `core/features/terminal/render.zig:translateCell`.
- Fatia vazia do Zig não veio do malloc: nunca entregar o ponteiro ao app (ver
  `core/features/terminal/c_api.zig:cadex_terminal_copy_text`).
- Callback do núcleo roda na thread de leitura e não pode chamar `cadex_terminal_close`.
- Struct nova compartilhada entre Zig e C: `_Static_assert` de tamanho nos dois lados, como
  cadex_terminal_frame. Struct nova enviada à GPU: conferir o stride (o `SIMD3` do Swift tem 16
  bytes; ver `apps/macos/features/terminal/TerminalRenderer.swift:QuadInstance`).
- Testes Swift são um executável (`apps/macos/shared/checks/Checks.swift` explica: sem Xcode o
  `swift test` não roda nada). Testes Zig com shell de verdade silenciam logs com
  `testing.log_level = .err`.

**Fases** (cada uma: núcleo + API C + app + testes + commit):
- **A.** Novo core/features/terminal/input.zig: tipos nossos Key (setas, Enter, Tab, Backspace,
  Escape, Delete, Home, End, PageUp, PageDown, Insert, F1–F12) e Mods; converte para o KeyEvent da
  libghostty e chama encodeKey com os modos atuais, sob o lock; escreve no PTY. API C
  `cadex_terminal_key(terminal, key, mods, text, len)` e constantes CADEX_KEY_* e CADEX_MOD_*.
  KeyEncoding.swift passa a só mapear keyCode → CADEX_KEY_* (a edição Mac fica). Option como
  Meta: Option+letra vai como Alt ao núcleo em vez do sistema de entrada.
- **B.** API C de rolagem (delta em linhas; topo; fim) e de seleção (press/drag/release com célula,
  número de cliques e shift; tudo; limpar; copiar texto). O quadro ganha o tamanho do histórico, a
  posição visível e a flag CADEX_CELL_SELECTED. App: scrollWheel acumulando pixels → linhas;
  mouseDown/Dragged/Up convertendo posição em célula (descontando padding e escala); autoscroll ao
  arrastar fora; ⌘C/⌘A; QuadBuilder pinta a seleção e a barra de rolagem. Digitar limpa a seleção
  e volta ao fim.
- **C.** API C de colagem (paste com bracketed paste; is_safe) e um escapador de caminhos para shell
  no núcleo (aspas simples, tratando aspa no nome), usado por colar e arrastar. App: ⌘V segue a
  ordem da spec com NSPasteboard; imagem em FileManager.temporaryDirectory/cadex-paste/; alerta
  "Colar N linhas?" com "não perguntar de novo"; registerForDraggedTypes([.fileURL]).
- **D.** Links: o núcleo responde "o que há na célula (col, linha)" (hyperlink OSC 8 ou URL/caminho
  detectado na linha); app sublinha com ⌘ pressionado e abre com NSWorkspace. Busca: API C
  iniciar/próxima/anterior/encerrar; quadro marca ocorrências (CADEX_CELL_MATCH e
  CADEX_CELL_MATCH_ACTIVE); barra de busca nativa no topo do painel.
- **E.** Núcleo informa se o programa quer mouse e em que formato; app manda cliques, arrastos e
  rolagem pelo encodeMouse do núcleo quando ativo (Shift força seleção local). Rolagem na tela
  alternativa vira setas. Foco (entrada e saída) codificado pelo núcleo. Callback de título
  (effects.title_changed) e de sino; título vai para a janela; sino pisca. Cursor piscando no app
  com timer só enquanto visível. Conferir reflow com teste.
- **F.** Confirmação ao fechar com processo em primeiro plano (`cadex_terminal_has_foreground_process`
  já existe). Desempenho: medir `cat` de 100 MB; se travar, limitar o trabalho por quadro e usar a
  marca de linhas sujas do RenderState para não recriar quads de linhas iguais.

## Como validar
- `make check` passa ao fim de cada fase.
- Testes do núcleo por fase: seta ↑ dá `ESC [ A` e, depois de `ESC [ ? 1 h`, `ESC O A`; Ctrl+→ dá
  `ESC [ 1 ; 5 C`; rolar 50 linhas mostra o texto certo; seleção de palavra, linha e tudo; copiar
  linha quebrada por largura volta inteira; escapador com espaço, aspa, acento e emoji; colagem com
  bracketed paste cercada por `ESC [ 200 ~` e `ESC [ 201 ~`; busca acha ocorrências no histórico;
  mouse em modo SGR codificado certo.
- Testes do app: posição→célula com padding e escala 2; mapeamento de teclas; ordem do ⌘V.
- Manual, com print da janela (ver `docs/plans/README.md`): os critérios de aceite de
  `docs/spec/terminal.md`, mais vim/htop/less com setas e F-keys, `seq 1 1000` rolando até o 1,
  colar print e arquivo com espaço, ⌘F achando texto do histórico, ⌘+clique numa URL.
- Ao terminar: marcar os critérios da spec, atualizar os `CLAUDE.md` do terminal (núcleo e app) e o
  status na tabela de `docs/plans/README.md`.
