# Plano 10 — Janela e terminal no Windows

Depende de: plano 9 · Features: terminal (app Windows) · Decisões:
`docs/adr/0012-windows-zig-win32-d3d11.md`, `docs/adr/0003-libghostty-vt-terminal-model.md` · Spec:
`docs/spec/terminal.md` (as notas de Windows que já existem nela viram critério).

## O que eu quero
- Cadex.exe abre uma janela Windows 11 com um terminal completo, no mesmo nível do Mac: cores,
  estilos, cursor, seleção, rolagem, links, busca, colagem, mouse, teclado e IME.
- Abrir em menos de 150 ms e gastar pouca memória com um terminal aberto (medir e registrar, como o
  plano 7 fez no Mac).
- Texto nítido em qualquer escala (100% a 300%), trocando de monitor sem borrar (DPI por monitor v2).
- Janela com a cara do Cadex: barra de título própria desenhada pelo app, Mica no fundo, os botões
  de minimizar, maximizar e fechar do Windows, Snap Layouts funcionando no botão de maximizar.

## O que eu não quero
- Texto desenhado pelo GDI ou fonte em bitmap: DirectWrite com atlas de glifos, como o Metal no Mac.
- Redesenhar a tela inteira a cada byte do shell: só quando o modelo do núcleo marcar sujo, no ritmo
  do monitor.
- Teclas do terminal roubadas pelo app: Ctrl+letra é do programa no terminal (spec de shortcuts).
- Arquivo acima de 500 linhas, ou Win32 chamado fora de apps/windows/shared/win32 e da feature.

## Como eu quero
**Onde estamos.** `apps/windows/` só tem o `apps/windows/CLAUDE.md`. O terminal do Mac, para conferir
o comportamento (não o código), está em `apps/macos/features/terminal/CLAUDE.md`.

**Fases:**
- **A. Esqueleto.** apps/windows/build.zig (alvo Windows 11 x64 e arm64, subsistema windows,
  manifesto com DPI por monitor v2 e UTF-8 como página de código), wWinMain, laço de mensagens,
  o cadex.h importado e libcadex.a ligada. `make windows-app` compila daqui; `make windows-run` manda
  para a VM e abre. Primeiras declarações em apps/windows/shared/win32.
- **B. Janela.** Barra de título própria (WM_NCCALCSIZE, WM_NCHITTEST com HTMAXBUTTON para os Snap
  Layouts), Mica por DwmSetWindowAttribute, cantos arredondados, tema claro e escuro do sistema.
- **C. Desenho.** Direct3D 11 com swap chain flip, atlas de glifos do DirectWrite (Cascadia Mono, que
  vem no Windows 11, como padrão no lugar da SF Mono), quads instanciados para fundo, glifo,
  sublinhado, cursor e seleção. Ritmo pelo DwmFlush ou pelo waitable da swap chain.
- **D. Teclado e IME.** WM_KEYDOWN/WM_CHAR com ToUnicodeEx, Alt como Meta, codificação de teclas do
  núcleo, teclado ABNT2 com acentos mortos, IME pelo IMM32 com a composição desenhada no cursor.
- **E. Resto do terminal.** Área de transferência do Win32 (texto e arquivos arrastados viram
  caminhos com aspas do PowerShell), colagem com o aviso de várias linhas, mouse e rolagem
  (precisão do touchpad), links com Ctrl+clique, busca no terminal, sino, fechar com processo rodando.
- **F. Medir.** Tempo de abertura, memória com um terminal e tamanho do `.exe`, registrados no README.

## Andamento (2026-10-20)
Fases A a E escritas e compilando para x64 e arm64 (o dono pediu para terminar tudo e testar depois
no Windows): janela com frame próprio, Snap Layouts e Mica (`apps/windows/app/window.zig`), desenho
por Direct2D/DirectWrite também no terminal (ADR 0012 revisto), teclado com AltGr, acentos e IME,
mouse, links, busca, colagem. A fase F (medir) e toda a conferência dependem da VM.

## Como validar
- `make check` passa no Mac; `make windows-core-test` e os testes do app passam na VM.
- Na VM: vim, htop do WSL, `git log` paginado, cores de 24 bits, emoji, CJK, acentos no ABNT2,
  IME japonês, trocar escala de 100% para 200% sem borrar, Snap Layouts no botão de maximizar.
- Status na tabela de `docs/plans/README.md`.
