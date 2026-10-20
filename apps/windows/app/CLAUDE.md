# app — entrada do app Windows

## O que eu quero
- Só o ponto de entrada: abrir a janela, rodar o laço de mensagens e ligar as features.

## O que eu não quero
- Lógica de feature aqui: cada coisa que a janela mostra vem de uma feature.
- Win32 declarado aqui: as declarações moram em `../shared/win32/`.

## Como eu quero
- `main.zig`: abre a janela e roda o laço. Chama o núcleo pelo módulo `cadex` (o
  `../../../core/include/cadex.h` traduzido no `../build.zig`); hoje só confere que ele está ligado.
- `window.zig`: a classe e o procedimento da janela principal, e o laço de mensagens.
- `Cadex.manifest`: DPI por monitor v2, UTF-8 como página de código e caminhos longos, embutido
  no exe pelo `../build.zig`.
- Status: esqueleto (plano 10, fase A). A barra de título própria e o Mica são a fase B.

## Como validar
- `make windows-app` compila x64 e arm64; `make windows-run` abre na VM.
