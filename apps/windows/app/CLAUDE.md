# app — entrada do app Windows

## O que eu quero
- O ponto de entrada e a casca: a janela, o quadro, e a ligação entre as features, como o
  `../../macos/app/CLAUDE.md` faz no Mac.

## O que eu não quero
- Lógica de feature aqui: cada coisa que a janela mostra vem de uma feature, pela porta de entrada.
- Win32 declarado aqui: o SDK vem de `../shared/win32/`.

## Como eu quero
- `main.zig`: cria o App e abre na pasta da linha de comando (ou na pessoal); CADEX_BACKGROUND=1
  mostra a janela sem tomar o foco.
- `app.zig`: App, tudo o que a janela guarda, e o quadro (barra de título, painéis, barra de
  status, sobreposições); o escolhido na paleta roda depois do quadro.
- `window.zig` e `window_messages.zig`: a janela Win32 com o cliente cobrindo o frame (cantos e
  sombra do DWM, Mica), bordas e título por hit test, maximizar como HTMAXBUTTON (Snap Layouts),
  mouse, roda, texto (pares substitutos), IME, arquivos soltos, DPI e tema. As teclas vão ao app
  antes do TranslateMessage (`window.zig:run`): atalho ou terminal que usou a tecla não gera WM_CHAR.
- `chrome.zig`: a barra de título (busca/paleta, abas, "+", configurações e os botões do Windows
  com a fonte Segoe Fluent Icons); os botões viram buracos no título para o hit test.
- `wiring.zig`: o Delegate da janela (teclas: atalhos, depois o terminal com foco), o Host das abas
  (criar terminal, avisos da thread de leitura por PostMessage), e as configurações e o tema
  aplicados a cada feature.
- `app_commands.zig`: palette.open, settings.open, app.quit, app.hide, window.new (outro processo),
  edit.* (para o terminal ou o documento com foco), terminal.clear/scroll-top/scroll-bottom, e o
  registro dos comandos das features. `settings_page.zig`: a página de configurações.
- `Cadex.manifest`: DPI por monitor v2, UTF-8 como página de código e caminhos longos.

## Como validar
- `make windows-app` compila x64 e arm64 e os testes; `make windows-run` abre na VM.
